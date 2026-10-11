-- =========================================================
-- 09_edicion_eventos.sql
-- hora_fin obligatoria, cupo ilimitado, tolerancia de entrada,
-- inscripción compatible con cupo ilimitado y edición por RPC
-- =========================================================

-- 1. hora_fin obligatoria (rellena los eventos viejos)
UPDATE eventos
SET hora_fin = CASE
      WHEN hora_inicio >= TIME '22:00' THEN TIME '23:59'
      ELSE hora_inicio + INTERVAL '2 hours'
    END
WHERE hora_fin IS NULL OR hora_fin <= hora_inicio;

ALTER TABLE eventos ALTER COLUMN hora_fin SET NOT NULL;
ALTER TABLE eventos
  ADD CONSTRAINT eventos_horario_check CHECK (hora_fin > hora_inicio);

-- 2. Cupo ilimitado: NULL = sin límite
ALTER TABLE eventos ALTER COLUMN cupos_maximos DROP NOT NULL;
ALTER TABLE eventos ALTER COLUMN cupos_disponibles DROP NOT NULL;

-- 3. Tolerancia de entrada (minutos). La usa la fase 4.
ALTER TABLE eventos
  ADD COLUMN IF NOT EXISTS tolerancia_entrada_min SMALLINT NOT NULL DEFAULT 15
  CHECK (tolerancia_entrada_min BETWEEN 0 AND 120);

-- 4. Inscripción compatible con cupo ilimitado
CREATE OR REPLACE FUNCTION public.inscribirse_a_evento(p_evento_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_cupos_disponibles INT;
BEGIN
  -- Bloquea la fila para evitar overbooking con inscripciones concurrentes.
  SELECT cupos_disponibles INTO v_cupos_disponibles
  FROM eventos
  WHERE id = p_evento_id AND activo = TRUE
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El evento no existe o no está activo';
  END IF;

  -- NULL = cupo ilimitado
  IF v_cupos_disponibles IS NOT NULL AND v_cupos_disponibles <= 0 THEN
    RAISE EXCEPTION 'No hay cupos disponibles para este evento';
  END IF;

  INSERT INTO inscripciones (usuario_id, evento_id)
  VALUES (auth.uid(), p_evento_id);

  -- Con cupo ilimitado (NULL) el resultado sigue siendo NULL
  UPDATE eventos
  SET cupos_disponibles = cupos_disponibles - 1
  WHERE id = p_evento_id;
END;
$$;

-- 5. Edición de un evento vigente
CREATE OR REPLACE FUNCTION public.editar_evento(
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
  p_cupos_maximos    INT,      -- NULL = ilimitado
  p_tolerancia_min   INT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev          eventos%ROWTYPE;
  v_inscriptos  INT;
  v_con_asist   BOOLEAN;
BEGIN
  IF COALESCE(rol_actual(), '') NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Solo un administrador puede editar eventos';
  END IF;

  SELECT * INTO v_ev FROM eventos WHERE id = p_evento_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El evento no existe';
  END IF;
  IF v_ev.estado <> 'vigente' THEN
    RAISE EXCEPTION 'Solo se pueden editar eventos vigentes';
  END IF;

  -- Validaciones de formato
  IF length(trim(COALESCE(p_nombre, ''))) < 3 THEN
    RAISE EXCEPTION 'El nombre del evento es obligatorio';
  END IF;
  IF length(trim(COALESCE(p_ubicacion, ''))) = 0 THEN
    RAISE EXCEPTION 'La ubicación es obligatoria';
  END IF;
  IF p_hora_fin <= p_hora_inicio THEN
    RAISE EXCEPTION 'La hora de fin debe ser posterior al inicio';
  END IF;
  IF p_horas_otorgadas NOT BETWEEN 1 AND 120 THEN
    RAISE EXCEPTION 'Las horas otorgadas deben estar entre 1 y 120';
  END IF;
  IF p_cupos_maximos IS NOT NULL AND p_cupos_maximos NOT BETWEEN 1 AND 5000 THEN
    RAISE EXCEPTION 'Los cupos deben estar entre 1 y 5000';
  END IF;
  IF p_tolerancia_min NOT BETWEEN 0 AND 120 THEN
    RAISE EXCEPTION 'La tolerancia debe estar entre 0 y 120 minutos';
  END IF;

  SELECT COUNT(*), COALESCE(BOOL_OR(asistencia_confirmada), FALSE)
  INTO v_inscriptos, v_con_asist
  FROM inscripciones WHERE evento_id = p_evento_id;

  -- Con asistencia registrada, fecha y horario quedan bloqueados
  -- (en la fase 4 el criterio pasa a ser la primera entrada)
  IF v_con_asist AND (
       p_fecha <> v_ev.fecha
    OR p_hora_inicio <> v_ev.hora_inicio
    OR p_hora_fin <> v_ev.hora_fin
    OR p_tolerancia_min <> v_ev.tolerancia_entrada_min
  ) THEN
    RAISE EXCEPTION 'Ya hay asistencia registrada: no se pueden cambiar fecha, horario ni tolerancia';
  END IF;

  IF p_fecha <> v_ev.fecha
     AND p_fecha < (NOW() AT TIME ZONE 'America/Asuncion')::date THEN
    RAISE EXCEPTION 'La nueva fecha no puede ser anterior a hoy';
  END IF;

  IF p_cupos_maximos IS NOT NULL AND p_cupos_maximos < v_inscriptos THEN
    RAISE EXCEPTION 'No se puede bajar el cupo por debajo de los % inscriptos', v_inscriptos;
  END IF;

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
END;
$$;

REVOKE EXECUTE ON FUNCTION public.editar_evento(
  UUID, TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME, TEXT, TEXT, INT, INT, INT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.editar_evento(
  UUID, TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME, TEXT, TEXT, INT, INT, INT
) TO authenticated;