-- =========================================================
-- 14b_pin_compartido.sql
-- Ajuste 1 (fase 4G), complemento del 14: PIN compartido entre
-- varios validadores del mismo evento (aprobado por Kevin, 18/10).
--
-- - Si ya hay un PIN vigente en la sesión, activar_pin devuelve ESE
--   mismo PIN en lugar de generar otro. Así todos los validadores
--   muestran el mismo número y un alumno no gasta intentos con un
--   PIN que otro validador reemplazó.
-- - Devuelve también segundos_restantes, para que el panel no
--   dependa del reloj del dispositivo.
-- - Cambia el tipo de retorno: se hace DROP + CREATE. La app actual
--   sigue funcionando (lee pin_codigo y vence_en; ignora la columna nueva).
--
-- Todo en una transacción. NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

DROP FUNCTION IF EXISTS public.activar_pin(UUID);

CREATE FUNCTION public.activar_pin(p_sesion_id UUID)
RETURNS TABLE (pin_codigo TEXT, vence_en TIMESTAMPTZ, segundos_restantes INT)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_ses    sesiones_asistencia%ROWTYPE;
  v_pin    TEXT;
  v_expira TIMESTAMPTZ;
BEGIN
  SELECT * INTO v_ses
  FROM sesiones_asistencia WHERE id = p_sesion_id AND abierta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sesión de asistencia no está abierta';
  END IF;
  IF NOT puede_validar_evento(v_ses.evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para gestionar este evento';
  END IF;
  IF v_ses.modo IS NULL OR NOW() >= v_ses.modo_hasta THEN
    RAISE EXCEPTION 'No hay un registro de entrada o salida activo';
  END IF;

  IF v_ses.pin IS NOT NULL AND v_ses.pin_expira_en > NOW() + INTERVAL '2 seconds' THEN
    -- Hay un PIN vigente (de este u otro validador): se reutiliza.
    v_pin    := v_ses.pin;
    v_expira := v_ses.pin_expira_en;
  ELSE
    v_pin := lpad(
      ((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::BIGINT) % 10000)::TEXT,
      4, '0');
    v_expira := LEAST(NOW() + INTERVAL '20 seconds', v_ses.modo_hasta);

    UPDATE sesiones_asistencia
    SET pin = v_pin, pin_expira_en = v_expira
    WHERE id = p_sesion_id;
  END IF;

  RETURN QUERY
  SELECT v_pin,
         v_expira,
         GREATEST(CEIL(EXTRACT(EPOCH FROM (v_expira - NOW()))), 0)::INT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.activar_pin(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activar_pin(UUID) TO authenticated;

COMMIT;