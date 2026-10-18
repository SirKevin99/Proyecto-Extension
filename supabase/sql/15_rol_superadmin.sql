-- =========================================================
-- 15_rol_superadmin.sql
-- Fase 5, paso 5.1: rol superadmin.
--
-- 1. El CHECK de usuarios acepta 'superadmin'.
-- 2. Índice único: puede existir UN SOLO superadmin.
-- 3. Las policies de lectura del admin (script 01) pasan a aceptar
--    también al superadmin, con chequeo NULL-safe.
--    eventos_update_admin se recrea igual que antes + superadmin.
-- 4. Se eliminan usuarios_insert_admin y usuarios_update_admin
--    (aprobado por Kevin, 18/10). La app no las usa: las altas van
--    por la Edge Function crear-usuario (service_role) y las
--    ediciones de usuarios (paso 5.3) irán por funciones del
--    servidor. Así un admin ya no puede cambiarse el rol a sí mismo
--    ni a otros con un UPDATE directo.
-- 5. Se quitan los permisos de escritura directa sobre usuarios
--    a anon y authenticated (defensa adicional a la RLS).
--
-- Policies verificadas en la base el 18/10 (consulta de solo lectura).
-- No se tocan: usuarios_select_propio, eventos_select_activos,
-- eventos_alumno_por_carrera, inscripciones_select_propio.
--
-- Todo en una transacción: si la verificación final falla, no
-- queda ningún cambio aplicado. NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

-- 1. CHECK DE ROLES -----------------------------------------
ALTER TABLE public.usuarios DROP CONSTRAINT IF EXISTS usuarios_rol_check;
ALTER TABLE public.usuarios
  ADD CONSTRAINT usuarios_rol_check
  CHECK (rol IN ('alumno', 'admin', 'validador', 'superadmin'));

-- 2. UN SOLO SUPERADMIN -------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_usuarios_un_superadmin
  ON public.usuarios (rol)
  WHERE rol = 'superadmin';

-- 3. POLICIES DE LECTURA: admin y superadmin -----------------

-- usuarios
DROP POLICY IF EXISTS "usuarios_select_admin" ON public.usuarios;
CREATE POLICY "usuarios_select_admin" ON public.usuarios
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') IN ('admin', 'superadmin'));

-- eventos
DROP POLICY IF EXISTS "eventos_select_admin" ON public.eventos;
CREATE POLICY "eventos_select_admin" ON public.eventos
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') IN ('admin', 'superadmin'));

DROP POLICY IF EXISTS "eventos_update_admin" ON public.eventos;
CREATE POLICY "eventos_update_admin" ON public.eventos
  FOR UPDATE TO authenticated
  USING (COALESCE(rol_actual(), '') IN ('admin', 'superadmin'));

-- inscripciones
DROP POLICY IF EXISTS "inscripciones_select_admin" ON public.inscripciones;
CREATE POLICY "inscripciones_select_admin" ON public.inscripciones
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') IN ('admin', 'superadmin'));

-- 4. SIN ESCRITURA DIRECTA SOBRE usuarios ---------------------
DROP POLICY IF EXISTS "usuarios_insert_admin" ON public.usuarios;
DROP POLICY IF EXISTS "usuarios_update_admin" ON public.usuarios;

-- 5. PERMISOS -------------------------------------------------
-- service_role conserva los suyos (script 06): crear-usuario sigue igual.
REVOKE INSERT, UPDATE, DELETE ON public.usuarios FROM anon, authenticated;

-- 6. VERIFICACIÓN FINAL (si falla, se revierte todo) ----------
DO $$
DECLARE
  v_escritura TEXT;
  v_solo_admin TEXT;
  v_check TEXT;
BEGIN
  -- Ninguna policy de escritura sobre usuarios
  SELECT string_agg(policyname, ', ') INTO v_escritura
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'usuarios'
    AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL');
  IF v_escritura IS NOT NULL THEN
    RAISE EXCEPTION 'Quedan policies de escritura en usuarios: %', v_escritura;
  END IF;

  -- Ninguna policy de usuarios/eventos/inscripciones que siga
  -- aceptando solo al admin
  SELECT string_agg(tablename || '.' || policyname, ', ') INTO v_solo_admin
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN ('usuarios', 'eventos', 'inscripciones')
    AND COALESCE(qual, '') || COALESCE(with_check, '') LIKE '%''admin''%'
    AND COALESCE(qual, '') || COALESCE(with_check, '') NOT LIKE '%superadmin%';
  IF v_solo_admin IS NOT NULL THEN
    RAISE EXCEPTION 'Policies que todavía aceptan solo admin: %', v_solo_admin;
  END IF;

  -- El CHECK acepta superadmin
  SELECT pg_get_constraintdef(oid) INTO v_check
  FROM pg_constraint WHERE conname = 'usuarios_rol_check';
  IF v_check IS NULL OR v_check NOT LIKE '%superadmin%' THEN
    RAISE EXCEPTION 'El CHECK usuarios_rol_check no incluye superadmin';
  END IF;
END;
$$;

COMMIT;