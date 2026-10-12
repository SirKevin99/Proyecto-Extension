-- 10b_estado_sesion_asistencia.sql
-- COMPLEMENTO de 10_asistencia_entrada_salida.sql (ejecutar DESPUÉS de ese).
-- NO ejecutar todavía: solo se prepara. Lo necesita el panel del validador
-- (4C) para saber qué modo está activo y hasta cuándo.

CREATE OR REPLACE FUNCTION public.estado_sesion_asistencia(p_sesion_id UUID)
RETURNS TABLE (esta_abierta BOOLEAN, modo_activo TEXT, modo_vence_en TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_ses sesiones_asistencia%ROWTYPE;
BEGIN
  SELECT * INTO v_ses FROM sesiones_asistencia WHERE id = p_sesion_id;

  IF NOT FOUND OR NOT puede_validar_evento(v_ses.evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para gestionar este evento';
  END IF;

  RETURN QUERY
  SELECT v_ses.abierta,
         CASE WHEN v_ses.abierta AND v_ses.modo_hasta > NOW()
              THEN v_ses.modo END,
         CASE WHEN v_ses.abierta AND v_ses.modo_hasta > NOW()
              THEN v_ses.modo_hasta END;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.estado_sesion_asistencia(UUID)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estado_sesion_asistencia(UUID)
  TO authenticated;