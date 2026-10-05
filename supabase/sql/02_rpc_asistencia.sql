-- =========================================================
-- 02_rpc_asistencia.sql
-- Todas las funciones son SECURITY DEFINER: el cliente nunca
-- escribe en inscripciones ni lee sesiones_asistencia directo.
-- search_path incluye "extensions" porque en Supabase pgcrypto
-- (hmac, gen_random_bytes) vive en ese schema.
-- =========================================================

-- Una sola sesión abierta por evento (un QR por evento)
CREATE UNIQUE INDEX IF NOT EXISTS uq_sesion_abierta_por_evento
  ON sesiones_asistencia (evento_id) WHERE abierta;

-- ---------------------------------------------------------
-- Helper: ¿el usuario actual puede gestionar este evento?
-- Admin, o validador activo, vigente y asignado a ESE evento.
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.puede_gestionar_evento(p_evento_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM usuarios u
    WHERE u.id = auth.uid()
      AND u.activo = TRUE
      AND (
        u.rol = 'admin'
        OR (
          u.rol = 'validador'
          AND u.evento_asignado_id = p_evento_id
          AND u.vigente_hasta > NOW()
        )
      )
  );
$$;

-- ---------------------------------------------------------
-- Interno: firma HMAC del token QR (20 hex = QR liviano)
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public._firma_qr(
  p_secreto TEXT, p_sesion_id UUID, p_ventana BIGINT
)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT left(
    encode(
      hmac(p_sesion_id::text || ':' || p_ventana::text, p_secreto, 'sha256'),
      'hex'
    ), 20);
$$;

-- ---------------------------------------------------------
-- Interno: registra el marcaje del alumno actual.
-- validado_por = validador de la sesión (auditoría).
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public._registrar_marcaje(
  p_sesion sesiones_asistencia, p_metodo TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_confirmada BOOLEAN;
BEGIN
  SELECT asistencia_confirmada INTO v_confirmada
  FROM inscripciones
  WHERE usuario_id = auth.uid() AND evento_id = p_sesion.evento_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No estás inscripto a este evento';
  END IF;
  IF v_confirmada THEN
    RAISE EXCEPTION 'Tu asistencia ya fue registrada';
  END IF;

  UPDATE inscripciones
  SET asistencia_confirmada = TRUE,
      metodo_validacion     = p_metodo,
      fecha_marcaje         = NOW(),
      fecha_validacion      = NOW(),
      validado_por          = p_sesion.validador_id,
      sesion_id             = p_sesion.id
  WHERE usuario_id = auth.uid() AND evento_id = p_sesion.evento_id;
END;
$$;

-- ---------------------------------------------------------
-- 1. Abrir sesión (idempotente: devuelve la abierta si existe)
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.abrir_sesion_asistencia(p_evento_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_sesion_id UUID;
BEGIN
  IF NOT puede_gestionar_evento(p_evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para gestionar la asistencia de este evento';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM eventos WHERE id = p_evento_id AND activo) THEN
    RAISE EXCEPTION 'El evento no existe o no está activo';
  END IF;

  SELECT id INTO v_sesion_id
  FROM sesiones_asistencia
  WHERE evento_id = p_evento_id AND abierta
  LIMIT 1;

  IF v_sesion_id IS NULL THEN
    INSERT INTO sesiones_asistencia (evento_id, validador_id)
    VALUES (p_evento_id, auth.uid())
    RETURNING id INTO v_sesion_id;
  END IF;

  RETURN v_sesion_id;
END;
$$;

-- ---------------------------------------------------------
-- 2. Token QR rotativo (ventanas de 5 s). Lo pide el dispositivo
--    del validador cada 5 s; el secreto nunca sale de la base.
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.obtener_token_qr(p_sesion_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_sesion  sesiones_asistencia%ROWTYPE;
  v_ventana BIGINT;
BEGIN
  SELECT * INTO v_sesion FROM sesiones_asistencia WHERE id = p_sesion_id;

  IF NOT FOUND OR NOT v_sesion.abierta THEN
    RAISE EXCEPTION 'La sesión de asistencia no está abierta';
  END IF;
  IF NOT puede_gestionar_evento(v_sesion.evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para gestionar este evento';
  END IF;

  v_ventana := floor(extract(epoch FROM NOW()) / 5)::BIGINT;

  RETURN p_sesion_id::text || ':' || v_ventana::text || ':' ||
         _firma_qr(v_sesion.secreto, p_sesion_id, v_ventana);
END;
$$;

-- ---------------------------------------------------------
-- 3. Marcaje por QR (alumno). Token válido: ventana actual y las
--    2 anteriores (~10-15 s de tolerancia).
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marcar_asistencia_qr(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_partes    TEXT[];
  v_sesion_id UUID;
  v_ventana   BIGINT;
  v_actual    BIGINT;
  v_sesion    sesiones_asistencia%ROWTYPE;
BEGIN
  IF rol_actual() IS DISTINCT FROM 'alumno' THEN
    RAISE EXCEPTION 'Solo los alumnos pueden marcar asistencia';
  END IF;

  v_partes := string_to_array(COALESCE(p_token, ''), ':');
  IF array_length(v_partes, 1) IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'Código QR inválido';
  END IF;

  BEGIN
    v_sesion_id := v_partes[1]::UUID;
    v_ventana   := v_partes[2]::BIGINT;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Código QR inválido';
  END;

  SELECT * INTO v_sesion
  FROM sesiones_asistencia WHERE id = v_sesion_id AND abierta;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sesión de asistencia no está abierta';
  END IF;

  v_actual := floor(extract(epoch FROM NOW()) / 5)::BIGINT;
  IF v_ventana < v_actual - 2 OR v_ventana > v_actual THEN
    RAISE EXCEPTION 'El código QR expiró. Escaneá el que está proyectado ahora';
  END IF;

  IF v_partes[3] IS DISTINCT FROM _firma_qr(v_sesion.secreto, v_sesion_id, v_ventana) THEN
    RAISE EXCEPTION 'Código QR inválido';
  END IF;

  PERFORM _registrar_marcaje(v_sesion, 'qr');
END;
$$;

-- ---------------------------------------------------------
-- 4. Activar PIN de respaldo (4 dígitos, vigencia 1-15 min).
--    Al emitir un PIN nuevo se reinician los intentos.
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.activar_pin(
  p_sesion_id UUID, p_minutos INT DEFAULT 5
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_sesion sesiones_asistencia%ROWTYPE;
  v_pin    TEXT;
BEGIN
  SELECT * INTO v_sesion
  FROM sesiones_asistencia WHERE id = p_sesion_id AND abierta;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sesión de asistencia no está abierta';
  END IF;
  IF NOT puede_gestionar_evento(v_sesion.evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para gestionar este evento';
  END IF;
  IF p_minutos < 1 OR p_minutos > 15 THEN
    RAISE EXCEPTION 'La vigencia del PIN debe estar entre 1 y 15 minutos';
  END IF;

  v_pin := lpad(floor(random() * 10000)::INT::TEXT, 4, '0');

  UPDATE sesiones_asistencia
  SET pin = v_pin,
      pin_expira_en = NOW() + make_interval(mins => p_minutos)
  WHERE id = p_sesion_id;

  DELETE FROM intentos_pin WHERE sesion_id = p_sesion_id;

  RETURN v_pin;
END;
$$;

-- ---------------------------------------------------------
-- 5. Marcaje por PIN (alumno). Máx. 5 intentos fallidos.
--    IMPORTANTE: devuelve un código en vez de lanzar excepción
--    cuando el PIN es incorrecto. Un RAISE revierte la
--    transacción y borraría el incremento de intentos, con lo
--    cual el límite nunca se aplicaría.
--    Retorna: 'ok' | 'incorrecto' | 'bloqueado' | 'pin_no_activo'
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marcar_asistencia_pin(
  p_evento_id UUID, p_pin TEXT
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_sesion     sesiones_asistencia%ROWTYPE;
  v_confirmada BOOLEAN;
  v_intentos   INT;
BEGIN
  IF rol_actual() IS DISTINCT FROM 'alumno' THEN
    RAISE EXCEPTION 'Solo los alumnos pueden marcar asistencia';
  END IF;

  SELECT asistencia_confirmada INTO v_confirmada
  FROM inscripciones
  WHERE usuario_id = auth.uid() AND evento_id = p_evento_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No estás inscripto a este evento';
  END IF;
  IF v_confirmada THEN
    RAISE EXCEPTION 'Tu asistencia ya fue registrada';
  END IF;

  SELECT * INTO v_sesion
  FROM sesiones_asistencia WHERE evento_id = p_evento_id AND abierta;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No hay una sesión de asistencia abierta para este evento';
  END IF;

  IF v_sesion.pin IS NULL OR v_sesion.pin_expira_en <= NOW() THEN
    RETURN 'pin_no_activo';
  END IF;

  INSERT INTO intentos_pin (sesion_id, usuario_id)
  VALUES (v_sesion.id, auth.uid())
  ON CONFLICT DO NOTHING;

  SELECT intentos INTO v_intentos
  FROM intentos_pin
  WHERE sesion_id = v_sesion.id AND usuario_id = auth.uid()
  FOR UPDATE;

  IF v_intentos >= 5 THEN
    RETURN 'bloqueado';
  END IF;

  IF p_pin IS DISTINCT FROM v_sesion.pin THEN
    UPDATE intentos_pin SET intentos = intentos + 1
    WHERE sesion_id = v_sesion.id AND usuario_id = auth.uid();
    RETURN 'incorrecto';
  END IF;

  PERFORM _registrar_marcaje(v_sesion, 'pin');
  RETURN 'ok';
END;
$$;

-- ---------------------------------------------------------
-- 6. Cerrar sesión (invalida QR y PIN al instante)
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cerrar_sesion_asistencia(p_sesion_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_evento_id UUID;
BEGIN
  SELECT evento_id INTO v_evento_id
  FROM sesiones_asistencia WHERE id = p_sesion_id;

  IF NOT FOUND OR NOT puede_gestionar_evento(v_evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para cerrar esta sesión';
  END IF;

  UPDATE sesiones_asistencia
  SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL
  WHERE id = p_sesion_id;
END;
$$;

-- ---------------------------------------------------------
-- 7. Desactivar validador (solo admin). Cierra sus sesiones.
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.desactivar_validador(p_usuario_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF rol_actual() IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Solo un administrador puede desactivar validadores';
  END IF;

  UPDATE usuarios SET activo = FALSE
  WHERE id = p_usuario_id AND rol = 'validador';

  UPDATE sesiones_asistencia
  SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL
  WHERE validador_id = p_usuario_id AND abierta;
END;
$$;

-- ---------------------------------------------------------
-- 8. Quórum: inscriptos vs. presentes
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resumen_asistencia(p_evento_id UUID)
RETURNS TABLE (inscriptos INT, presentes INT)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT puede_gestionar_evento(p_evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para ver este evento';
  END IF;

  RETURN QUERY
  SELECT COUNT(*)::INT,
         COUNT(*) FILTER (WHERE asistencia_confirmada)::INT
  FROM inscripciones
  WHERE evento_id = p_evento_id;
END;
$$;

-- ---------------------------------------------------------
-- 9. Corrección manual (solo admin), individual o en lote.
--    Siempre auditada. Si se revoca, se anula el hash del
--    certificado para que deje de ser válido.
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.corregir_asistencia(
  p_inscripcion_ids UUID[], p_confirmada BOOLEAN
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_filas INT;
BEGIN
  IF rol_actual() IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Solo un administrador puede corregir asistencias';
  END IF;

  UPDATE inscripciones
  SET asistencia_confirmada = p_confirmada,
      metodo_validacion     = 'manual',
      fecha_marcaje         = CASE WHEN p_confirmada THEN NOW() ELSE NULL END,
      fecha_validacion      = NOW(),
      validado_por          = auth.uid(),
      sesion_id             = NULL,
      hash_certificado      = CASE WHEN p_confirmada THEN hash_certificado ELSE NULL END
  WHERE id = ANY(p_inscripcion_ids);

  GET DIAGNOSTICS v_filas = ROW_COUNT;
  RETURN v_filas;
END;
$$;

-- =========================================================
-- PERMISOS DE EJECUCIÓN
-- Supabase da EXECUTE a anon por defecto: lo quitamos.
-- =========================================================
REVOKE EXECUTE ON FUNCTION
  public.puede_gestionar_evento(UUID),
  public.abrir_sesion_asistencia(UUID),
  public.obtener_token_qr(UUID),
  public.marcar_asistencia_qr(TEXT),
  public.activar_pin(UUID, INT),
  public.marcar_asistencia_pin(UUID, TEXT),
  public.cerrar_sesion_asistencia(UUID),
  public.desactivar_validador(UUID),
  public.resumen_asistencia(UUID),
  public.corregir_asistencia(UUID[], BOOLEAN),
  public.rol_actual(),
  public.inscribirse_a_evento(UUID)
FROM PUBLIC, anon;

-- Funciones internas: ni siquiera authenticated puede llamarlas
REVOKE EXECUTE ON FUNCTION
  public._firma_qr(TEXT, UUID, BIGINT),
  public._registrar_marcaje(sesiones_asistencia, TEXT)
FROM PUBLIC, anon, authenticated;

-- Endurecer la RPC de inscripción que hicimos antes
ALTER FUNCTION public.inscribirse_a_evento(UUID)
  SET search_path = public, extensions;