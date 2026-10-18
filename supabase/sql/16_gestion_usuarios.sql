-- =========================================================
-- 16_gestion_usuarios.sql
-- Fase 5, paso 5.3: gestión de usuarios (solo superadmin).
--
-- Decisiones (18/10):
-- - Solo el superadmin edita, desactiva y reactiva usuarios.
-- - Editables: nombre, C.I., carrera, horas requeridas y rol
--   (solo entre 'alumno' y 'admin'). El correo NO se edita.
-- - Nada se borra: "eliminar" = desactivar (bloqueo en Auth).
-- - Solo se gestionan alumnos y admins: los validadores tienen su
--   propia pantalla y nadie puede recibir el rol superadmin.
-- - El superadmin no puede editarse, desactivarse ni cambiarse
--   el rol a sí mismo (es el único y no es alumno ni admin).
--
-- La lista de usuarios la lee la app directamente (policy
-- usuarios_select_admin del script 15); acá solo van las escrituras.
-- La auditoría de estos cambios la agrega el script del paso 5.4:
-- ejecutar ambos juntos.
--
-- Limitación aceptada: desactivar impide nuevos inicios de sesión,
-- pero una sesión ya abierta puede seguir hasta vencer (≤ 1 h).
--
-- Todo en una transacción. NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

-- 1. HELPER: el usuario actual es el superadmin activo ---------
CREATE OR REPLACE FUNCTION public._es_superadmin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM usuarios
    WHERE id = auth.uid() AND rol = 'superadmin' AND activo
  );
$$;

-- 2. EDITAR USUARIO --------------------------------------------
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

  -- Carrera oficial y activa para ambos roles (para alumnos también
  -- lo exige el trigger trg_usuarios_validar_carrera).
  IF NOT EXISTS (SELECT 1 FROM carreras WHERE nombre = v_carrera AND activa) THEN
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

-- 3. DESACTIVAR USUARIO ----------------------------------------
CREATE OR REPLACE FUNCTION public.desactivar_usuario(p_usuario_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede desactivar usuarios';
  END IF;
  IF p_usuario_id = auth.uid() THEN
    RAISE EXCEPTION 'No podés desactivar tu propia cuenta';
  END IF;

  UPDATE usuarios SET activo = FALSE
  WHERE id = p_usuario_id AND rol IN ('alumno', 'admin') AND activo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario no existe, no es alumno ni administrador o ya está desactivado';
  END IF;

  -- Impide nuevos inicios de sesión y la renovación de la sesión.
  UPDATE auth.users SET banned_until = 'infinity' WHERE id = p_usuario_id;
END;
$$;

-- 4. REACTIVAR USUARIO -----------------------------------------
CREATE OR REPLACE FUNCTION public.reactivar_usuario(p_usuario_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede reactivar usuarios';
  END IF;

  UPDATE usuarios SET activo = TRUE
  WHERE id = p_usuario_id AND rol IN ('alumno', 'admin') AND NOT activo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario no existe, no es alumno ni administrador o ya está activo';
  END IF;

  UPDATE auth.users SET banned_until = NULL WHERE id = p_usuario_id;
END;
$$;

-- 5. PERMISOS --------------------------------------------------
REVOKE EXECUTE ON FUNCTION public._es_superadmin()
  FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION
  public.editar_usuario(UUID, TEXT, TEXT, TEXT, INT, TEXT),
  public.desactivar_usuario(UUID),
  public.reactivar_usuario(UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.editar_usuario(UUID, TEXT, TEXT, TEXT, INT, TEXT),
  public.desactivar_usuario(UUID),
  public.reactivar_usuario(UUID)
TO authenticated;

COMMIT;