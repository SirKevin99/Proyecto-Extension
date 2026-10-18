-- =========================================================
-- 11_carreras_por_evento.sql
-- Ajuste 0 (fase 4G): carreras habilitadas por evento.
--
-- - Tabla carreras (lista oficial, 15) y evento_carreras.
-- - Eventos existentes: habilitados para todas las carreras.
-- - El admin crea el evento con crear_evento() (evento + carreras
--   en una transacción) y luego puede cambiarlas con
--   definir_carreras_evento() (mínimo una; solo con el evento
--   vigente; no toca inscripciones ya hechas).
-- - El alumno solo ve eventos de su carrera o en los que ya
--   está inscripto (policy RESTRICTIVE sobre eventos).
-- - inscribirse_a_evento valida la carrera del alumno.
-- - usuarios.carrera sigue siendo TEXT; para rol 'alumno'
--   debe coincidir con un nombre de la lista oficial (trigger).
--
-- Todo corre en una transacción: si la verificación final
-- falla (sección 9), no queda ningún cambio aplicado.
-- NO EJECUTAR sin completar y confirmar la sección 6.
-- =========================================================

BEGIN;

-- 1. CARRERAS (lista oficial) ------------------------------
CREATE TABLE IF NOT EXISTS public.carreras (
  id      SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre  TEXT NOT NULL UNIQUE CHECK (length(trim(nombre)) > 0),
  activa  BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO public.carreras (nombre) VALUES
  ('Administración de Empresas'),
  ('Bioquímica'),
  ('Ciencias Contables'),
  ('Comercio Exterior y Relaciones Internacionales'),
  ('Derecho'),
  ('Enfermería'),
  ('Fisioterapia y Kinesiología'),
  ('Ingeniería Comercial'),
  ('Ingeniería Electromecánica'),
  ('Ingeniería Informática'),
  ('Medicina'),
  ('Nutrición'),
  ('Odontología'),
  ('Periodismo'),
  ('Psicología')
ON CONFLICT (nombre) DO NOTHING;

-- 2. EVENTO_CARRERAS ---------------------------------------
CREATE TABLE IF NOT EXISTS public.evento_carreras (
  evento_id   UUID     NOT NULL REFERENCES public.eventos(id)  ON DELETE CASCADE,
  carrera_id  SMALLINT NOT NULL REFERENCES public.carreras(id) ON DELETE RESTRICT,
  creado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (evento_id, carrera_id)
);

CREATE INDEX IF NOT EXISTS idx_evento_carreras_carrera
  ON public.evento_carreras (carrera_id);

-- 3. EVENTOS EXISTENTES: habilitados para todas las carreras
INSERT INTO public.evento_carreras (evento_id, carrera_id)
SELECT e.id, c.id
FROM public.eventos e CROSS JOIN public.carreras c
ON CONFLICT DO NOTHING;

-- 4. RLS Y PERMISOS DE LAS TABLAS NUEVAS -------------------
ALTER TABLE public.carreras        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evento_carreras ENABLE ROW LEVEL SECURITY;

-- carreras: lectura para cualquier usuario autenticado (listas y formularios)
DROP POLICY IF EXISTS "carreras_select_autenticados" ON public.carreras;
CREATE POLICY "carreras_select_autenticados" ON public.carreras
  FOR SELECT TO authenticated USING (TRUE);

-- evento_carreras: solo lectura para admin; la escritura va por RPC
DROP POLICY IF EXISTS "evento_carreras_select_admin" ON public.evento_carreras;
CREATE POLICY "evento_carreras_select_admin" ON public.evento_carreras
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') IN ('admin', 'superadmin'));

REVOKE ALL ON public.carreras        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.evento_carreras FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.carreras        TO authenticated, service_role;
GRANT SELECT ON public.evento_carreras TO authenticated, service_role;

-- 5. VISIBILIDAD DEL ALUMNO --------------------------------
-- Visible si el evento está habilitado para su carrera
-- o si ya está inscripto (cambiar carreras no lo afecta).
CREATE OR REPLACE FUNCTION public.evento_visible_para_alumno(p_evento_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
           SELECT 1 FROM inscripciones i
           WHERE i.evento_id = p_evento_id
             AND i.usuario_id = auth.uid()
         )
      OR EXISTS (
           SELECT 1
           FROM evento_carreras ec
           JOIN carreras c ON c.id = ec.carrera_id
           JOIN usuarios u ON u.carrera = c.nombre
           WHERE ec.evento_id = p_evento_id
             AND u.id = auth.uid()
         );
$$;

-- RESTRICTIVE: se combina (AND) con las policies de lectura
-- existentes, sin necesidad de modificarlas. Solo afecta a alumnos.
DROP POLICY IF EXISTS "eventos_alumno_por_carrera" ON public.eventos;
CREATE POLICY "eventos_alumno_por_carrera" ON public.eventos
  AS RESTRICTIVE
  FOR SELECT TO authenticated
  USING (
    COALESCE(rol_actual(), '') <> 'alumno'
    OR evento_visible_para_alumno(id)
  );

-- 6. NORMALIZACIÓN DE usuarios.carrera ---------------------
-- Valores actuales (consulta del 17/10), todos de prueba:
--   admin  'Administración' (1) · alumno 'Derecho' (1)
--   alumno 'Ingeniería' (1)     · validador 'Validador temporal' (8)
-- 'Validador temporal' no se toca (lo escribe crear-usuario).
-- 'Derecho' ya coincide con la lista oficial.
-- Los nombres se guardan siempre completos.

-- Admin de prueba: nombre completo
UPDATE public.usuarios
SET carrera = 'Administración de Empresas'
WHERE rol = 'admin' AND carrera = 'Administración';

-- Alumno de prueba: valor de prueba elegido (cambiar si se prefiere otra)
UPDATE public.usuarios
SET carrera = 'Ingeniería Informática'
WHERE rol = 'alumno' AND carrera = 'Ingeniería';

-- 7. TRIGGER: la carrera de un alumno debe ser oficial y activa
CREATE OR REPLACE FUNCTION public._validar_carrera_alumno()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.rol = 'alumno'
     AND (TG_OP = 'INSERT'
          OR NEW.carrera IS DISTINCT FROM OLD.carrera
          OR NEW.rol     IS DISTINCT FROM OLD.rol)
     AND NOT EXISTS (
       SELECT 1 FROM carreras
       WHERE nombre = NEW.carrera AND activa
     )
  THEN
    RAISE EXCEPTION 'La carrera "%" no está en la lista oficial', NEW.carrera;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_usuarios_validar_carrera ON public.usuarios;
CREATE TRIGGER trg_usuarios_validar_carrera
  BEFORE INSERT OR UPDATE OF carrera, rol ON public.usuarios
  FOR EACH ROW EXECUTE FUNCTION public._validar_carrera_alumno();

-- 8. FUNCIONES DEL CLIENTE ---------------------------------

-- 8.1 Definir (o reemplazar) las carreras de un evento vigente.
--     Mínimo una. No modifica inscripciones existentes.
--     El botón "todas" del cliente envía todos los id activos.
CREATE OR REPLACE FUNCTION public.definir_carreras_evento(
  p_evento_id   UUID,
  p_carrera_ids INT[]
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado  TEXT;
  v_ids     INT[];
  v_validas INT;
BEGIN
  IF COALESCE(rol_actual(), '') NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Solo un administrador puede definir las carreras de un evento';
  END IF;

  -- Bloquea el evento: serializa con inscribirse_a_evento
  SELECT estado INTO v_estado
  FROM eventos WHERE id = p_evento_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El evento no existe';
  END IF;
  IF v_estado <> 'vigente' THEN
    RAISE EXCEPTION 'Solo se pueden cambiar las carreras de eventos vigentes';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT x), '{}')
  INTO v_ids
  FROM unnest(COALESCE(p_carrera_ids, '{}')) AS x
  WHERE x IS NOT NULL;

  IF cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION 'Seleccioná al menos una carrera';
  END IF;

  SELECT COUNT(*) INTO v_validas
  FROM carreras WHERE id = ANY(v_ids) AND activa;
  IF v_validas <> cardinality(v_ids) THEN
    RAISE EXCEPTION 'La selección incluye carreras inexistentes o inactivas';
  END IF;

  DELETE FROM evento_carreras
  WHERE evento_id = p_evento_id AND carrera_id <> ALL(v_ids);

  INSERT INTO evento_carreras (evento_id, carrera_id)
  SELECT p_evento_id, x FROM unnest(v_ids) AS x
  ON CONFLICT DO NOTHING;

  RETURN cardinality(v_ids);
END;
$$;

-- 8.2 Inscripción: igual a la versión de 09 + validación de carrera
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

  -- Nuevo: el evento debe estar habilitado para la carrera del usuario
  IF NOT EXISTS (
    SELECT 1
    FROM evento_carreras ec
    JOIN carreras c ON c.id = ec.carrera_id
    JOIN usuarios u ON u.carrera = c.nombre
    WHERE ec.evento_id = p_evento_id
      AND u.id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Este evento no está habilitado para tu carrera';
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

-- 8.3 Crear evento + carreras en una sola transacción (opción B).
--     Reemplaza el INSERT directo de CrearEventoNotifier.
--     Validaciones iguales a editar_evento (09) + fecha/hora futura.
--     NOTA: la policy eventos_insert_admin se mantiene por ahora para
--     no romper la app de develop; se elimina en un script posterior,
--     cuando el cliente nuevo esté mergeado.
CREATE OR REPLACE FUNCTION public.crear_evento(
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
  p_tolerancia_min   INT,
  p_carrera_ids      INT[]     -- mínimo una
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id    UUID;
  v_ahora TIMESTAMP := NOW() AT TIME ZONE 'America/Asuncion';
BEGIN
  IF COALESCE(rol_actual(), '') NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Solo un administrador puede crear eventos';
  END IF;

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
  IF p_fecha < v_ahora::date THEN
    RAISE EXCEPTION 'La fecha no puede ser anterior a hoy';
  END IF;
  IF p_fecha = v_ahora::date AND p_hora_fin <= v_ahora::time THEN
    RAISE EXCEPTION 'La hora de fin ya pasó';
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

  INSERT INTO eventos (
    nombre, descripcion, categoria, expositor, fecha, hora_inicio, hora_fin,
    ubicacion, modalidad, horas_otorgadas, cupos_maximos, cupos_disponibles,
    tolerancia_entrada_min, creado_por, estado
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
    p_cupos_maximos,            -- NULL = ilimitado
    p_tolerancia_min,
    auth.uid(),
    'vigente'
  )
  RETURNING id INTO v_id;

  -- Valida "mínimo una carrera" y que existan; si falla, se revierte el evento.
  PERFORM definir_carreras_evento(v_id, p_carrera_ids);

  RETURN v_id;
END;
$$;

-- 8.4 Permisos de ejecución
REVOKE EXECUTE ON FUNCTION public._validar_carrera_alumno()
  FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION
  public.evento_visible_para_alumno(UUID),
  public.definir_carreras_evento(UUID, INT[]),
  public.crear_evento(TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME, TEXT, TEXT,
                      INT, INT, INT, INT[]),
  public.inscribirse_a_evento(UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.evento_visible_para_alumno(UUID),   -- la usa la policy de eventos
  public.definir_carreras_evento(UUID, INT[]),
  public.crear_evento(TEXT, TEXT, TEXT, TEXT, DATE, TIME, TIME, TEXT, TEXT,
                      INT, INT, INT, INT[]),
  public.inscribirse_a_evento(UUID)
TO authenticated;

-- 9. VERIFICACIÓN FINAL (si falla, se revierte todo) --------
DO $$
DECLARE
  v_fuera TEXT;
  v_sin   INT;
BEGIN
  SELECT string_agg(DISTINCT COALESCE(u.carrera, '(vacía)'), ', ')
  INTO v_fuera
  FROM usuarios u
  WHERE u.rol = 'alumno'
    AND NOT EXISTS (SELECT 1 FROM carreras c WHERE c.nombre = u.carrera);
  IF v_fuera IS NOT NULL THEN
    RAISE EXCEPTION 'Alumnos con carrera fuera de la lista oficial: %. Completá la sección 6.', v_fuera;
  END IF;

  SELECT COUNT(*) INTO v_sin
  FROM eventos e
  WHERE NOT EXISTS (SELECT 1 FROM evento_carreras ec WHERE ec.evento_id = e.id);
  IF v_sin > 0 THEN
    RAISE EXCEPTION 'Hay % eventos sin carreras habilitadas', v_sin;
  END IF;
END;
$$;

COMMIT;