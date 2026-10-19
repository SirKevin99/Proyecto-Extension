-- =========================================================
-- 18_carga_masiva_alumnos.sql
-- Fase 6, paso 6.1: alta masiva de alumnos por CSV (solo superadmin).
--
-- Decisiones (18/10, Kevin y Pedro):
-- - Solo alumnos y solo el superadmin. Máximo 300 filas por archivo;
--   la app envía tandas de 50 a la Edge Function alta-masiva-alumnos.
-- - La C.I. es el único identificador. Si ya existe: omitir o
--   actualizar (nombre, carrera, horas; nunca correo ni clave) y, si la
--   cuenta está desactivada, reactivar o no. Por defecto: omitir.
-- - Carga parcial: cada fila tiene su propio resultado.
-- - Nada se borra: estas tablas no tienen DELETE para nadie.
--
-- Objetos:
-- 1. cargas_masivas: un registro por lote (archivo).
-- 2. cargas_masivas_detalle: un registro por fila, con los valores
--    tal como vinieron en el CSV (TEXT), la acción pedida y el resultado.
-- 3. vista_cargas_masivas: totales por lote (security_invoker).
-- 4. verificar_carga_alumnos(): coincidencias por C.I. o correo para la
--    vista previa (por POST, sin límite de largo de URL).
--
-- Quién escribe:
-- - Las tablas las escribe solo la Edge Function (service_role).
-- - Las altas nuevas las audita el trigger del script 17 con
--   usuarios.creado_por. Las actualizaciones y reactivaciones las hace
--   la Edge Function llamando a editar_usuario y reactivar_usuario
--   (script 16) con el JWT del superadmin: mismas validaciones y la
--   auditoría general lo registra como autor.
--
-- Requiere: scripts 15 (superadmin), 16 (_es_superadmin) y 17.
-- Todo en una transacción. NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

-- 1. LOTES -------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cargas_masivas (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  realizado_por  UUID NOT NULL REFERENCES public.usuarios(id),
  nombre_archivo TEXT NOT NULL CHECK (length(trim(nombre_archivo)) > 0),
  total_filas    INT  NOT NULL CHECK (total_filas BETWEEN 1 AND 300),
  iniciada_en    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finalizada_en  TIMESTAMPTZ          -- NULL = alguna tanda no terminó
);

CREATE INDEX IF NOT EXISTS idx_cargas_masivas_fecha
  ON public.cargas_masivas (iniciada_en DESC);

-- 2. DETALLE POR FILA ---------------------------------------------
-- Los datos de la fila se guardan como TEXT, tal como vinieron, para
-- poder registrar también las filas rechazadas (p. ej. horas = "abc").
CREATE TABLE IF NOT EXISTS public.cargas_masivas_detalle (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carga_id         UUID NOT NULL REFERENCES public.cargas_masivas(id),
  fila             INT  NOT NULL CHECK (fila >= 1),   -- fila de datos del CSV
  ci               TEXT,
  nombre_completo  TEXT,
  correo           TEXT,
  carrera          TEXT,
  horas_requeridas TEXT,
  accion           TEXT NOT NULL
                     CHECK (accion IN ('crear', 'actualizar', 'omitir')),
  reactivar        BOOLEAN NOT NULL DEFAULT FALSE,    -- lo que se pidió
  resultado        TEXT NOT NULL
                     CHECK (resultado IN ('creado', 'actualizado', 'omitido', 'rechazado')),
  reactivado       BOOLEAN NOT NULL DEFAULT FALSE,    -- lo que pasó
  error            TEXT,
  usuario_id       UUID REFERENCES public.usuarios(id),
  registrado_en    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (carga_id, fila)
);

-- 3. RLS Y PERMISOS DE LAS TABLAS ----------------------------------
ALTER TABLE public.cargas_masivas         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cargas_masivas_detalle ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cargas_masivas_select_superadmin"
  ON public.cargas_masivas;
CREATE POLICY "cargas_masivas_select_superadmin"
  ON public.cargas_masivas
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') = 'superadmin');

DROP POLICY IF EXISTS "cargas_masivas_detalle_select_superadmin"
  ON public.cargas_masivas_detalle;
CREATE POLICY "cargas_masivas_detalle_select_superadmin"
  ON public.cargas_masivas_detalle
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') = 'superadmin');

REVOKE ALL ON public.cargas_masivas, public.cargas_masivas_detalle
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.cargas_masivas, public.cargas_masivas_detalle
  TO authenticated;
-- Solo la Edge Function escribe. Sin DELETE: no se borra nada.
GRANT SELECT, INSERT, UPDATE ON public.cargas_masivas, public.cargas_masivas_detalle
  TO service_role;

-- 4. VISTA CON TOTALES POR LOTE --------------------------------------
-- security_invoker: respeta la RLS de quien consulta (solo superadmin).
CREATE OR REPLACE VIEW public.vista_cargas_masivas
WITH (security_invoker = true) AS
SELECT c.id,
       c.realizado_por,
       u.nombre_completo                                       AS realizado_por_nombre,
       c.nombre_archivo,
       c.total_filas,
       c.iniciada_en,
       c.finalizada_en,
       COUNT(d.id)                                             AS filas_procesadas,
       COUNT(d.id) FILTER (WHERE d.resultado = 'creado')       AS creados,
       COUNT(d.id) FILTER (WHERE d.resultado = 'actualizado')  AS actualizados,
       COUNT(d.id) FILTER (WHERE d.reactivado)                 AS reactivados,
       COUNT(d.id) FILTER (WHERE d.resultado = 'omitido')      AS omitidos,
       COUNT(d.id) FILTER (WHERE d.resultado = 'rechazado')    AS rechazados
FROM public.cargas_masivas c
LEFT JOIN public.usuarios u ON u.id = c.realizado_por
LEFT JOIN public.cargas_masivas_detalle d ON d.carga_id = c.id
GROUP BY c.id, u.nombre_completo;

REVOKE ALL ON public.vista_cargas_masivas FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.vista_cargas_masivas TO authenticated, service_role;

-- 5. VERIFICACIÓN PREVIA (vista previa de la app) ---------------------
-- Devuelve los usuarios (de cualquier rol) cuya C.I. o correo coincide
-- con alguna fila del archivo. La app clasifica cada fila:
-- - C.I. de un alumno            → preguntar omitir / actualizar (y reactivar)
-- - C.I. de otro rol             → rechazada
-- - correo usado por otra C.I.   → rechazada
-- La Edge Function vuelve a verificar todo al procesar.
CREATE OR REPLACE FUNCTION public.verificar_carga_alumnos(
  p_cis     TEXT[],
  p_correos TEXT[]
)
RETURNS TABLE (
  usuario_id        UUID,
  ci                TEXT,
  nombre_completo   TEXT,
  correo            TEXT,
  carrera           TEXT,
  horas_requeridas  INT,
  rol               TEXT,
  activo            BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede usar la carga masiva';
  END IF;
  IF COALESCE(cardinality(p_cis), 0) > 300
     OR COALESCE(cardinality(p_correos), 0) > 300 THEN
    RAISE EXCEPTION 'Máximo 300 filas por archivo';
  END IF;

  RETURN QUERY
  SELECT u.id,
         u.ci::TEXT,
         u.nombre_completo::TEXT,
         u.correo_institucional::TEXT,
         u.carrera::TEXT,
         u.horas_requeridas::INT,
         u.rol::TEXT,
         u.activo
  FROM usuarios u
  WHERE u.ci = ANY (COALESCE(p_cis, '{}'::TEXT[]))
     OR lower(u.correo_institucional) = ANY (
          SELECT lower(trim(x)) FROM unnest(COALESCE(p_correos, '{}'::TEXT[])) AS x
        );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.verificar_carga_alumnos(TEXT[], TEXT[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verificar_carga_alumnos(TEXT[], TEXT[])
  TO authenticated;

-- 6. VERIFICACIÓN FINAL (si falla, se revierte todo) ------------------
DO $$
BEGIN
  IF to_regprocedure('public._es_superadmin()') IS NULL THEN
    RAISE EXCEPTION 'Falta _es_superadmin(): ejecutá antes el script 16';
  END IF;
  IF to_regprocedure('public.editar_usuario(uuid, text, text, text, integer, text)') IS NULL
     OR to_regprocedure('public.reactivar_usuario(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Faltan editar_usuario / reactivar_usuario (script 16)';
  END IF;
  IF to_regclass('public.auditoria_cambios') IS NULL THEN
    RAISE EXCEPTION 'Falta auditoria_cambios: ejecutá antes el script 17';
  END IF;

  -- Solo informativo: dos cargas simultáneas con la misma C.I. se
  -- frenarían en la base únicamente si usuarios.ci tiene índice único.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
    WHERE i.indrelid = 'public.usuarios'::regclass
      AND i.indisunique
      AND i.indnatts = 1
      AND a.attname = 'ci'
  ) THEN
    RAISE NOTICE 'Aviso: usuarios.ci no tiene índice único (informar al asistente)';
  END IF;
END;
$$;

COMMIT;