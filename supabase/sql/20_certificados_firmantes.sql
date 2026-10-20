-- =========================================================
-- 20_certificados_firmantes.sql
-- Fase 7, paso 7.3a: firmantes por carrera (tabla editable del
-- superadmin) y certificados con datos congelados.
--
-- Decisiones (19-20/10, Kevin y Pedro; ESTADO_PROYECTO.md, sección 12):
-- - Cada carrera guarda SU facultad, SU decano/a y SU director/a
--   (aunque se repitan entre carreras de la misma facultad). Reemplaza
--   el modelo del script 19 (decano/a en la tabla facultades). Los datos
--   de facultades y carreras.facultad_id quedan sin uso (no se borran).
-- - El firmante de la carrera es el director/a; el cargo admite también
--   Coordinador/Coordinadora (carreras sin director).
-- - La carga se hace con guardar_firmantes(): recibe las filas de la
--   tabla (nuevas o modificadas) y las guarda todas o ninguna. Renombrar
--   una carrera actualiza usuarios.carrera (igual que en el 19).
-- - Certificados: uno por inscripción con entrada y salida en un evento
--   FINALIZADO. Se crean solos cuando el evento pasa a "finalizado"
--   (cierre automático) y guardan una COPIA FIJA de la carrera del
--   alumno y de los firmantes. Si la carrera todavía no tiene firmantes
--   completos, el certificado queda "pendiente" y se completa (y se
--   congela) cuando el superadmin los carga.
-- - Nombre del alumno y datos del evento NO se congelan: se leen al día.
-- - Si una corrección deja sin asistencia completa a un alumno de un
--   evento finalizado, su certificado se marca "anulado" (no se borra);
--   si vuelve a completarse, se reactiva con su copia original (la
--   carrera y los firmantes de entonces; si estaba pendiente, sigue
--   pendiente).
-- - No se guarda el PDF: el teléfono lo genera con mis_certificados().
--
-- Requiere: 11, 16 (_es_superadmin), 17 (_auditar_cambio) y 19.
-- Todo en una transacción. NO EJECUTAR sin autorización de Kevin.
-- =========================================================

BEGIN;

-- 1. CARRERAS: facultad y decano/a propios ------------------------
ALTER TABLE public.carreras
  ADD COLUMN IF NOT EXISTS facultad      TEXT,
  ADD COLUMN IF NOT EXISTS decano_nombre TEXT,
  ADD COLUMN IF NOT EXISTS decano_cargo  TEXT;

ALTER TABLE public.carreras
  DROP CONSTRAINT IF EXISTS carreras_decano_cargo_check;
ALTER TABLE public.carreras
  ADD CONSTRAINT carreras_decano_cargo_check
  CHECK (decano_cargo IN ('Decano', 'Decana'));

ALTER TABLE public.carreras
  DROP CONSTRAINT IF EXISTS carreras_decano_completo_check;
ALTER TABLE public.carreras
  ADD CONSTRAINT carreras_decano_completo_check
  CHECK ((decano_nombre IS NULL) = (decano_cargo IS NULL));

-- Cargo del responsable de la carrera: también coordinador/a.
ALTER TABLE public.carreras
  DROP CONSTRAINT IF EXISTS carreras_director_cargo_check;
ALTER TABLE public.carreras
  ADD CONSTRAINT carreras_director_cargo_check
  CHECK (director_cargo IN ('Director', 'Directora',
                            'Coordinador', 'Coordinadora'));

-- Datos cargados con el modelo del 19 (hoy solo la carrera de prueba):
-- se copian a las columnas nuevas.
UPDATE public.carreras c
SET facultad      = f.nombre,
    decano_nombre = f.decano_nombre,
    decano_cargo  = f.decano_cargo
FROM public.facultades f
WHERE f.id = c.facultad_id
  AND c.facultad IS NULL;

-- Firmantes completos = se puede emitir un certificado.
CREATE OR REPLACE FUNCTION public._firmantes_completos(c public.carreras)
RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
  SELECT c.facultad IS NOT NULL
     AND c.decano_nombre IS NOT NULL
     AND c.director_nombre IS NOT NULL;
$$;

-- 2. CERTIFICADOS ------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.certificados (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  inscripcion_id   UUID NOT NULL UNIQUE
                     REFERENCES public.inscripciones(id) ON DELETE RESTRICT,
  usuario_id       UUID NOT NULL REFERENCES public.usuarios(id),
  evento_id        UUID NOT NULL REFERENCES public.eventos(id),
  -- Copia fija (la carrera "de entonces" y sus firmantes)
  carrera_id       SMALLINT REFERENCES public.carreras(id),
  carrera          TEXT NOT NULL,
  facultad         TEXT,
  decano_nombre    TEXT,
  decano_cargo     TEXT,
  director_nombre  TEXT,
  director_cargo   TEXT,
  estado           TEXT NOT NULL
                     CHECK (estado IN ('pendiente', 'emitido', 'anulado')),
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  emitido_en       TIMESTAMPTZ,
  anulado_en       TIMESTAMPTZ,
  CHECK (estado <> 'emitido'
         OR (facultad IS NOT NULL AND decano_nombre IS NOT NULL
             AND director_nombre IS NOT NULL AND emitido_en IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_certificados_usuario
  ON public.certificados (usuario_id);
CREATE INDEX IF NOT EXISTS idx_certificados_pendientes
  ON public.certificados (carrera_id) WHERE estado = 'pendiente';

-- Solo lectura para el superadmin; el alumno lee los suyos con
-- mis_certificados(). Escriben únicamente los triggers y funciones.
ALTER TABLE public.certificados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "certificados_select_superadmin" ON public.certificados;
CREATE POLICY "certificados_select_superadmin" ON public.certificados
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') = 'superadmin');

REVOKE ALL ON public.certificados FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.certificados TO authenticated;

-- 3. EMITIR / ANULAR -------------------------------------------------
-- Crea el certificado de una inscripción con asistencia completa en un
-- evento finalizado, copiando la carrera actual del alumno y los
-- firmantes actuales de esa carrera. Si existía anulado, lo reactiva
-- con su copia original.
CREATE OR REPLACE FUNCTION public._emitir_certificado(p_inscripcion_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_i  RECORD;
  v_c  carreras%ROWTYPE;
  v_ok BOOLEAN;
BEGIN
  SELECT i.id, i.usuario_id, i.evento_id, u.carrera
  INTO v_i
  FROM inscripciones i
  JOIN usuarios u ON u.id = i.usuario_id
  JOIN eventos  e ON e.id = i.evento_id
  WHERE i.id = p_inscripcion_id
    AND e.estado = 'finalizado'
    AND i.entrada_en IS NOT NULL
    AND i.salida_en  IS NOT NULL;
  IF NOT FOUND THEN
    RETURN;   -- no corresponde certificado
  END IF;

  -- Ya emitido o pendiente: no se toca (los datos quedan congelados).
  -- Anulado: vuelve a su estado anterior, con la misma copia.
  IF EXISTS (SELECT 1 FROM certificados
             WHERE inscripcion_id = p_inscripcion_id) THEN
    UPDATE certificados
    SET estado     = CASE WHEN emitido_en IS NOT NULL
                          THEN 'emitido' ELSE 'pendiente' END,
        anulado_en = NULL
    WHERE inscripcion_id = p_inscripcion_id AND estado = 'anulado';
    RETURN;
  END IF;

  SELECT * INTO v_c FROM carreras WHERE nombre = v_i.carrera;
  v_ok := FOUND AND _firmantes_completos(v_c);

  INSERT INTO certificados (
    inscripcion_id, usuario_id, evento_id, carrera_id, carrera,
    facultad, decano_nombre, decano_cargo, director_nombre, director_cargo,
    estado, emitido_en, anulado_en
  ) VALUES (
    v_i.id, v_i.usuario_id, v_i.evento_id, v_c.id, v_i.carrera,
    CASE WHEN v_ok THEN v_c.facultad END,
    CASE WHEN v_ok THEN v_c.decano_nombre END,
    CASE WHEN v_ok THEN v_c.decano_cargo END,
    CASE WHEN v_ok THEN v_c.director_nombre END,
    CASE WHEN v_ok THEN v_c.director_cargo END,
    CASE WHEN v_ok THEN 'emitido' ELSE 'pendiente' END,
    CASE WHEN v_ok THEN NOW() END,
    NULL
  );
END;
$$;

-- Completa los pendientes de una carrera (o de todas, con NULL) cuando
-- ya tiene firmantes completos. Devuelve cuántos se emitieron.
CREATE OR REPLACE FUNCTION public._completar_certificados_pendientes(
  p_carrera_id INT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INT;
BEGIN
  UPDATE certificados ce SET
    facultad        = c.facultad,
    decano_nombre   = c.decano_nombre,
    decano_cargo    = c.decano_cargo,
    director_nombre = c.director_nombre,
    director_cargo  = c.director_cargo,
    estado          = 'emitido',
    emitido_en      = NOW()
  FROM carreras c
  WHERE ce.estado = 'pendiente'
    AND c.id = ce.carrera_id
    AND (p_carrera_id IS NULL OR c.id = p_carrera_id)
    AND _firmantes_completos(c);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- 4. TRIGGERS ---------------------------------------------------------
-- 4.1 Evento que pasa a "finalizado": certificados de sus asistentes.
CREATE OR REPLACE FUNCTION public._certificados_al_finalizar()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NEW.estado = 'finalizado'
     AND OLD.estado IS DISTINCT FROM 'finalizado' THEN
    FOR v_id IN
      SELECT id FROM inscripciones
      WHERE evento_id = NEW.id
        AND entrada_en IS NOT NULL
        AND salida_en  IS NOT NULL
    LOOP
      PERFORM _emitir_certificado(v_id);
    END LOOP;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_certificados ON public.eventos;
CREATE TRIGGER trg_eventos_certificados
  AFTER UPDATE OF estado ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public._certificados_al_finalizar();

-- 4.2 Corrección de asistencia en un evento ya finalizado.
CREATE OR REPLACE FUNCTION public._certificados_al_corregir()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_completa_antes BOOLEAN :=
    OLD.entrada_en IS NOT NULL AND OLD.salida_en IS NOT NULL;
  v_completa_ahora BOOLEAN :=
    NEW.entrada_en IS NOT NULL AND NEW.salida_en IS NOT NULL;
BEGIN
  IF v_completa_ahora = v_completa_antes THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM eventos
                 WHERE id = NEW.evento_id AND estado = 'finalizado') THEN
    RETURN NULL;   -- evento vigente: se resuelve al finalizar
  END IF;

  IF v_completa_ahora THEN
    PERFORM _emitir_certificado(NEW.id);
  ELSE
    UPDATE certificados
    SET estado = 'anulado', anulado_en = NOW()
    WHERE inscripcion_id = NEW.id AND estado <> 'anulado';
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_inscripciones_certificados ON public.inscripciones;
CREATE TRIGGER trg_inscripciones_certificados
  AFTER UPDATE OF entrada_en, salida_en ON public.inscripciones
  FOR EACH ROW EXECUTE FUNCTION public._certificados_al_corregir();

-- 5. TABLA DE FIRMANTES (superadmin) -------------------------------
-- p_filas: arreglo JSON de filas nuevas o modificadas:
--   { "id": 3 | null, "nombre": "...", "facultad": "...",
--     "decano_nombre": "...", "decano_cargo": "Decano|Decana",
--     "director_nombre": "...",
--     "director_cargo": "Director|Directora|Coordinador|Coordinadora" }
-- Sin id = carrera nueva (queda activa). Los datos de firmantes pueden
-- quedar vacíos (la carrera no emite certificados hasta completarlos),
-- pero nombre y cargo van juntos. Todo o nada.
-- Devuelve { creadas, actualizadas, usuarios_renombrados,
--            certificados_emitidos }.
CREATE OR REPLACE FUNCTION public.guardar_firmantes(p_filas JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_f          JSONB;
  v_n          INT := 0;
  v_id         INT;
  v_ant        carreras%ROWTYPE;
  v_nombre     TEXT;
  v_facultad   TEXT;
  v_dec_nom    TEXT;
  v_dec_cargo  TEXT;
  v_dir_nom    TEXT;
  v_dir_cargo  TEXT;
  v_creadas    INT := 0;
  v_actualiz   INT := 0;
  v_usuarios   INT := 0;
  v_cnt        INT;
  v_bloqueado  BOOLEAN := FALSE;
  v_ids        INT[] := '{}';
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede cargar firmantes';
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array'
     OR jsonb_array_length(p_filas) = 0 THEN
    RAISE EXCEPTION 'No hay filas para guardar';
  END IF;
  IF jsonb_array_length(p_filas) > 200 THEN
    RAISE EXCEPTION 'Se pueden guardar hasta 200 filas por vez';
  END IF;

  -- Nombres repetidos dentro de la misma carga
  SELECT string_agg(n, ', ') INTO v_nombre
  FROM (
    SELECT lower(_texto_limpio(x ->> 'nombre')) AS n
    FROM jsonb_array_elements(p_filas) x
    GROUP BY 1 HAVING COUNT(*) > 1
  ) d;
  IF v_nombre IS NOT NULL THEN
    RAISE EXCEPTION 'Hay carreras repetidas en la tabla: %', v_nombre;
  END IF;

  FOR v_f IN SELECT * FROM jsonb_array_elements(p_filas) LOOP
    v_n := v_n + 1;
    v_id        := NULLIF(v_f ->> 'id', '')::INT;
    v_nombre    := _texto_limpio(v_f ->> 'nombre');
    v_facultad  := NULLIF(_texto_limpio(v_f ->> 'facultad'), '');
    v_dec_nom   := NULLIF(_texto_limpio(v_f ->> 'decano_nombre'), '');
    v_dec_cargo := NULLIF(_texto_limpio(v_f ->> 'decano_cargo'), '');
    v_dir_nom   := NULLIF(_texto_limpio(v_f ->> 'director_nombre'), '');
    v_dir_cargo := NULLIF(_texto_limpio(v_f ->> 'director_cargo'), '');

    -- Validaciones de la fila (el mensaje indica la fila)
    IF length(v_nombre) NOT BETWEEN 3 AND 120 THEN
      RAISE EXCEPTION 'Fila %: el nombre de la carrera debe tener entre 3 y 120 caracteres', v_n;
    END IF;
    IF v_nombre ~* '^carrera(\s|$)' THEN
      RAISE EXCEPTION 'Fila %: escribí la carrera sin "Carrera de"', v_n;
    END IF;
    IF v_facultad IS NOT NULL THEN
      IF length(v_facultad) NOT BETWEEN 3 AND 120 THEN
        RAISE EXCEPTION 'Fila %: la facultad debe tener entre 3 y 120 caracteres', v_n;
      END IF;
      IF v_facultad ~* '^facultad(\s|$)' THEN
        RAISE EXCEPTION 'Fila %: escribí la facultad sin "Facultad de"', v_n;
      END IF;
    END IF;
    IF (v_dec_nom IS NULL) <> (v_dec_cargo IS NULL) THEN
      RAISE EXCEPTION 'Fila %: completá el nombre y el cargo del decano/a, o dejá ambos vacíos', v_n;
    END IF;
    IF v_dec_cargo IS NOT NULL AND v_dec_cargo NOT IN ('Decano', 'Decana') THEN
      RAISE EXCEPTION 'Fila %: el cargo del decano/a debe ser Decano o Decana', v_n;
    END IF;
    IF v_dec_nom IS NOT NULL AND length(v_dec_nom) NOT BETWEEN 5 AND 150 THEN
      RAISE EXCEPTION 'Fila %: el nombre del decano/a debe tener entre 5 y 150 caracteres', v_n;
    END IF;
    IF (v_dir_nom IS NULL) <> (v_dir_cargo IS NULL) THEN
      RAISE EXCEPTION 'Fila %: completá el nombre y el cargo del director/a, o dejá ambos vacíos', v_n;
    END IF;
    IF v_dir_cargo IS NOT NULL
       AND v_dir_cargo NOT IN ('Director', 'Directora', 'Coordinador', 'Coordinadora') THEN
      RAISE EXCEPTION 'Fila %: el cargo debe ser Director, Directora, Coordinador o Coordinadora', v_n;
    END IF;
    IF v_dir_nom IS NOT NULL AND length(v_dir_nom) NOT BETWEEN 5 AND 150 THEN
      RAISE EXCEPTION 'Fila %: el nombre del director/a debe tener entre 5 y 150 caracteres', v_n;
    END IF;
    IF v_dec_nom IS NOT NULL AND v_facultad IS NULL THEN
      RAISE EXCEPTION 'Fila %: indicá la facultad del decano/a', v_n;
    END IF;

    IF EXISTS (SELECT 1 FROM carreras
               WHERE lower(nombre) = lower(v_nombre)
                 AND id IS DISTINCT FROM v_id) THEN
      RAISE EXCEPTION 'Fila %: ya existe otra carrera llamada "%"', v_n, v_nombre;
    END IF;

    IF v_id IS NULL THEN
      -- Carrera nueva: no puede usar un valor de usuarios.carrera que no
      -- sea carrera ("Validador temporal", "Administración del sistema").
      IF EXISTS (SELECT 1 FROM usuarios WHERE lower(carrera) = lower(v_nombre)) THEN
        RAISE EXCEPTION 'Fila %: "%" ya lo usan otras cuentas del sistema; elegí otro nombre', v_n, v_nombre;
      END IF;

      INSERT INTO carreras (nombre, facultad, decano_nombre, decano_cargo,
                            director_nombre, director_cargo)
      VALUES (v_nombre, v_facultad, v_dec_nom, v_dec_cargo, v_dir_nom, v_dir_cargo)
      RETURNING id INTO v_id;
      v_creadas := v_creadas + 1;
    ELSE
      SELECT * INTO v_ant FROM carreras WHERE id = v_id FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Fila %: la carrera no existe (recargá la tabla)', v_n;
      END IF;

      IF v_nombre IS DISTINCT FROM v_ant.nombre THEN
        IF NOT v_ant.activa THEN
          RAISE EXCEPTION 'Fila %: reactivá "%" antes de cambiarle el nombre', v_n, v_ant.nombre;
        END IF;
        IF EXISTS (SELECT 1 FROM usuarios
                   WHERE lower(carrera) = lower(v_nombre)
                     AND carrera <> v_ant.nombre) THEN
          RAISE EXCEPTION 'Fila %: "%" ya lo usan otras cuentas del sistema; elegí otro nombre', v_n, v_nombre;
        END IF;
        IF NOT v_bloqueado THEN
          -- Igual que editar_carrera (19): ninguna alta o edición de
          -- usuarios queda guardada con el nombre viejo.
          LOCK TABLE usuarios IN SHARE ROW EXCLUSIVE MODE;
          v_bloqueado := TRUE;
        END IF;
      END IF;

      UPDATE carreras SET
        nombre          = v_nombre,
        facultad        = v_facultad,
        decano_nombre   = v_dec_nom,
        decano_cargo    = v_dec_cargo,
        director_nombre = v_dir_nom,
        director_cargo  = v_dir_cargo
      WHERE id = v_id;

      IF v_nombre IS DISTINCT FROM v_ant.nombre THEN
        UPDATE usuarios SET carrera = v_nombre WHERE carrera = v_ant.nombre;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        v_usuarios := v_usuarios + v_cnt;
      END IF;
      v_actualiz := v_actualiz + 1;
    END IF;

    v_ids := v_ids || v_id;
  END LOOP;

  -- Certificados pendientes de las carreras que quedaron completas
  v_cnt := 0;
  FOREACH v_id IN ARRAY v_ids LOOP
    v_cnt := v_cnt + _completar_certificados_pendientes(v_id);
  END LOOP;

  RETURN jsonb_build_object(
    'creadas', v_creadas,
    'actualizadas', v_actualiz,
    'usuarios_renombrados', v_usuarios,
    'certificados_emitidos', v_cnt
  );
END;
$$;

-- 6. LISTA PARA LA TABLA (reemplaza la del 19: cambian las columnas) ---
DROP FUNCTION IF EXISTS public.listar_carreras_admin();
CREATE FUNCTION public.listar_carreras_admin()
RETURNS TABLE (
  id                      INT,
  nombre                  TEXT,
  activa                  BOOLEAN,
  facultad                TEXT,
  decano_nombre           TEXT,
  decano_cargo            TEXT,
  director_nombre         TEXT,
  director_cargo          TEXT,
  alumnos_activos         INT,
  eventos_vigentes        INT,
  certificados_pendientes INT
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
         c.facultad::TEXT,
         c.decano_nombre::TEXT,
         c.decano_cargo::TEXT,
         c.director_nombre::TEXT,
         c.director_cargo::TEXT,
         (SELECT COUNT(*) FROM usuarios u
          WHERE u.carrera = c.nombre AND u.rol = 'alumno' AND u.activo)::INT,
         (SELECT COUNT(*) FROM evento_carreras ec
          JOIN eventos e ON e.id = ec.evento_id
          WHERE ec.carrera_id = c.id AND e.estado = 'vigente')::INT,
         (SELECT COUNT(*) FROM certificados ce
          WHERE ce.carrera_id = c.id AND ce.estado = 'pendiente')::INT
  FROM carreras c
  ORDER BY c.activa DESC, c.nombre;
END;
$$;

-- 7. CERTIFICADOS DEL ALUMNO ------------------------------------------
-- Nombre del alumno y datos del evento: al día. Carrera y firmantes:
-- la copia fija. Los pendientes se devuelven sin firmantes, para que la
-- app los muestre como "pendientes". No devuelve anulados.
CREATE OR REPLACE FUNCTION public.mis_certificados()
RETURNS TABLE (
  certificado_id   BIGINT,
  estado           TEXT,
  alumno           TEXT,
  evento_id        UUID,
  evento           TEXT,
  fecha            DATE,
  ubicacion        TEXT,
  horas            INT,
  carrera          TEXT,
  facultad         TEXT,
  decano_nombre    TEXT,
  decano_cargo     TEXT,
  director_nombre  TEXT,
  director_cargo   TEXT,
  emitido_en       TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
BEGIN
  IF COALESCE(rol_actual(), '') <> 'alumno' THEN
    RAISE EXCEPTION 'Solo los alumnos tienen certificados';
  END IF;

  RETURN QUERY
  SELECT ce.id,
         ce.estado,
         u.nombre_completo::TEXT,
         e.id,
         e.nombre::TEXT,
         e.fecha::DATE,
         e.ubicacion::TEXT,
         e.horas_otorgadas::INT,
         ce.carrera,
         ce.facultad,
         ce.decano_nombre,
         ce.decano_cargo,
         ce.director_nombre,
         ce.director_cargo,
         ce.emitido_en
  FROM certificados ce
  JOIN usuarios u ON u.id = ce.usuario_id
  JOIN eventos  e ON e.id = ce.evento_id
  WHERE ce.usuario_id = auth.uid()
    AND ce.estado IN ('pendiente', 'emitido')
    AND e.estado = 'finalizado'
  ORDER BY e.fecha DESC, e.hora_inicio DESC;
END;
$$;

-- 8. CERTIFICADOS DE EVENTOS YA FINALIZADOS ----------------------------
-- No hay historia anterior: se usa la carrera y los firmantes de hoy
-- (como hoy ninguna carrera oficial tiene firmantes, quedan pendientes
-- y se emiten cuando se carguen).
DO $$
DECLARE
  v_id UUID;
BEGIN
  FOR v_id IN
    SELECT i.id
    FROM inscripciones i
    JOIN eventos e ON e.id = i.evento_id
    WHERE e.estado = 'finalizado'
      AND i.entrada_en IS NOT NULL
      AND i.salida_en  IS NOT NULL
  LOOP
    PERFORM _emitir_certificado(v_id);
  END LOOP;
END;
$$;

-- 9. PERMISOS ----------------------------------------------------------
-- Funciones internas (triggers y ayudantes): sin EXECUTE para clientes.
REVOKE EXECUTE ON FUNCTION
  public._firmantes_completos(public.carreras),
  public._emitir_certificado(UUID),
  public._completar_certificados_pendientes(INT),
  public._certificados_al_finalizar(),
  public._certificados_al_corregir()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION
  public.guardar_firmantes(JSONB),
  public.listar_carreras_admin(),
  public.mis_certificados()
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.guardar_firmantes(JSONB),
  public.listar_carreras_admin(),
  public.mis_certificados()
TO authenticated;

-- Funciones del 19 reemplazadas por la tabla de firmantes (usan el
-- modelo de facultades). No se borran: se quitan del cliente.
REVOKE EXECUTE ON FUNCTION
  public.crear_facultad(TEXT, TEXT, TEXT),
  public.editar_facultad(INT, TEXT, TEXT, TEXT),
  public.crear_carrera(TEXT, INT, TEXT, TEXT),
  public.editar_carrera(INT, TEXT, INT, TEXT, TEXT)
FROM PUBLIC, anon, authenticated;

-- 10. VERIFICACIÓN FINAL (si falla, se revierte todo) -------------------
DO $$
DECLARE
  v_n INT;
BEGIN
  SELECT COUNT(*) INTO v_n
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'carreras'
    AND column_name IN ('facultad', 'decano_nombre', 'decano_cargo');
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'Faltan columnas nuevas en carreras (encontradas: %)', v_n;
  END IF;

  SELECT COUNT(*) INTO v_n
  FROM pg_trigger
  WHERE NOT tgisinternal
    AND tgname IN ('trg_eventos_certificados', 'trg_inscripciones_certificados');
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'Faltan triggers de certificados (encontrados: %)', v_n;
  END IF;

  -- Todo evento finalizado con asistencia completa tiene certificado
  SELECT COUNT(*) INTO v_n
  FROM inscripciones i
  JOIN eventos e ON e.id = i.evento_id
  WHERE e.estado = 'finalizado'
    AND i.entrada_en IS NOT NULL AND i.salida_en IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM certificados c WHERE c.inscripcion_id = i.id);
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Quedaron % asistencias completas sin certificado', v_n;
  END IF;
END;
$$;

COMMIT;