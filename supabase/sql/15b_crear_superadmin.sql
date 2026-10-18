-- =========================================================
-- 15b_crear_superadmin.sql
-- Fase 5, paso 5.1: perfil del ÚNICO superadmin.
--
-- Requisitos:
-- 1. Script 15 ya ejecutado (CHECK con 'superadmin').
-- 2. Kevin creó antes la cuenta en Supabase:
--    Authentication > Users > crear usuario nuevo, con el correo
--    institucional del superadmin, una contraseña elegida por él y
--    el correo confirmado automáticamente.
--    La contraseña NUNCA se escribe en este script ni en un chat.
--
-- Este script solo crea la fila en public.usuarios para esa cuenta.
-- No asciende cuentas existentes: si el correo ya tiene perfil, falla.
-- El índice ux_usuarios_un_superadmin impide un segundo superadmin.
--
-- Antes de ejecutar: completar los 3 valores de la sección 1.
-- Todo en una transacción. NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

DO $$
DECLARE
  -- 1. COMPLETAR ---------------------------------------------
  v_correo  TEXT := 'superadmin1@uninorte.edu.py';  -- mismo correo que en Auth
  v_nombre  TEXT := 'SuperAdmin1';                  -- nombre completo
  v_ci      TEXT := '7894561';                  -- C.I. con la que inicia sesión (4 a 10 dígitos)
  -- ----------------------------------------------------------
  v_id UUID;
BEGIN
  v_correo := lower(trim(v_correo));
  v_nombre := trim(v_nombre);
  v_ci     := trim(v_ci);

  IF v_correo LIKE 'completar%' OR v_nombre = 'COMPLETAR' OR v_ci = 'COMPLETAR' THEN
    RAISE EXCEPTION 'Completá correo, nombre y C.I. en la sección 1';
  END IF;
  IF v_correo NOT LIKE '%@uninorte.edu.py' THEN
    RAISE EXCEPTION 'El correo debe ser institucional (@uninorte.edu.py)';
  END IF;
  IF length(v_nombre) < 3 THEN
    RAISE EXCEPTION 'Ingresá el nombre completo';
  END IF;
  IF v_ci !~ '^\d{4,10}$' THEN
    RAISE EXCEPTION 'La C.I. debe tener entre 4 y 10 dígitos';
  END IF;

  -- La cuenta debe existir en Auth
  SELECT id INTO v_id FROM auth.users WHERE lower(email) = v_correo;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'No existe una cuenta en Auth con el correo %. Creala primero en Authentication > Users', v_correo;
  END IF;

  -- Cuenta nueva: no debe tener perfil
  IF EXISTS (SELECT 1 FROM public.usuarios WHERE id = v_id) THEN
    RAISE EXCEPTION 'Esa cuenta ya tiene perfil en usuarios: este script no asciende cuentas existentes';
  END IF;

  -- C.I. y correo libres
  IF EXISTS (SELECT 1 FROM public.usuarios
             WHERE ci = v_ci OR lower(correo_institucional) = v_correo) THEN
    RAISE EXCEPTION 'Ya existe un usuario con esa C.I. o ese correo';
  END IF;

  -- Un solo superadmin (el índice único también lo garantiza)
  IF EXISTS (SELECT 1 FROM public.usuarios WHERE rol = 'superadmin') THEN
    RAISE EXCEPTION 'Ya existe un superadmin';
  END IF;

  INSERT INTO public.usuarios
    (id, nombre_completo, ci, correo_institucional, carrera, rol)
  VALUES
    (v_id, v_nombre, v_ci, v_correo, 'Administración del sistema', 'superadmin');

  RAISE NOTICE 'Superadmin creado: % (C.I. %)', v_nombre, v_ci;
END;
$$;

COMMIT;