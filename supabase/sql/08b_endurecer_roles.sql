-- =========================================================
-- 08b_endurecer_roles.sql
-- 1) Chequeo de rol seguro ante NULL
-- 2) desactivar_validador banea en Auth de inmediato
-- =========================================================

CREATE OR REPLACE FUNCTION public._cerrar_evento(p_evento_id UUID, p_estado TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(rol_actual(), '') NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Solo un administrador puede cambiar el estado de un evento';
  END IF;

  UPDATE eventos SET estado = p_estado
  WHERE id = p_evento_id AND estado = 'vigente';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El evento no existe o ya no está vigente';
  END IF;

  UPDATE sesiones_asistencia
  SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL
  WHERE evento_id = p_evento_id AND abierta;

  UPDATE usuarios SET activo = FALSE
  WHERE rol = 'validador' AND evento_asignado_id = p_evento_id AND activo;
END;
$$;

CREATE OR REPLACE FUNCTION public.listar_validadores()
RETURNS TABLE (
  id UUID,
  nombre_completo TEXT,
  evento_id UUID,
  evento_nombre TEXT,
  evento_fecha DATE,
  vigente_hasta TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(rol_actual(), '') NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Solo un administrador puede ver los validadores';
  END IF;

  RETURN QUERY
  SELECT u.id,
         u.nombre_completo::TEXT,
         u.evento_asignado_id,
         e.nombre::TEXT,
         e.fecha::DATE,
         u.vigente_hasta
  FROM usuarios u
  LEFT JOIN eventos e ON e.id = u.evento_asignado_id
  WHERE u.rol = 'validador'
    AND u.activo
    AND u.vigente_hasta > NOW()
  ORDER BY e.fecha, u.nombre_completo;
END;
$$;

CREATE OR REPLACE FUNCTION public.desactivar_validador(p_usuario_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  IF COALESCE(rol_actual(), '') NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Solo un administrador puede desactivar validadores';
  END IF;

  UPDATE usuarios SET activo = FALSE
  WHERE id = p_usuario_id AND rol = 'validador' AND activo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El validador no existe o ya está desactivado';
  END IF;

  UPDATE sesiones_asistencia
  SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL
  WHERE validador_id = p_usuario_id AND abierta;

  -- Corte inmediato del acceso (el cron solo lo haría en <= 5 min)
  UPDATE auth.users SET banned_until = 'infinity' WHERE id = p_usuario_id;
END;
$$;