-- =========================================================
-- 13_cambio_horario_evento.sql
-- Ajuste 2 (fase 4G): editar hora_inicio y hora_fin con el
-- evento vigente, aunque ya haya entradas registradas.
--
-- Decisiones (Kevin, 17/10):
-- - Solo admin (o superadmin). Sin motivo, pero auditado
--   (quién, horario anterior y nuevo, cuándo).
-- - Con entradas registradas, FECHA y TOLERANCIAS siguen
--   bloqueadas; solo se liberan las horas.
-- - No se tocan inscripciones ni sesiones: un modo abierto
--   conserva su plazo (modo_hasta) hasta cerrarse o reabrirse.
-- - Se rechaza hora_fin ya pasada (si el evento es hoy) y
--   hora_inicio igual o posterior a hora_fin.
--
-- Cómo se libera: editar_evento marca la transacción con
-- set_config('uninorte.cambio_horario_autorizado', 'on', true)
-- y el trigger solo deja pasar el cambio de horas con esa marca.
-- Un UPDATE directo sobre eventos sigue bloqueado.
--
-- Todo en una transacción. NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

-- 1. AUDITORÍA DE CAMBIOS DE HORARIO ------------------------
CREATE TABLE IF NOT EXISTS public.cambios_horario_evento (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  evento_id        UUID NOT NULL REFERENCES public.eventos(id) ON DELETE CASCADE,
  inicio_anterior  TIME NOT NULL,
  fin_anterior     TIME NOT NULL,
  inicio_nuevo     TIME NOT NULL,
  fin_nuevo        TIME NOT NULL,
  con_entradas     BOOLEAN NOT NULL,     -- había entradas al momento del cambio
  cambiado_por     UUID NOT NULL REFERENCES public.usuarios(id),
  cambiado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cambios_horario_evento
  ON public.cambios_horario_evento (evento_id, cambiado_en DESC);

ALTER TABLE public.cambios_horario_evento ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cambios_horario_select_admin"
  ON public.cambios_horario_evento;
CREATE POLICY "cambios_horario_select_admin"
  ON public.cambios_horario_evento
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') IN ('admin', 'superadmin'));

-- Solo lectura para el admin; la escritura la hace editar_evento
-- (SECURITY DEFINER).
REVOKE ALL ON public.cambios_horario_evento FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.cambios_horario_evento TO authenticated, service_role;

-- 2. TRIGGER: fecha y tolerancias bloqueadas; horas solo vía editar_evento
CREATE OR REPLACE FUNCTION public._bloquear_cambio_horario()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cambia_fecha_tol BOOLEAN;
  v_cambia_horas     BOOLEAN;
BEGIN
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
-- El trigger trg_eventos_bloquear_horario (script 10) ya apunta a esta
-- función; CREATE OR REPLACE lo actualiza sin recrearlo.

-- 3. EDITAR EVENTO (misma firma que en 09) -------------------
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
  v_ev            eventos%ROWTYPE;
  v_inscriptos    INT;
  v_con_entradas  BOOLEAN;
  v_cambia_horas  BOOLEAN;
  v_ahora         TIMESTAMP := NOW() AT TIME ZONE 'America/Asuncion';
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
  IF p_fecha IS NULL OR p_hora_inicio IS NULL OR p_hora_fin IS NULL THEN
    RAISE EXCEPTION 'La fecha y el horario son obligatorios';
  END IF;
  IF p_hora_fin <= p_hora_inicio THEN
    RAISE EXCEPTION 'La hora de fin debe ser posterior al inicio';
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

  SELECT COUNT(*), COALESCE(BOOL_OR(entrada_en IS NOT NULL), FALSE)
  INTO v_inscriptos, v_con_entradas
  FROM inscripciones WHERE evento_id = p_evento_id;

  -- Con entradas, fecha y tolerancia quedan bloqueadas (el trigger
  -- también lo impide; acá se da un mensaje claro antes).
  IF v_con_entradas AND (
       p_fecha <> v_ev.fecha
    OR p_tolerancia_min <> v_ev.tolerancia_entrada_min
  ) THEN
    RAISE EXCEPTION 'Ya hay entradas registradas: no se pueden cambiar la fecha ni la tolerancia';
  END IF;

  IF p_fecha <> v_ev.fecha AND p_fecha < v_ahora::date THEN
    RAISE EXCEPTION 'La nueva fecha no puede ser anterior a hoy';
  END IF;

  v_cambia_horas := (p_hora_inicio, p_hora_fin)
                    IS DISTINCT FROM (v_ev.hora_inicio, v_ev.hora_fin);

  -- Si cambia el horario (o la fecha) de un evento de hoy,
  -- la nueva hora de fin no puede haber pasado.
  IF (v_cambia_horas OR p_fecha <> v_ev.fecha)
     AND p_fecha = v_ahora::date
     AND p_hora_fin <= v_ahora::time THEN
    RAISE EXCEPTION 'La nueva hora de fin ya pasó';
  END IF;

  IF p_cupos_maximos IS NOT NULL AND p_cupos_maximos < v_inscriptos THEN
    RAISE EXCEPTION 'No se puede bajar el cupo por debajo de los % inscriptos', v_inscriptos;
  END IF;

  IF v_cambia_horas THEN
    INSERT INTO cambios_horario_evento (
      evento_id, inicio_anterior, fin_anterior,
      inicio_nuevo, fin_nuevo, con_entradas, cambiado_por
    ) VALUES (
      p_evento_id, v_ev.hora_inicio, v_ev.hora_fin,
      p_hora_inicio, p_hora_fin, v_con_entradas, auth.uid()
    );
    -- Marca local a esta transacción: habilita el cambio de horas en el trigger.
    PERFORM set_config('uninorte.cambio_horario_autorizado', 'on', true);
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

  -- Se quita la marca para el resto de la transacción.
  PERFORM set_config('uninorte.cambio_horario_autorizado', 'off', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public._bloquear_cambio_horario()
  FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.editar_evento(
  UUID, TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME, TEXT, TEXT, INT, INT, INT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.editar_evento(
  UUID, TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME, TEXT, TEXT, INT, INT, INT
) TO authenticated;

COMMIT;