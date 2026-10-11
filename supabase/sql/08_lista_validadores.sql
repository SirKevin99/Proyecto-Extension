-- =========================================================
-- 08_lista_validadores.sql
-- Lista de validadores activos y desactivación (admin y superadmin)
-- =========================================================

-- 1. Lista de validadores vigentes con su evento asignado
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
  IF rol_actual() NOT IN ('admin', 'superadmin') THEN
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

REVOKE EXECUTE ON FUNCTION public.listar_validadores() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.listar_validadores() TO authenticated;

-- 2. Desactivar: ahora acepta superadmin y avisa si el validador no existe
CREATE OR REPLACE FUNCTION public.desactivar_validador(p_usuario_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  IF rol_actual() NOT IN ('admin', 'superadmin') THEN
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
END;
$$;