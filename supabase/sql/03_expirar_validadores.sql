-- Desactiva validadores vencidos, cierra sus sesiones y los banea en Auth.
CREATE OR REPLACE FUNCTION public.expirar_validadores()
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_baneados INT;
BEGIN
  -- 1. Marcar como inactivos los vencidos
  UPDATE usuarios SET activo = FALSE
  WHERE rol = 'validador' AND activo AND vigente_hasta <= NOW();

  -- 2. Cerrar sus sesiones abiertas (invalida QR y PIN)
  UPDATE sesiones_asistencia s
  SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL
  FROM usuarios u
  WHERE s.validador_id = u.id AND s.abierta
    AND u.rol = 'validador' AND NOT u.activo;

  -- 3. Banear en Auth a todo validador inactivo (vencido o desactivado a mano)
  UPDATE auth.users a
  SET banned_until = 'infinity'
  FROM usuarios u
  WHERE a.id = u.id AND u.rol = 'validador' AND NOT u.activo
    AND (a.banned_until IS NULL OR a.banned_until < 'infinity');

  GET DIAGNOSTICS v_baneados = ROW_COUNT;
  RETURN v_baneados;
END;
$$;

-- Solo cron (postgres) la ejecuta; ningún cliente puede llamarla
REVOKE EXECUTE ON FUNCTION public.expirar_validadores()
  FROM PUBLIC, anon, authenticated;

SELECT cron.schedule(
  'expirar-validadores',
  '*/5 * * * *',
  $$SELECT public.expirar_validadores()$$
);