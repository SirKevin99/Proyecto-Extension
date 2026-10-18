-- =========================================================
-- 17_auditoria.sql
-- Fase 5, paso 5.4: auditoría general (solo superadmin).
--
-- Decisiones aprobadas por Kevin (18/10):
-- - Tabla auditoria_cambios: cada alta, modificación o baja en
--   usuarios, eventos e inscripciones, con los campos que cambiaron
--   (antes / después), quién lo hizo, con qué rol y cuándo.
--   La carga un trigger: no depende de cada pantalla o función.
-- - Solo la lee el superadmin. Nadie la modifica ni la borra desde
--   la app (sin policies de escritura).
-- - Se registran también los marcajes de los alumnos.
-- - Altas desde la Edge Function crear-usuario (service_role, sin
--   auth.uid()): el autor sale de la columna nueva usuarios.creado_por,
--   que la función completa (opción B). Redesplegar crear-usuario
--   DESPUÉS de ejecutar este script.
-- - Acciones automáticas (pg_cron): sin autor ("Sistema (automático)").
-- - Se ignoran columnas derivadas o de compatibilidad (ruido).
-- - listar_auditoria(): une esta tabla con las auditorías previas
--   (correcciones de asistencia con motivo, cambios de horario,
--   restablecimiento de claves de validadores).
--   Para no duplicar, las modificaciones de inscripciones hechas por
--   admin/superadmin se muestran desde correcciones_asistencia (que
--   incluye el motivo), no desde auditoria_cambios.
--
-- Requiere: scripts 10 (_hora_local), 12, 13 y 16 (_es_superadmin).
-- Ejecutar DESPUÉS del 16. Todo en una transacción.
-- NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

-- 1. AUTOR DE LAS ALTAS ------------------------------------------
-- Con FK: los usuarios nunca se borran, así que es segura y documenta
-- la relación. Las filas existentes quedan con NULL (autor desconocido).
ALTER TABLE public.usuarios
  ADD COLUMN IF NOT EXISTS creado_por UUID
    REFERENCES public.usuarios(id) ON DELETE SET NULL;

-- 2. TABLA DE AUDITORÍA -------------------------------------------
-- realizado_por sin FK: un fallo de FK abortaría la operación auditada.
CREATE TABLE IF NOT EXISTS public.auditoria_cambios (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tabla          TEXT NOT NULL
                   CHECK (tabla IN ('usuarios', 'eventos', 'inscripciones')),
  registro_id    TEXT NOT NULL,
  operacion      TEXT NOT NULL
                   CHECK (operacion IN ('alta', 'modificacion', 'baja')),
  cambios        JSONB NOT NULL,   -- { campo: { "antes": ..., "despues": ... } }
  realizado_por  UUID,             -- NULL = sistema (cron)
  rol_actor      TEXT,             -- rol de quien lo hizo, en ese momento
  realizado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auditoria_cambios_fecha
  ON public.auditoria_cambios (realizado_en DESC);
CREATE INDEX IF NOT EXISTS idx_auditoria_cambios_registro
  ON public.auditoria_cambios (tabla, registro_id);
CREATE INDEX IF NOT EXISTS idx_auditoria_cambios_actor
  ON public.auditoria_cambios (realizado_por);

ALTER TABLE public.auditoria_cambios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auditoria_cambios_select_superadmin"
  ON public.auditoria_cambios;
CREATE POLICY "auditoria_cambios_select_superadmin"
  ON public.auditoria_cambios
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') = 'superadmin');

REVOKE ALL ON public.auditoria_cambios FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.auditoria_cambios TO authenticated;

-- 3. TRIGGER GENÉRICO ---------------------------------------------
-- Los argumentos del trigger (TG_ARGV) son las columnas a ignorar.
CREATE OR REPLACE FUNCTION public._auditar_cambio()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ant     JSONB := CASE WHEN TG_OP = 'INSERT' THEN '{}'::JSONB ELSE to_jsonb(OLD) END;
  v_nue     JSONB := CASE WHEN TG_OP = 'DELETE' THEN '{}'::JSONB ELSE to_jsonb(NEW) END;
  v_ignorar TEXT[] := COALESCE(TG_ARGV, '{}'::TEXT[]);
  v_cambios JSONB;
  v_actor   UUID := auth.uid();
  v_rol     TEXT;
BEGIN
  SELECT jsonb_object_agg(
           t.k,
           jsonb_build_object('antes', v_ant -> t.k, 'despues', v_nue -> t.k))
  INTO v_cambios
  FROM jsonb_object_keys(v_ant || v_nue) AS t(k)
  WHERE t.k <> ALL (v_ignorar)
    AND (v_ant -> t.k) IS DISTINCT FROM (v_nue -> t.k);

  -- Nada relevante cambió (p. ej. solo cupos_disponibles): no se registra.
  IF v_cambios IS NULL THEN
    RETURN NULL;
  END IF;

  -- Altas desde crear-usuario (service_role): el autor es creado_por.
  IF v_actor IS NULL AND TG_TABLE_NAME = 'usuarios' AND TG_OP = 'INSERT' THEN
    v_actor := NULLIF(v_nue ->> 'creado_por', '')::UUID;
  END IF;

  IF v_actor IS NOT NULL THEN
    SELECT u.rol INTO v_rol FROM usuarios u WHERE u.id = v_actor;
  END IF;

  INSERT INTO auditoria_cambios
    (tabla, registro_id, operacion, cambios, realizado_por, rol_actor)
  VALUES (
    TG_TABLE_NAME,
    COALESCE(v_nue ->> 'id', v_ant ->> 'id'),
    CASE TG_OP WHEN 'INSERT' THEN 'alta'
               WHEN 'UPDATE' THEN 'modificacion'
               ELSE 'baja' END,
    v_cambios,
    v_actor,
    v_rol
  );

  RETURN NULL;   -- trigger AFTER: el valor de retorno se ignora
END;
$$;

DROP TRIGGER IF EXISTS trg_auditoria_usuarios ON public.usuarios;
CREATE TRIGGER trg_auditoria_usuarios
  AFTER INSERT OR UPDATE OR DELETE ON public.usuarios
  FOR EACH ROW EXECUTE FUNCTION public._auditar_cambio();

DROP TRIGGER IF EXISTS trg_auditoria_eventos ON public.eventos;
CREATE TRIGGER trg_auditoria_eventos
  AFTER INSERT OR UPDATE OR DELETE ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public._auditar_cambio(
    'cupos_disponibles', 'activo');

DROP TRIGGER IF EXISTS trg_auditoria_inscripciones ON public.inscripciones;
CREATE TRIGGER trg_auditoria_inscripciones
  AFTER INSERT OR UPDATE OR DELETE ON public.inscripciones
  FOR EACH ROW EXECUTE FUNCTION public._auditar_cambio(
    'asistencia_confirmada', 'metodo_validacion', 'fecha_marcaje',
    'fecha_validacion', 'sesion_id');

-- 4. LISTA UNIFICADA PARA LA PANTALLA ------------------------------
-- p_origen: NULL | 'usuarios' | 'eventos' | 'asistencias' | 'validadores'
-- p_desde / p_hasta: fechas de Paraguay, ambas inclusive.
CREATE OR REPLACE FUNCTION public.listar_auditoria(
  p_origen  TEXT DEFAULT NULL,
  p_desde   DATE DEFAULT NULL,
  p_hasta   DATE DEFAULT NULL,
  p_limite  INT  DEFAULT 50,
  p_offset  INT  DEFAULT 0
)
RETURNS TABLE (
  origen        TEXT,
  accion        TEXT,
  entidad       TEXT,
  detalle       JSONB,
  motivo        TEXT,
  actor_nombre  TEXT,
  actor_rol     TEXT,
  realizado_en  TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_desde  TIMESTAMPTZ;
  v_hasta  TIMESTAMPTZ;
  v_limite INT := LEAST(GREATEST(COALESCE(p_limite, 50), 1), 200);
  v_offset INT := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede ver la auditoría';
  END IF;
  IF p_origen IS NOT NULL
     AND p_origen NOT IN ('usuarios', 'eventos', 'asistencias', 'validadores') THEN
    RAISE EXCEPTION 'Origen inválido';
  END IF;
  IF p_desde IS NOT NULL AND p_hasta IS NOT NULL AND p_hasta < p_desde THEN
    RAISE EXCEPTION 'La fecha final no puede ser anterior a la inicial';
  END IF;

  IF p_desde IS NOT NULL THEN
    v_desde := _hora_local(p_desde, TIME '00:00');
  END IF;
  IF p_hasta IS NOT NULL THEN
    v_hasta := _hora_local(p_hasta + 1, TIME '00:00');
  END IF;

  RETURN QUERY
  WITH fuentes AS (
    -- Cambios generales (trigger)
    SELECT CASE a.tabla WHEN 'inscripciones' THEN 'asistencias' ELSE a.tabla END AS f_origen,
           a.operacion        AS f_accion,
           CASE a.tabla WHEN 'usuarios' THEN 'usuario'
                        WHEN 'eventos'  THEN 'evento'
                        ELSE 'inscripcion' END AS f_ref_tipo,
           a.registro_id      AS f_ref_id,
           a.cambios          AS f_detalle,
           NULL::TEXT         AS f_motivo,
           a.realizado_por    AS f_actor,
           a.rol_actor        AS f_rol,
           a.realizado_en     AS f_fecha
    FROM auditoria_cambios a
    WHERE NOT (a.tabla = 'inscripciones'
               AND a.operacion = 'modificacion'
               AND COALESCE(a.rol_actor, '') IN ('admin', 'superadmin'))

    UNION ALL
    -- Correcciones de asistencia (script 10), con motivo
    SELECT 'asistencias', 'correccion', 'inscripcion', c.inscripcion_id::TEXT,
           jsonb_build_object('campo', c.campo,
                              'antes', c.valor_anterior,
                              'despues', c.valor_nuevo),
           c.motivo, c.corregido_por, NULL::TEXT, c.corregido_en
    FROM correcciones_asistencia c

    UNION ALL
    -- Cambios de horario (script 13)
    SELECT 'eventos', 'cambio_horario', 'evento', h.evento_id::TEXT,
           jsonb_build_object(
             'hora_inicio', jsonb_build_object('antes', h.inicio_anterior, 'despues', h.inicio_nuevo),
             'hora_fin',    jsonb_build_object('antes', h.fin_anterior,    'despues', h.fin_nuevo),
             'con_entradas', h.con_entradas),
           NULL::TEXT, h.cambiado_por, NULL::TEXT, h.cambiado_en
    FROM cambios_horario_evento h

    UNION ALL
    -- Restablecimiento de claves de validadores (script 12)
    SELECT 'validadores', v.accion, 'usuario', v.validador_id::TEXT,
           jsonb_build_object('evento', ev.nombre),
           NULL::TEXT, v.realizado_por, NULL::TEXT, v.realizado_en
    FROM auditoria_validadores v
    LEFT JOIN eventos ev ON ev.id = v.evento_id
  ),
  pagina AS (
    SELECT f.*
    FROM fuentes f
    WHERE (p_origen IS NULL OR f.f_origen = p_origen)
      AND (v_desde IS NULL OR f.f_fecha >= v_desde)
      AND (v_hasta IS NULL OR f.f_fecha <  v_hasta)
    ORDER BY f.f_fecha DESC
    LIMIT v_limite OFFSET v_offset
  )
  -- Los nombres se resuelven solo para la página pedida
  SELECT p.f_origen,
         p.f_accion,
         CASE p.f_ref_tipo
           WHEN 'usuario' THEN
             (SELECT u.nombre_completo::TEXT || ' · ' || u.ci::TEXT
              FROM usuarios u WHERE u.id = p.f_ref_id::UUID)
           WHEN 'evento' THEN
             (SELECT e.nombre::TEXT FROM eventos e WHERE e.id = p.f_ref_id::UUID)
           ELSE
             (SELECT u.nombre_completo::TEXT || ' · ' || e.nombre::TEXT
              FROM inscripciones i
              JOIN usuarios u ON u.id = i.usuario_id
              JOIN eventos  e ON e.id = i.evento_id
              WHERE i.id = p.f_ref_id::UUID)
         END,
         p.f_detalle,
         p.f_motivo,
         act.nombre_completo::TEXT,
         COALESCE(p.f_rol, act.rol)::TEXT,
         p.f_fecha
  FROM pagina p
  LEFT JOIN usuarios act ON act.id = p.f_actor
  ORDER BY p.f_fecha DESC;
END;
$$;

-- 5. PERMISOS ------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public._auditar_cambio()
  FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION
  public.listar_auditoria(TEXT, DATE, DATE, INT, INT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.listar_auditoria(TEXT, DATE, DATE, INT, INT)
TO authenticated;

-- 6. VERIFICACIÓN FINAL (si falla, se revierte todo) ----------------
DO $$
DECLARE
  v_triggers INT;
BEGIN
  SELECT COUNT(*) INTO v_triggers
  FROM pg_trigger
  WHERE NOT tgisinternal
    AND tgname IN ('trg_auditoria_usuarios',
                   'trg_auditoria_eventos',
                   'trg_auditoria_inscripciones');
  IF v_triggers <> 3 THEN
    RAISE EXCEPTION 'Faltan triggers de auditoría (encontrados: %)', v_triggers;
  END IF;

  IF to_regprocedure('public._es_superadmin()') IS NULL THEN
    RAISE EXCEPTION 'Falta _es_superadmin(): ejecutá antes el script 16';
  END IF;
END;
$$;

COMMIT;