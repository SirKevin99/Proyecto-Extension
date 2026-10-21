-- =========================================================
-- 21_eventos_pasados.sql
-- Fase 8, paso 8.2: eventos pasados y reactivación de cancelados
-- (solo superadmin).
--
-- Decisiones (Kevin y Pedro, 20/10; ESTADO_PROYECTO.md, sección 13):
-- - El superadmin carga eventos que ya ocurrieron y no estaban en el
--   sistema, sin tope de antigüedad, con los mismos datos que "Nuevo
--   evento". Se crean directamente como "finalizado" y quedan marcados
--   con eventos.carga_historica = TRUE.
-- - Fecha: estrictamente ANTERIOR a hoy (hora de Paraguay). Un evento de
--   hoy sigue el flujo normal (se crea y se finaliza).
-- - Motivo obligatorio (mínimo 10 caracteres) al cargar, al editar y al
--   reactivar.
-- - Los eventos cargados como pasados SE PUEDEN CORREGIR después (Pedro,
--   20/10: los errores pueden pasar desapercibidos durante la carga),
--   con motivo y auditado. La fecha sigue siendo anterior a hoy. Si
--   cambian la fecha o el horario, la entrada y la salida de sus
--   asistentes se mueven al nuevo inicio y al nuevo fin (en los eventos
--   pasados la entrada es la hora de inicio y la salida la de fin).
--   Los demás eventos finalizados NO se editan.
-- - Eventos cancelados con fecha pasada: se pueden reactivar como
--   "finalizado", con motivo. El trigger del script 20 emite los
--   certificados de quienes tienen entrada y salida, y desde ese momento
--   suman horas. Un cancelado de hoy o futuro no se reactiva.
-- - Cupos: igual que "Nuevo evento" (NULL = sin límite). El paso 8.3
--   no dejará cargar más asistentes que el cupo.
-- - Todo se audita en auditoria_cambios (trigger del 17): se agregan las
--   columnas "contexto" (carga, edición o reactivación) y "motivo". Las
--   funciones de este script los indican con set_config local a la
--   transacción, y _auditar_cambio los guarda en cada fila. Las carreras
--   habilitadas también quedan en la auditoría del evento.
--
-- Los asistentes de los eventos pasados se cargan en el paso 8.3.
--
-- Requiere: 10 (_hora_local), 11, 13, 16 (_es_superadmin), 17, 19 y 20.
-- Todo en una transacción: si la verificación final falla, no queda
-- ningún cambio aplicado.
-- NO EJECUTAR sin autorización de Kevin.
-- =========================================================

BEGIN;

-- 1. EVENTOS: marca de carga histórica ------------------------------
ALTER TABLE public.eventos
  ADD COLUMN IF NOT EXISTS carga_historica BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. AUDITORÍA: contexto y motivo -----------------------------------
ALTER TABLE public.auditoria_cambios
  ADD COLUMN IF NOT EXISTS contexto TEXT,
  ADD COLUMN IF NOT EXISTS motivo   TEXT;

ALTER TABLE public.auditoria_cambios
  DROP CONSTRAINT IF EXISTS auditoria_cambios_contexto_check;
ALTER TABLE public.auditoria_cambios
  ADD CONSTRAINT auditoria_cambios_contexto_check
  CHECK (contexto IS NULL
         OR contexto IN ('carga_evento_pasado',
                         'edicion_evento_pasado',
                         'reactivacion_evento'));

-- Igual que en el 17, más contexto y motivo (variables de la
-- transacción que fijan las funciones de este script; vacías = NULL).
CREATE OR REPLACE FUNCTION public._auditar_cambio()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ant      JSONB := CASE WHEN TG_OP = 'INSERT' THEN '{}'::JSONB ELSE to_jsonb(OLD) END;
  v_nue      JSONB := CASE WHEN TG_OP = 'DELETE' THEN '{}'::JSONB ELSE to_jsonb(NEW) END;
  v_ignorar  TEXT[] := COALESCE(TG_ARGV, '{}'::TEXT[]);
  v_cambios  JSONB;
  v_actor    UUID := auth.uid();
  v_rol      TEXT;
  v_contexto TEXT := NULLIF(current_setting('uninorte.auditoria_contexto', true), '');
  v_motivo   TEXT := NULLIF(current_setting('uninorte.auditoria_motivo', true), '');
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
    (tabla, registro_id, operacion, cambios, realizado_por, rol_actor,
     contexto, motivo)
  VALUES (
    TG_TABLE_NAME,
    COALESCE(v_nue ->> 'id', v_ant ->> 'id'),
    CASE TG_OP WHEN 'INSERT' THEN 'alta'
               WHEN 'UPDATE' THEN 'modificacion'
               ELSE 'baja' END,
    v_cambios,
    v_actor,
    v_rol,
    v_contexto,
    v_motivo
  );

  RETURN NULL;   -- trigger AFTER: el valor de retorno se ignora
END;
$$;

-- 3. BLOQUEO DE HORARIO (13): la edición de un evento pasado puede
--    cambiar fecha y horario aunque tenga asistentes ----------------
CREATE OR REPLACE FUNCTION public._bloquear_cambio_horario()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cambia_fecha_tol BOOLEAN;
  v_cambia_horas     BOOLEAN;
BEGIN
  -- Nuevo (21): editar_evento_pasado marca la transacción.
  IF OLD.carga_historica
     AND COALESCE(current_setting('uninorte.edicion_evento_pasado', true), '') = 'on' THEN
    RETURN NEW;
  END IF;

  v_cambia_fecha_tol :=
    (NEW.fecha, NEW.tolerancia_entrada_min, NEW.tolerancia_salida_min)
    IS DISTINCT FROM
    (OLD.fecha, OLD.tolerancia_entrada_min, OLD.tolerancia_salida_min);

  v_cambia_horas :=
    (NEW.hora_inicio, NEW.hora_fin) IS DISTINCT FROM (OLD.hora_inicio, OLD.hora_fin);

  IF NOT (v_cambia_fecha_tol OR v_cambia_horas) THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM inscripciones
                 WHERE evento_id = NEW.id AND entrada_en IS NOT NULL) THEN
    RETURN NEW;
  END IF;

  IF v_cambia_fecha_tol THEN
    RAISE EXCEPTION 'Ya hay entradas registradas: no se pueden cambiar la fecha ni las tolerancias';
  END IF;

  IF COALESCE(current_setting('uninorte.cambio_horario_autorizado', true), '') <> 'on' THEN
    RAISE EXCEPTION 'Ya hay entradas registradas: el horario solo se puede cambiar desde la edición del evento';
  END IF;

  RETURN NEW;
END;
$$;

-- 4. AYUDANTES ------------------------------------------------------

-- 4.1 Contexto y motivo para la auditoría (locales a la transacción).
CREATE OR REPLACE FUNCTION public._fijar_contexto_auditoria(
  p_contexto TEXT,
  p_motivo   TEXT
)
RETURNS VOID
LANGUAGE sql
SET search_path = public
AS $$
  SELECT set_config('uninorte.auditoria_contexto', COALESCE(p_contexto, ''), true),
         set_config('uninorte.auditoria_motivo',   COALESCE(p_motivo, ''),   true);
$$;

-- 4.2 Motivo obligatorio (mínimo 10 caracteres, sin espacios de más).
CREATE OR REPLACE FUNCTION public._motivo_valido(p_motivo TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v TEXT := _texto_limpio(p_motivo);
BEGIN
  IF length(v) < 10 THEN
    RAISE EXCEPTION 'Indicá el motivo (mínimo 10 caracteres)';
  END IF;
  IF length(v) > 500 THEN
    RAISE EXCEPTION 'El motivo puede tener hasta 500 caracteres';
  END IF;
  RETURN v;
END;
$$;

-- 4.3 Datos del evento pasado: mismas reglas que crear_evento (11),
--     salvo la fecha, que debe ser anterior a hoy.
CREATE OR REPLACE FUNCTION public._validar_evento_pasado(
  p_nombre           TEXT,
  p_fecha            DATE,
  p_hora_inicio      TIME,
  p_hora_fin         TIME,
  p_ubicacion        TEXT,
  p_horas_otorgadas  INT,
  p_cupos_maximos    INT,
  p_tolerancia_min   INT
)
RETURNS VOID
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
BEGIN
  IF length(trim(COALESCE(p_nombre, ''))) < 3 THEN
    RAISE EXCEPTION 'El nombre del evento es obligatorio';
  END IF;
  IF length(trim(COALESCE(p_ubicacion, ''))) = 0 THEN
    RAISE EXCEPTION 'La ubicación es obligatoria';
  END IF;
  IF p_fecha IS NULL OR p_hora_inicio IS NULL OR p_hora_fin IS NULL THEN
    RAISE EXCEPTION 'La fecha y el horario son obligatorios';
  END IF;
  IF p_hora_fin <= p_hora_inicio THEN
    RAISE EXCEPTION 'La hora de fin debe ser posterior al inicio';
  END IF;
  IF p_fecha >= (NOW() AT TIME ZONE 'America/Asuncion')::date THEN
    RAISE EXCEPTION 'Un evento pasado debe tener una fecha anterior a hoy';
  END IF;
  IF p_horas_otorgadas IS NULL OR p_horas_otorgadas NOT BETWEEN 1 AND 120 THEN
    RAISE EXCEPTION 'Las horas otorgadas deben estar entre 1 y 120';
  END IF;
  IF p_cupos_maximos IS NOT NULL AND p_cupos_maximos NOT BETWEEN 1 AND 5000 THEN
    RAISE EXCEPTION 'Los cupos deben estar entre 1 y 5000';
  END IF;
  IF p_tolerancia_min IS NULL OR p_tolerancia_min NOT BETWEEN 0 AND 120 THEN
    RAISE EXCEPTION 'La tolerancia debe estar entre 0 y 120 minutos';
  END IF;
END;
$$;

-- 4.4 Nombres de las carreras habilitadas (ordenados), para la auditoría.
CREATE OR REPLACE FUNCTION public._nombres_carreras_evento(p_evento_id UUID)
RETURNS TEXT[]
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(c.nombre::TEXT ORDER BY c.nombre), '{}')
  FROM evento_carreras ec
  JOIN carreras c ON c.id = ec.carrera_id
  WHERE ec.evento_id = p_evento_id;
$$;

-- 4.5 Reemplaza las carreras de un evento pasado. Mínimo una; deben
--     estar activas, salvo las que el evento ya tenía (una carrera
--     desactivada después de la carga se puede conservar).
--     A diferencia de definir_carreras_evento (11), no exige evento vigente.
CREATE OR REPLACE FUNCTION public._definir_carreras_evento_pasado(
  p_evento_id   UUID,
  p_carrera_ids INT[]
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ids     INT[];
  v_validas INT;
BEGIN
  SELECT COALESCE(array_agg(DISTINCT x), '{}')
  INTO v_ids
  FROM unnest(COALESCE(p_carrera_ids, '{}')) AS x
  WHERE x IS NOT NULL;

  IF cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION 'Seleccioná al menos una carrera';
  END IF;

  SELECT COUNT(*) INTO v_validas
  FROM carreras c
  WHERE c.id = ANY(v_ids)
    AND (c.activa
         OR EXISTS (SELECT 1 FROM evento_carreras ec
                    WHERE ec.evento_id = p_evento_id AND ec.carrera_id = c.id));
  IF v_validas <> cardinality(v_ids) THEN
    RAISE EXCEPTION 'La selección incluye carreras inexistentes o inactivas';
  END IF;

  DELETE FROM evento_carreras
  WHERE evento_id = p_evento_id AND carrera_id <> ALL(v_ids);

  INSERT INTO evento_carreras (evento_id, carrera_id)
  SELECT p_evento_id, x FROM unnest(v_ids) AS x
  ON CONFLICT DO NOTHING;
END;
$$;

-- 4.6 Agrega el cambio de carreras a la auditoría del evento. Si en esta
--     misma transacción ya hay una fila del evento (alta o modificación
--     que registró el trigger), lo suma ahí; si no (solo cambiaron las
--     carreras), crea una fila de modificación.
CREATE OR REPLACE FUNCTION public._auditar_carreras_evento(
  p_evento_id UUID,
  p_antes     TEXT[],     -- NULL en la carga
  p_despues   TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_cambio JSONB;
  v_fila   BIGINT;
  v_rol    TEXT;
BEGIN
  IF p_antes IS NOT DISTINCT FROM p_despues THEN
    RETURN;
  END IF;

  v_cambio := jsonb_build_object('carreras', jsonb_build_object(
                'antes',   to_jsonb(p_antes),
                'despues', to_jsonb(p_despues)));

  -- NOW() es la hora de inicio de la transacción: identifica las filas
  -- que el trigger escribió en esta misma operación.
  SELECT id INTO v_fila
  FROM auditoria_cambios
  WHERE tabla = 'eventos'
    AND registro_id = p_evento_id::TEXT
    AND realizado_en = NOW()
    AND realizado_por IS NOT DISTINCT FROM auth.uid()
  ORDER BY id DESC
  LIMIT 1;

  IF FOUND THEN
    UPDATE auditoria_cambios SET cambios = cambios || v_cambio WHERE id = v_fila;
  ELSE
    SELECT rol INTO v_rol FROM usuarios WHERE id = auth.uid();
    INSERT INTO auditoria_cambios
      (tabla, registro_id, operacion, cambios, realizado_por, rol_actor,
       contexto, motivo)
    VALUES (
      'eventos', p_evento_id::TEXT, 'modificacion', v_cambio, auth.uid(), v_rol,
      NULLIF(current_setting('uninorte.auditoria_contexto', true), ''),
      NULLIF(current_setting('uninorte.auditoria_motivo', true), '')
    );
  END IF;
END;
$$;

-- 5. CARGAR UN EVENTO PASADO ----------------------------------------
-- Mismos parámetros que crear_evento (11) + motivo. Queda finalizado,
-- con carga_historica = TRUE y sin asistentes (se cargan en el 8.3).
CREATE OR REPLACE FUNCTION public.crear_evento_pasado(
  p_nombre           TEXT,
  p_descripcion      TEXT,
  p_categoria        TEXT,
  p_expositor        TEXT,
  p_fecha            DATE,
  p_hora_inicio      TIME,
  p_hora_fin         TIME,
  p_ubicacion        TEXT,
  p_modalidad        TEXT,
  p_horas_otorgadas  INT,
  p_cupos_maximos    INT,      -- NULL = sin límite
  p_tolerancia_min   INT,
  p_carrera_ids      INT[],    -- mínimo una
  p_motivo           TEXT
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id     UUID;
  v_motivo TEXT;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede cargar eventos pasados';
  END IF;

  v_motivo := _motivo_valido(p_motivo);
  PERFORM _validar_evento_pasado(p_nombre, p_fecha, p_hora_inicio, p_hora_fin,
                                 p_ubicacion, p_horas_otorgadas,
                                 p_cupos_maximos, p_tolerancia_min);

  PERFORM _fijar_contexto_auditoria('carga_evento_pasado', v_motivo);

  INSERT INTO eventos (
    nombre, descripcion, categoria, expositor, fecha, hora_inicio, hora_fin,
    ubicacion, modalidad, horas_otorgadas, cupos_maximos, cupos_disponibles,
    tolerancia_entrada_min, creado_por, estado, carga_historica
  ) VALUES (
    trim(p_nombre),
    NULLIF(trim(COALESCE(p_descripcion, '')), ''),
    p_categoria,
    NULLIF(trim(COALESCE(p_expositor, '')), ''),
    p_fecha, p_hora_inicio, p_hora_fin,
    trim(p_ubicacion),
    p_modalidad,
    p_horas_otorgadas,
    p_cupos_maximos,
    p_cupos_maximos,            -- sin asistentes todavía
    p_tolerancia_min,
    auth.uid(),
    'finalizado',
    TRUE
  )
  RETURNING id INTO v_id;

  -- Si falla (sin carreras o carreras inválidas), se revierte el evento.
  PERFORM _definir_carreras_evento_pasado(v_id, p_carrera_ids);
  PERFORM _auditar_carreras_evento(v_id, NULL, _nombres_carreras_evento(v_id));

  PERFORM _fijar_contexto_auditoria(NULL, NULL);
  RETURN v_id;
END;
$$;

-- 6. CORREGIR UN EVENTO CARGADO COMO PASADO -------------------------
-- Solo eventos con carga_historica = TRUE. Mismas validaciones que la
-- carga. Si cambian la fecha o el horario, la entrada y la salida de los
-- asistentes pasan al nuevo inicio y al nuevo fin. Devuelve cuántas
-- asistencias se ajustaron.
CREATE OR REPLACE FUNCTION public.editar_evento_pasado(
  p_evento_id        UUID,
  p_nombre           TEXT,
  p_descripcion      TEXT,
  p_categoria        TEXT,
  p_expositor        TEXT,
  p_fecha            DATE,
  p_hora_inicio      TIME,
  p_hora_fin         TIME,
  p_ubicacion        TEXT,
  p_modalidad        TEXT,
  p_horas_otorgadas  INT,
  p_cupos_maximos    INT,      -- NULL = sin límite
  p_tolerancia_min   INT,
  p_carrera_ids      INT[],
  p_motivo           TEXT
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev          eventos%ROWTYPE;
  v_motivo      TEXT;
  v_inscriptos  INT;
  v_antes       TEXT[];
  v_despues     TEXT[];
  v_cambia_hora BOOLEAN;
  v_cambia_dato BOOLEAN;
  v_ajustadas   INT := 0;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede corregir eventos pasados';
  END IF;

  SELECT * INTO v_ev FROM eventos WHERE id = p_evento_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El evento no existe';
  END IF;
  IF NOT v_ev.carga_historica THEN
    RAISE EXCEPTION 'Solo se pueden corregir los eventos cargados como pasados';
  END IF;
  IF v_ev.estado <> 'finalizado' THEN
    RAISE EXCEPTION 'El evento no está finalizado';
  END IF;

  v_motivo := _motivo_valido(p_motivo);
  PERFORM _validar_evento_pasado(p_nombre, p_fecha, p_hora_inicio, p_hora_fin,
                                 p_ubicacion, p_horas_otorgadas,
                                 p_cupos_maximos, p_tolerancia_min);

  SELECT COUNT(*) INTO v_inscriptos FROM inscripciones WHERE evento_id = p_evento_id;
  IF p_cupos_maximos IS NOT NULL AND p_cupos_maximos < v_inscriptos THEN
    RAISE EXCEPTION 'No se puede bajar el cupo por debajo de los % asistentes cargados', v_inscriptos;
  END IF;

  v_cambia_hora := (p_fecha, p_hora_inicio, p_hora_fin)
                   IS DISTINCT FROM (v_ev.fecha, v_ev.hora_inicio, v_ev.hora_fin);
  v_cambia_dato := v_cambia_hora
    OR (trim(p_nombre), NULLIF(trim(COALESCE(p_descripcion, '')), ''), p_categoria,
        NULLIF(trim(COALESCE(p_expositor, '')), ''), trim(p_ubicacion), p_modalidad,
        p_horas_otorgadas, p_cupos_maximos, p_tolerancia_min)
       IS DISTINCT FROM
       (v_ev.nombre, v_ev.descripcion, v_ev.categoria, v_ev.expositor,
        v_ev.ubicacion, v_ev.modalidad, v_ev.horas_otorgadas,
        v_ev.cupos_maximos, v_ev.tolerancia_entrada_min);

  v_antes := _nombres_carreras_evento(p_evento_id);

  PERFORM _fijar_contexto_auditoria('edicion_evento_pasado', v_motivo);
  -- Habilita el cambio de fecha y horario en el trigger del 13.
  PERFORM set_config('uninorte.edicion_evento_pasado', 'on', true);

  IF v_cambia_dato THEN
    UPDATE eventos SET
      nombre                 = trim(p_nombre),
      descripcion            = NULLIF(trim(COALESCE(p_descripcion, '')), ''),
      categoria              = p_categoria,
      expositor              = NULLIF(trim(COALESCE(p_expositor, '')), ''),
      fecha                  = p_fecha,
      hora_inicio            = p_hora_inicio,
      hora_fin               = p_hora_fin,
      ubicacion              = trim(p_ubicacion),
      modalidad              = p_modalidad,
      horas_otorgadas        = p_horas_otorgadas,
      cupos_maximos          = p_cupos_maximos,
      cupos_disponibles      = CASE WHEN p_cupos_maximos IS NULL
                                    THEN NULL
                                    ELSE p_cupos_maximos - v_inscriptos END,
      tolerancia_entrada_min = p_tolerancia_min
    WHERE id = p_evento_id;
  END IF;

  IF v_cambia_hora THEN
    -- Una sola sentencia: la salida nunca queda antes de la entrada.
    UPDATE inscripciones SET
      entrada_en = CASE WHEN entrada_en IS NULL THEN NULL
                        ELSE _hora_local(p_fecha, p_hora_inicio) END,
      salida_en  = CASE WHEN salida_en IS NULL THEN NULL
                        ELSE _hora_local(p_fecha, p_hora_fin) END
    WHERE evento_id = p_evento_id
      AND (entrada_en IS NOT NULL OR salida_en IS NOT NULL);
    GET DIAGNOSTICS v_ajustadas = ROW_COUNT;
  END IF;

  PERFORM _definir_carreras_evento_pasado(p_evento_id, p_carrera_ids);
  v_despues := _nombres_carreras_evento(p_evento_id);

  IF NOT v_cambia_dato AND v_antes IS NOT DISTINCT FROM v_despues THEN
    RAISE EXCEPTION 'No hay cambios para guardar';
  END IF;

  PERFORM _auditar_carreras_evento(p_evento_id, v_antes, v_despues);

  PERFORM set_config('uninorte.edicion_evento_pasado', 'off', true);
  PERFORM _fijar_contexto_auditoria(NULL, NULL);
  RETURN v_ajustadas;
END;
$$;

-- 7. REACTIVAR UN EVENTO CANCELADO ----------------------------------
-- Solo cancelados con fecha anterior a hoy; pasan a "finalizado". Los
-- certificados los emite el trigger del 20 (trg_eventos_certificados).
-- Devuelve cuántos asistentes tienen entrada y salida (reciben
-- certificado y suman horas).
CREATE OR REPLACE FUNCTION public.reactivar_evento_cancelado(
  p_evento_id UUID,
  p_motivo    TEXT
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev       eventos%ROWTYPE;
  v_motivo   TEXT;
  v_completos INT;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede reactivar eventos';
  END IF;

  SELECT * INTO v_ev FROM eventos WHERE id = p_evento_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El evento no existe';
  END IF;
  IF v_ev.estado <> 'cancelado' THEN
    RAISE EXCEPTION 'Solo se pueden reactivar eventos cancelados';
  END IF;
  IF v_ev.fecha >= (NOW() AT TIME ZONE 'America/Asuncion')::date THEN
    RAISE EXCEPTION 'Solo se pueden reactivar eventos cancelados con fecha anterior a hoy';
  END IF;

  v_motivo := _motivo_valido(p_motivo);

  PERFORM _fijar_contexto_auditoria('reactivacion_evento', v_motivo);

  UPDATE eventos SET estado = 'finalizado' WHERE id = p_evento_id;

  SELECT COUNT(*) INTO v_completos
  FROM inscripciones
  WHERE evento_id = p_evento_id
    AND entrada_en IS NOT NULL AND salida_en IS NOT NULL;

  PERFORM _fijar_contexto_auditoria(NULL, NULL);
  RETURN v_completos;
END;
$$;

-- 8. listar_auditoria (19): acción y motivo de la nueva auditoría ------
-- Misma firma y columnas que en el 19. Cambios: en las filas de
-- auditoria_cambios, la acción es el contexto cuando lo hay
-- (carga_evento_pasado, edicion_evento_pasado, reactivacion_evento) y el
-- motivo sale de la columna nueva.
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
     AND p_origen NOT IN ('usuarios', 'eventos', 'asistencias',
                          'validadores', 'carreras') THEN
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
    SELECT CASE a.tabla WHEN 'inscripciones' THEN 'asistencias'
                        WHEN 'facultades'    THEN 'carreras'
                        ELSE a.tabla END AS f_origen,
           COALESCE(a.contexto, a.operacion) AS f_accion,
           CASE a.tabla WHEN 'usuarios'   THEN 'usuario'
                        WHEN 'eventos'    THEN 'evento'
                        WHEN 'carreras'   THEN 'carrera'
                        WHEN 'facultades' THEN 'facultad'
                        ELSE 'inscripcion' END AS f_ref_tipo,
           a.registro_id      AS f_ref_id,
           a.cambios          AS f_detalle,
           a.motivo           AS f_motivo,
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
           WHEN 'carrera' THEN
             (SELECT c.nombre::TEXT FROM carreras c WHERE c.id = p.f_ref_id::INT)
           WHEN 'facultad' THEN
             (SELECT 'Facultad de ' || fa.nombre::TEXT
              FROM facultades fa WHERE fa.id = p.f_ref_id::INT)
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

-- 9. PERMISOS -------------------------------------------------------
-- Funciones internas: sin EXECUTE para clientes.
REVOKE EXECUTE ON FUNCTION
  public._auditar_cambio(),
  public._bloquear_cambio_horario(),
  public._fijar_contexto_auditoria(TEXT, TEXT),
  public._motivo_valido(TEXT),
  public._validar_evento_pasado(TEXT, DATE, TIME, TIME, TEXT, INT, INT, INT),
  public._nombres_carreras_evento(UUID),
  public._definir_carreras_evento_pasado(UUID, INT[]),
  public._auditar_carreras_evento(UUID, TEXT[], TEXT[])
FROM PUBLIC, anon, authenticated;

-- RPC del cliente (todas verifican superadmin adentro).
REVOKE EXECUTE ON FUNCTION
  public.crear_evento_pasado(TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME, TEXT,
                             TEXT, INT, INT, INT, INT[], TEXT),
  public.editar_evento_pasado(UUID, TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME,
                              TEXT, TEXT, INT, INT, INT, INT[], TEXT),
  public.reactivar_evento_cancelado(UUID, TEXT),
  public.listar_auditoria(TEXT, DATE, DATE, INT, INT)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.crear_evento_pasado(TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME, TEXT,
                             TEXT, INT, INT, INT, INT[], TEXT),
  public.editar_evento_pasado(UUID, TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME,
                              TEXT, TEXT, INT, INT, INT, INT[], TEXT),
  public.reactivar_evento_cancelado(UUID, TEXT),
  public.listar_auditoria(TEXT, DATE, DATE, INT, INT)
TO authenticated;

-- 10. VERIFICACIÓN FINAL (si falla, se revierte todo) -----------------
DO $$
DECLARE
  v_n INT;
BEGIN
  SELECT COUNT(*) INTO v_n
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND ((table_name = 'eventos' AND column_name = 'carga_historica')
      OR (table_name = 'auditoria_cambios' AND column_name IN ('contexto', 'motivo')));
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'Faltan columnas nuevas (encontradas: %)', v_n;
  END IF;

  SELECT COUNT(*) INTO v_n
  FROM pg_trigger
  WHERE NOT tgisinternal
    AND tgname IN ('trg_auditoria_eventos', 'trg_eventos_bloquear_horario',
                   'trg_eventos_certificados', 'trg_eventos_sync_activo');
  IF v_n <> 4 THEN
    RAISE EXCEPTION 'Faltan triggers de eventos (encontrados: %)', v_n;
  END IF;

  IF to_regprocedure('public._es_superadmin()') IS NULL
     OR to_regprocedure('public._texto_limpio(text)') IS NULL
     OR to_regprocedure('public._hora_local(date, time)') IS NULL
     OR to_regprocedure('public._emitir_certificado(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Faltan funciones de los scripts 10, 16, 19 o 20';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'auditoria_cambios_contexto_check'
      AND conrelid = 'public.auditoria_cambios'::regclass
  ) THEN
    RAISE EXCEPTION 'Falta el CHECK de auditoria_cambios.contexto';
  END IF;
END;
$$;

COMMIT;