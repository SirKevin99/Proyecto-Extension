-- =========================================================
-- 19_administrar_carreras.sql
-- Fase 7, paso 7.1: administración de carreras (solo superadmin).
--
-- Decisiones de Kevin (19/10, ESTADO_PROYECTO.md sección 12):
-- - Crear, editar, desactivar y reactivar carreras. No se borra nada.
-- - Renombrar una carrera actualiza usuarios.carrera (sigue siendo
--   TEXT) de todos los usuarios que la tienen.
-- - Antes de desactivar, la app muestra los alumnos activos y los
--   eventos vigentes de la carrera (resumen_carrera) y pide
--   confirmación.
-- - Desactivar no afecta a los alumnos que ya la tienen ni a los
--   eventos ya habilitados para ella: solo impide altas nuevas
--   (trigger del 11) y que se elija al crear o editar eventos
--   (definir_carreras_evento del 11 ya rechaza carreras inactivas).
-- - Firmantes del certificado: cada carrera guarda su facultad y su
--   director/a (nombre con título; cargo 'Director' o 'Directora');
--   cada facultad guarda su decano/a ('Decano' o 'Decana').
-- - Todo se audita (auditoria_cambios, script 17).
--
-- Propuestas de este script (A CONFIRMAR antes de ejecutar):
-- (a) Las facultades se crean y editan desde la misma pantalla de
--     carreras; no se desactivan (solo sirven para el certificado).
-- (b) Los nombres se guardan sin prefijo: la facultad "Ingeniería" se
--     imprime "Facultad de Ingeniería"; la carrera "Medicina",
--     "Carrera de Medicina". Se rechazan nombres que empiecen con
--     "Facultad" o "Carrera".
-- (c) Facultad y director/a son obligatorios al crear y al editar una
--     carrera. Las 15 actuales quedan sin esos datos (NULL) hasta que
--     se completen desde la pantalla.
-- (d) Una carrera desactivada no se puede renombrar (primero se
--     reactiva): el trigger del 11 exige carrera activa cuando cambia
--     usuarios.carrera de un alumno.
-- (e) Debe quedar al menos una carrera activa.
-- (f) editar_usuario (16) exige carrera activa solo si cambia la
--     carrera o el rol. Sin esto, el superadmin no podría editar (ni la
--     carga CSV actualizar) a un alumno de una carrera desactivada.
--
-- Requiere: 11, 16 y 17 (y 10 por _hora_local).
-- Todo en una transacción: si la verificación final falla, no queda
-- ningún cambio aplicado.
-- NO EJECUTAR sin autorización de Kevin.
-- =========================================================

BEGIN;

-- 1. HELPER: texto sin espacios de más ----------------------------
CREATE OR REPLACE FUNCTION public._texto_limpio(p_texto TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
  SELECT trim(regexp_replace(COALESCE(p_texto, ''), '\s+', ' ', 'g'));
$$;

-- 2. FACULTADES ---------------------------------------------------
CREATE TABLE IF NOT EXISTS public.facultades (
  id             SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre         TEXT NOT NULL CHECK (length(trim(nombre)) > 0),
  decano_nombre  TEXT NOT NULL CHECK (length(trim(decano_nombre)) > 0),
  decano_cargo   TEXT NOT NULL CHECK (decano_cargo IN ('Decano', 'Decana')),
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_facultades_nombre
  ON public.facultades (lower(nombre));

-- 3. CARRERAS: facultad y director/a -------------------------------
-- Columnas NULL para las 15 existentes; las funciones de este script
-- las exigen al crear o editar.
ALTER TABLE public.carreras
  ADD COLUMN IF NOT EXISTS facultad_id     SMALLINT
    REFERENCES public.facultades(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS director_nombre TEXT,
  ADD COLUMN IF NOT EXISTS director_cargo  TEXT;

ALTER TABLE public.carreras
  DROP CONSTRAINT IF EXISTS carreras_director_cargo_check;
ALTER TABLE public.carreras
  ADD CONSTRAINT carreras_director_cargo_check
  CHECK (director_cargo IN ('Director', 'Directora'));

ALTER TABLE public.carreras
  DROP CONSTRAINT IF EXISTS carreras_director_completo_check;
ALTER TABLE public.carreras
  ADD CONSTRAINT carreras_director_completo_check
  CHECK ((director_nombre IS NULL) = (director_cargo IS NULL));

CREATE INDEX IF NOT EXISTS idx_carreras_facultad
  ON public.carreras (facultad_id);

-- Nombre único sin distinguir mayúsculas (además del UNIQUE del 11).
CREATE UNIQUE INDEX IF NOT EXISTS ux_carreras_nombre_lower
  ON public.carreras (lower(nombre));

-- 4. RLS Y PERMISOS DE facultades -----------------------------------
-- Lectura para cualquier autenticado: el teléfono del alumno la
-- necesita para armar el certificado (igual que carreras en el 11).
-- Escritura solo por RPC.
ALTER TABLE public.facultades ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "facultades_select_autenticados" ON public.facultades;
CREATE POLICY "facultades_select_autenticados" ON public.facultades
  FOR SELECT TO authenticated USING (TRUE);

REVOKE ALL ON public.facultades FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.facultades TO authenticated, service_role;

-- 5. AUDITORÍA -----------------------------------------------------
-- 5.1 auditoria_cambios acepta también carreras y facultades.
--     Se borra el CHECK de la columna "tabla" del 17 (nombre generado
--     por Postgres) y se crea uno con nombre fijo.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_attribute a
      ON a.attrelid = c.conrelid AND a.attname = 'tabla'
    WHERE c.conrelid = 'public.auditoria_cambios'::regclass
      AND c.contype = 'c'
      AND c.conkey = ARRAY[a.attnum]
  LOOP
    EXECUTE format('ALTER TABLE public.auditoria_cambios DROP CONSTRAINT %I',
                   r.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.auditoria_cambios
  ADD CONSTRAINT auditoria_cambios_tabla_check
  CHECK (tabla IN ('usuarios', 'eventos', 'inscripciones',
                   'carreras', 'facultades'));

-- 5.2 Triggers (mismo _auditar_cambio del 17).
DROP TRIGGER IF EXISTS trg_auditoria_carreras ON public.carreras;
CREATE TRIGGER trg_auditoria_carreras
  AFTER INSERT OR UPDATE OR DELETE ON public.carreras
  FOR EACH ROW EXECUTE FUNCTION public._auditar_cambio();

DROP TRIGGER IF EXISTS trg_auditoria_facultades ON public.facultades;
CREATE TRIGGER trg_auditoria_facultades
  AFTER INSERT OR UPDATE OR DELETE ON public.facultades
  FOR EACH ROW EXECUTE FUNCTION public._auditar_cambio();

-- 6. VALIDACIONES COMPARTIDAS ---------------------------------------
-- p_id = NULL al crear; el id propio al editar (para no chocar consigo).
CREATE OR REPLACE FUNCTION public._validar_facultad(
  p_id      INT,
  p_nombre  TEXT,
  p_decano  TEXT,
  p_cargo   TEXT
)
RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF length(p_nombre) NOT BETWEEN 3 AND 120 THEN
    RAISE EXCEPTION 'El nombre de la facultad debe tener entre 3 y 120 caracteres';
  END IF;
  IF p_nombre ~* '^facultad(\s|$)' THEN
    RAISE EXCEPTION 'Escribí el nombre sin "Facultad de" (se agrega al imprimir)';
  END IF;
  IF EXISTS (
    SELECT 1 FROM facultades
    WHERE lower(nombre) = lower(p_nombre)
      AND id IS DISTINCT FROM p_id
  ) THEN
    RAISE EXCEPTION 'Ya existe una facultad con ese nombre';
  END IF;
  IF length(p_decano) NOT BETWEEN 5 AND 150 THEN
    RAISE EXCEPTION 'Ingresá el nombre del decano o decana con su título';
  END IF;
  IF COALESCE(p_cargo, '') NOT IN ('Decano', 'Decana') THEN
    RAISE EXCEPTION 'El cargo debe ser Decano o Decana';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._validar_carrera(
  p_id           INT,
  p_nombre       TEXT,
  p_facultad_id  INT,
  p_director     TEXT,
  p_cargo        TEXT
)
RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF length(p_nombre) NOT BETWEEN 3 AND 120 THEN
    RAISE EXCEPTION 'El nombre de la carrera debe tener entre 3 y 120 caracteres';
  END IF;
  IF p_nombre ~* '^carrera(\s|$)' THEN
    RAISE EXCEPTION 'Escribí el nombre sin "Carrera de" (se agrega al imprimir)';
  END IF;
  IF EXISTS (
    SELECT 1 FROM carreras
    WHERE lower(nombre) = lower(p_nombre)
      AND id IS DISTINCT FROM p_id
  ) THEN
    RAISE EXCEPTION 'Ya existe una carrera con ese nombre';
  END IF;
  -- Evita mezclar con valores de usuarios.carrera que no son carreras
  -- ('Validador temporal', 'Administración del sistema', etc.).
  -- Se excluyen los usuarios que ya tienen esta misma carrera.
  IF EXISTS (
    SELECT 1 FROM usuarios u
    WHERE lower(u.carrera) = lower(p_nombre)
      AND NOT EXISTS (
        SELECT 1 FROM carreras c
        WHERE c.id = p_id AND c.nombre = u.carrera
      )
  ) THEN
    RAISE EXCEPTION 'Ese nombre ya lo usan otras cuentas del sistema. Elegí otro';
  END IF;
  IF p_facultad_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM facultades WHERE id = p_facultad_id) THEN
    RAISE EXCEPTION 'Elegí una facultad';
  END IF;
  IF length(p_director) NOT BETWEEN 5 AND 150 THEN
    RAISE EXCEPTION 'Ingresá el nombre del director o directora con su título';
  END IF;
  IF COALESCE(p_cargo, '') NOT IN ('Director', 'Directora') THEN
    RAISE EXCEPTION 'El cargo debe ser Director o Directora';
  END IF;
END;
$$;

-- 7. FACULTADES: crear y editar -------------------------------------
CREATE OR REPLACE FUNCTION public.crear_facultad(
  p_nombre         TEXT,
  p_decano_nombre  TEXT,
  p_decano_cargo   TEXT
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nombre TEXT := _texto_limpio(p_nombre);
  v_decano TEXT := _texto_limpio(p_decano_nombre);
  v_id     INT;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede administrar facultades';
  END IF;

  PERFORM _validar_facultad(NULL, v_nombre, v_decano, p_decano_cargo);

  INSERT INTO facultades (nombre, decano_nombre, decano_cargo)
  VALUES (v_nombre, v_decano, p_decano_cargo)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.editar_facultad(
  p_facultad_id    INT,
  p_nombre         TEXT,
  p_decano_nombre  TEXT,
  p_decano_cargo   TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nombre TEXT := _texto_limpio(p_nombre);
  v_decano TEXT := _texto_limpio(p_decano_nombre);
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede administrar facultades';
  END IF;

  PERFORM 1 FROM facultades WHERE id = p_facultad_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La facultad no existe';
  END IF;

  PERFORM _validar_facultad(p_facultad_id, v_nombre, v_decano, p_decano_cargo);

  UPDATE facultades SET
    nombre        = v_nombre,
    decano_nombre = v_decano,
    decano_cargo  = p_decano_cargo
  WHERE id = p_facultad_id;
END;
$$;

-- 8. CARRERAS: crear, editar (renombrar), desactivar, reactivar -------

-- 8.1 Crear (queda activa).
CREATE OR REPLACE FUNCTION public.crear_carrera(
  p_nombre           TEXT,
  p_facultad_id      INT,
  p_director_nombre  TEXT,
  p_director_cargo   TEXT
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nombre   TEXT := _texto_limpio(p_nombre);
  v_director TEXT := _texto_limpio(p_director_nombre);
  v_id       INT;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede administrar carreras';
  END IF;

  PERFORM _validar_carrera(NULL, v_nombre, p_facultad_id, v_director, p_director_cargo);

  INSERT INTO carreras (nombre, facultad_id, director_nombre, director_cargo)
  VALUES (v_nombre, p_facultad_id, v_director, p_director_cargo)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- 8.2 Editar. Si cambia el nombre, actualiza usuarios.carrera de
--     todos los usuarios que la tienen (cada cambio queda en la
--     auditoría con el superadmin como autor).
--     Devuelve cuántos usuarios se actualizaron (0 si no se renombró).
CREATE OR REPLACE FUNCTION public.editar_carrera(
  p_carrera_id       INT,
  p_nombre           TEXT,
  p_facultad_id      INT,
  p_director_nombre  TEXT,
  p_director_cargo   TEXT
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_c          carreras%ROWTYPE;
  v_nombre     TEXT := _texto_limpio(p_nombre);
  v_director   TEXT := _texto_limpio(p_director_nombre);
  v_renombra   BOOLEAN;
  v_usuarios   INT := 0;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede administrar carreras';
  END IF;

  SELECT * INTO v_c FROM carreras WHERE id = p_carrera_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La carrera no existe';
  END IF;

  v_renombra := v_nombre IS DISTINCT FROM v_c.nombre;

  IF v_renombra AND NOT v_c.activa THEN
    RAISE EXCEPTION 'Reactivá la carrera antes de cambiarle el nombre';
  END IF;

  PERFORM _validar_carrera(p_carrera_id, v_nombre, p_facultad_id,
                           v_director, p_director_cargo);

  IF v_renombra THEN
    -- Serializa con altas y ediciones de usuarios en curso, para que
    -- ninguna quede guardada con el nombre viejo. Los renombres son
    -- poco frecuentes y la transacción es corta.
    LOCK TABLE usuarios IN SHARE ROW EXCLUSIVE MODE;
  END IF;

  UPDATE carreras SET
    nombre          = v_nombre,
    facultad_id     = p_facultad_id,
    director_nombre = v_director,
    director_cargo  = p_director_cargo
  WHERE id = p_carrera_id;

  IF v_renombra THEN
    -- El trigger trg_usuarios_validar_carrera (11) acepta el nombre
    -- nuevo porque la carrera ya está renombrada y activa.
    UPDATE usuarios SET carrera = v_nombre WHERE carrera = v_c.nombre;
    GET DIAGNOSTICS v_usuarios = ROW_COUNT;
  END IF;

  RETURN v_usuarios;
END;
$$;

-- 8.3 Resumen para la alerta previa a desactivar (y para consulta).
--     Muestras limitadas a 20; los totales son exactos.
CREATE OR REPLACE FUNCTION public.resumen_carrera(p_carrera_id INT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_c carreras%ROWTYPE;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede administrar carreras';
  END IF;

  SELECT * INTO v_c FROM carreras WHERE id = p_carrera_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La carrera no existe';
  END IF;

  RETURN jsonb_build_object(
    'carrera', v_c.nombre,
    'activa',  v_c.activa,
    'alumnos_activos', (
      SELECT COUNT(*) FROM usuarios
      WHERE carrera = v_c.nombre AND rol = 'alumno' AND activo),
    'admins_activos', (
      SELECT COUNT(*) FROM usuarios
      WHERE carrera = v_c.nombre AND rol = 'admin' AND activo),
    'eventos_vigentes', (
      SELECT COUNT(*) FROM evento_carreras ec
      JOIN eventos e ON e.id = ec.evento_id
      WHERE ec.carrera_id = v_c.id AND e.estado = 'vigente'),
    -- Eventos vigentes habilitados SOLO para esta carrera: si se
    -- desactiva, para editar sus carreras habrá que elegir otra.
    'eventos_solo_esta_carrera', (
      SELECT COUNT(*) FROM evento_carreras ec
      JOIN eventos e ON e.id = ec.evento_id
      WHERE ec.carrera_id = v_c.id AND e.estado = 'vigente'
        AND NOT EXISTS (
          SELECT 1 FROM evento_carreras ec2
          WHERE ec2.evento_id = ec.evento_id
            AND ec2.carrera_id <> v_c.id)),
    'muestra_alumnos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'nombre', x.nombre_completo, 'ci', x.ci))
      FROM (SELECT nombre_completo, ci FROM usuarios
            WHERE carrera = v_c.nombre AND rol = 'alumno' AND activo
            ORDER BY nombre_completo
            LIMIT 20) x), '[]'::JSONB),
    'muestra_eventos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'nombre', x.nombre, 'fecha', x.fecha))
      FROM (SELECT e.nombre, e.fecha
            FROM evento_carreras ec
            JOIN eventos e ON e.id = ec.evento_id
            WHERE ec.carrera_id = v_c.id AND e.estado = 'vigente'
            ORDER BY e.fecha, e.hora_inicio
            LIMIT 20) x), '[]'::JSONB)
  );
END;
$$;

-- 8.4 Desactivar.
CREATE OR REPLACE FUNCTION public.desactivar_carrera(p_carrera_id INT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activa BOOLEAN;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede administrar carreras';
  END IF;

  -- Bloquea todas las activas: dos desactivaciones simultáneas no
  -- pueden dejar el sistema sin carreras activas.
  PERFORM 1 FROM carreras WHERE activa OR id = p_carrera_id FOR UPDATE;

  SELECT activa INTO v_activa FROM carreras WHERE id = p_carrera_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La carrera no existe';
  END IF;
  IF NOT v_activa THEN
    RAISE EXCEPTION 'La carrera ya está desactivada';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM carreras WHERE activa AND id <> p_carrera_id) THEN
    RAISE EXCEPTION 'Debe quedar al menos una carrera activa';
  END IF;

  UPDATE carreras SET activa = FALSE WHERE id = p_carrera_id;
END;
$$;

-- 8.5 Reactivar.
CREATE OR REPLACE FUNCTION public.reactivar_carrera(p_carrera_id INT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede administrar carreras';
  END IF;

  UPDATE carreras SET activa = TRUE
  WHERE id = p_carrera_id AND NOT activa;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La carrera no existe o ya está activa';
  END IF;
END;
$$;

-- 8.6 Lista para la pantalla (activas e inactivas, con totales).
CREATE OR REPLACE FUNCTION public.listar_carreras_admin()
RETURNS TABLE (
  id                INT,
  nombre            TEXT,
  activa            BOOLEAN,
  facultad_id       INT,
  facultad          TEXT,
  director_nombre   TEXT,
  director_cargo    TEXT,
  alumnos_activos   INT,
  eventos_vigentes  INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede administrar carreras';
  END IF;

  RETURN QUERY
  SELECT c.id::INT,
         c.nombre::TEXT,
         c.activa,
         c.facultad_id::INT,
         f.nombre::TEXT,
         c.director_nombre::TEXT,
         c.director_cargo::TEXT,
         (SELECT COUNT(*) FROM usuarios u
          WHERE u.carrera = c.nombre AND u.rol = 'alumno' AND u.activo)::INT,
         (SELECT COUNT(*) FROM evento_carreras ec
          JOIN eventos e ON e.id = ec.evento_id
          WHERE ec.carrera_id = c.id AND e.estado = 'vigente')::INT
  FROM carreras c
  LEFT JOIN facultades f ON f.id = c.facultad_id
  ORDER BY c.activa DESC, c.nombre;
END;
$$;

-- 9. editar_usuario (16): carrera activa solo si cambia ---------------
-- Única diferencia con el 16: el bloque de la carrera.
CREATE OR REPLACE FUNCTION public.editar_usuario(
  p_usuario_id        UUID,
  p_nombre            TEXT,
  p_ci                TEXT,
  p_carrera           TEXT,
  p_horas_requeridas  INT,
  p_rol               TEXT      -- 'alumno' | 'admin'
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_u       usuarios%ROWTYPE;
  v_nombre  TEXT := trim(COALESCE(p_nombre, ''));
  v_ci      TEXT := trim(COALESCE(p_ci, ''));
  v_carrera TEXT := trim(COALESCE(p_carrera, ''));
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede editar usuarios';
  END IF;

  SELECT * INTO v_u FROM usuarios WHERE id = p_usuario_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario no existe';
  END IF;
  IF v_u.id = auth.uid() THEN
    RAISE EXCEPTION 'No podés editar tu propia cuenta desde aquí';
  END IF;
  IF v_u.rol NOT IN ('alumno', 'admin') THEN
    RAISE EXCEPTION 'Solo se pueden editar alumnos y administradores';
  END IF;

  IF COALESCE(p_rol, '') NOT IN ('alumno', 'admin') THEN
    RAISE EXCEPTION 'El rol debe ser alumno o administrador';
  END IF;
  IF length(v_nombre) < 3 THEN
    RAISE EXCEPTION 'Ingresá el nombre completo';
  END IF;
  IF v_ci !~ '^\d{4,10}$' THEN
    RAISE EXCEPTION 'La C.I. debe tener entre 4 y 10 dígitos';
  END IF;
  IF EXISTS (SELECT 1 FROM usuarios WHERE ci = v_ci AND id <> p_usuario_id) THEN
    RAISE EXCEPTION 'Ya existe otro usuario con esa C.I.';
  END IF;

  -- Carrera oficial siempre; además ACTIVA si cambia la carrera o el
  -- rol (mismo criterio que el trigger trg_usuarios_validar_carrera).
  IF v_carrera IS DISTINCT FROM v_u.carrera OR p_rol IS DISTINCT FROM v_u.rol THEN
    IF NOT EXISTS (SELECT 1 FROM carreras WHERE nombre = v_carrera AND activa) THEN
      RAISE EXCEPTION 'La carrera "%" no está en la lista oficial o está desactivada', v_carrera;
    END IF;
  ELSIF NOT EXISTS (SELECT 1 FROM carreras WHERE nombre = v_carrera) THEN
    RAISE EXCEPTION 'La carrera "%" no está en la lista oficial', v_carrera;
  END IF;

  IF p_horas_requeridas IS NULL OR p_horas_requeridas NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'Las horas requeridas deben estar entre 1 y 500';
  END IF;

  UPDATE usuarios SET
    nombre_completo  = v_nombre,
    ci               = v_ci,
    carrera          = v_carrera,
    horas_requeridas = p_horas_requeridas,
    rol              = p_rol
  WHERE id = p_usuario_id;
END;
$$;

-- 10. listar_auditoria (17): nuevo origen 'carreras' -----------------
-- Misma firma y mismas columnas que en el 17. Cambios: acepta el origen
-- 'carreras' (incluye facultades) y resuelve el nombre de la carrera o
-- de la facultad en "entidad".
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
           a.operacion        AS f_accion,
           CASE a.tabla WHEN 'usuarios'   THEN 'usuario'
                        WHEN 'eventos'    THEN 'evento'
                        WHEN 'carreras'   THEN 'carrera'
                        WHEN 'facultades' THEN 'facultad'
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

-- 11. PERMISOS -------------------------------------------------------
-- Helpers internos: sin EXECUTE para clientes.
REVOKE EXECUTE ON FUNCTION
  public._texto_limpio(TEXT),
  public._validar_facultad(INT, TEXT, TEXT, TEXT),
  public._validar_carrera(INT, TEXT, INT, TEXT, TEXT)
FROM PUBLIC, anon, authenticated;

-- RPC del cliente (todas verifican superadmin adentro).
REVOKE EXECUTE ON FUNCTION
  public.crear_facultad(TEXT, TEXT, TEXT),
  public.editar_facultad(INT, TEXT, TEXT, TEXT),
  public.crear_carrera(TEXT, INT, TEXT, TEXT),
  public.editar_carrera(INT, TEXT, INT, TEXT, TEXT),
  public.resumen_carrera(INT),
  public.desactivar_carrera(INT),
  public.reactivar_carrera(INT),
  public.listar_carreras_admin(),
  public.editar_usuario(UUID, TEXT, TEXT, TEXT, INT, TEXT),
  public.listar_auditoria(TEXT, DATE, DATE, INT, INT)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.crear_facultad(TEXT, TEXT, TEXT),
  public.editar_facultad(INT, TEXT, TEXT, TEXT),
  public.crear_carrera(TEXT, INT, TEXT, TEXT),
  public.editar_carrera(INT, TEXT, INT, TEXT, TEXT),
  public.resumen_carrera(INT),
  public.desactivar_carrera(INT),
  public.reactivar_carrera(INT),
  public.listar_carreras_admin(),
  public.editar_usuario(UUID, TEXT, TEXT, TEXT, INT, TEXT),
  public.listar_auditoria(TEXT, DATE, DATE, INT, INT)
TO authenticated;

-- 12. VERIFICACIÓN FINAL (si falla, se revierte todo) -----------------
DO $$
DECLARE
  v_cols     INT;
  v_triggers INT;
BEGIN
  SELECT COUNT(*) INTO v_cols
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'carreras'
    AND column_name IN ('facultad_id', 'director_nombre', 'director_cargo');
  IF v_cols <> 3 THEN
    RAISE EXCEPTION 'Faltan columnas nuevas en carreras (encontradas: %)', v_cols;
  END IF;

  SELECT COUNT(*) INTO v_triggers
  FROM pg_trigger
  WHERE NOT tgisinternal
    AND tgname IN ('trg_auditoria_carreras', 'trg_auditoria_facultades',
                   'trg_usuarios_validar_carrera');
  IF v_triggers <> 3 THEN
    RAISE EXCEPTION 'Faltan triggers (encontrados: %)', v_triggers;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'auditoria_cambios_tabla_check'
      AND pg_get_constraintdef(oid) LIKE '%facultades%'
  ) THEN
    RAISE EXCEPTION 'El CHECK de auditoria_cambios.tabla no se actualizó';
  END IF;

  -- Debe quedar un solo CHECK sobre la columna tabla.
  IF (SELECT COUNT(*) FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attname = 'tabla'
      WHERE c.conrelid = 'public.auditoria_cambios'::regclass
        AND c.contype = 'c' AND c.conkey = ARRAY[a.attnum]) <> 1 THEN
    RAISE EXCEPTION 'Hay más de un CHECK sobre auditoria_cambios.tabla';
  END IF;

  IF to_regprocedure('public._es_superadmin()') IS NULL
     OR to_regprocedure('public._auditar_cambio()') IS NULL THEN
    RAISE EXCEPTION 'Faltan funciones de los scripts 16 o 17';
  END IF;
END;
$$;

COMMIT;