-- =========================================================
-- 10_asistencia_entrada_salida.sql
-- Fase 4A: entrada/salida, QR 60 s (+10 s de gracia), PIN 20 s,
-- activación de modo (solo service_role), cierre parcial,
-- correcciones auditadas y horas sin eventos cancelados.
-- =========================================================

-- 0. Cierra las sesiones abiertas (formato anterior, sin modo)
UPDATE sesiones_asistencia
SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL
WHERE abierta;

-- 1. EVENTOS: tolerancia de salida y autorización de salida anticipada
ALTER TABLE eventos
  ADD COLUMN IF NOT EXISTS tolerancia_salida_min SMALLINT NOT NULL DEFAULT 15
    CHECK (tolerancia_salida_min BETWEEN 0 AND 120),
  ADD COLUMN IF NOT EXISTS salida_anticipada_en TIMESTAMPTZ;

-- 2. INSCRIPCIONES: entrada y salida
ALTER TABLE inscripciones
  ADD COLUMN IF NOT EXISTS entrada_en TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS salida_en TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS metodo_entrada TEXT
    CHECK (metodo_entrada IN ('qr', 'pin', 'manual')),
  ADD COLUMN IF NOT EXISTS metodo_salida TEXT
    CHECK (metodo_salida IN ('qr', 'pin', 'manual')),
  ADD COLUMN IF NOT EXISTS migrado BOOLEAN NOT NULL DEFAULT FALSE;

-- Asistencias ya confirmadas: se conservan como entrada y salida migradas
UPDATE inscripciones
SET entrada_en     = COALESCE(fecha_marcaje, fecha_validacion, NOW()),
    salida_en      = COALESCE(fecha_marcaje, fecha_validacion, NOW()),
    metodo_entrada = COALESCE(metodo_validacion, 'manual'),
    metodo_salida  = COALESCE(metodo_validacion, 'manual'),
    migrado        = TRUE
WHERE asistencia_confirmada AND entrada_en IS NULL;

ALTER TABLE inscripciones
  DROP CONSTRAINT IF EXISTS inscripciones_salida_requiere_entrada;
ALTER TABLE inscripciones
  ADD CONSTRAINT inscripciones_salida_requiere_entrada
  CHECK (salida_en IS NULL OR (entrada_en IS NOT NULL AND salida_en >= entrada_en));

-- asistencia_confirmada se deriva siempre: verdadera solo con entrada y salida
CREATE OR REPLACE FUNCTION public._sync_asistencia_confirmada()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.asistencia_confirmada := (NEW.entrada_en IS NOT NULL AND NEW.salida_en IS NOT NULL);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inscripciones_sync_confirmada ON inscripciones;
CREATE TRIGGER trg_inscripciones_sync_confirmada
  BEFORE INSERT OR UPDATE ON inscripciones
  FOR EACH ROW EXECUTE FUNCTION public._sync_asistencia_confirmada();

-- No se emiten certificados de eventos cancelados
CREATE OR REPLACE FUNCTION public._bloquear_certificado_cancelado()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.hash_certificado IS NOT NULL
     AND NEW.hash_certificado IS DISTINCT FROM OLD.hash_certificado
     AND EXISTS (SELECT 1 FROM eventos
                 WHERE id = NEW.evento_id AND estado = 'cancelado') THEN
    RAISE EXCEPTION 'No se emiten certificados de eventos cancelados';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inscripciones_sin_certificado_cancelado ON inscripciones;
CREATE TRIGGER trg_inscripciones_sin_certificado_cancelado
  BEFORE UPDATE ON inscripciones
  FOR EACH ROW EXECUTE FUNCTION public._bloquear_certificado_cancelado();

-- Con una entrada registrada, fecha, horario y tolerancias quedan bloqueados
CREATE OR REPLACE FUNCTION public._bloquear_cambio_horario()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (NEW.fecha, NEW.hora_inicio, NEW.hora_fin,
      NEW.tolerancia_entrada_min, NEW.tolerancia_salida_min)
     IS DISTINCT FROM
     (OLD.fecha, OLD.hora_inicio, OLD.hora_fin,
      OLD.tolerancia_entrada_min, OLD.tolerancia_salida_min)
     AND EXISTS (SELECT 1 FROM inscripciones
                 WHERE evento_id = NEW.id AND entrada_en IS NOT NULL) THEN
    RAISE EXCEPTION 'Ya hay entradas registradas: no se pueden cambiar fecha, horario ni tolerancias';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_bloquear_horario ON eventos;
CREATE TRIGGER trg_eventos_bloquear_horario
  BEFORE UPDATE ON eventos
  FOR EACH ROW EXECUTE FUNCTION public._bloquear_cambio_horario();

-- 3. SESIONES: modo activo (entrada | salida) y su ventana
ALTER TABLE sesiones_asistencia
  ADD COLUMN IF NOT EXISTS modo TEXT CHECK (modo IN ('entrada', 'salida')),
  ADD COLUMN IF NOT EXISTS modo_desde TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS modo_hasta TIMESTAMPTZ;

-- Una sola sesión abierta por evento, garantizado por la base
CREATE UNIQUE INDEX IF NOT EXISTS ux_sesion_abierta_por_evento
  ON sesiones_asistencia (evento_id) WHERE abierta;

-- 4. INTENTOS DE PIN: acumulados por sesión + modo (no se reinician con cada PIN)
DROP TABLE IF EXISTS intentos_pin;
CREATE TABLE intentos_pin (
  sesion_id  UUID NOT NULL REFERENCES sesiones_asistencia(id) ON DELETE CASCADE,
  usuario_id UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  modo       TEXT NOT NULL CHECK (modo IN ('entrada', 'salida')),
  intentos   INT  NOT NULL DEFAULT 0,
  PRIMARY KEY (sesion_id, usuario_id, modo)
);
ALTER TABLE intentos_pin ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON intentos_pin FROM PUBLIC, anon, authenticated;

-- 5. AUDITORÍA DE CORRECCIONES
CREATE TABLE IF NOT EXISTS correcciones_asistencia (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inscripcion_id  UUID NOT NULL REFERENCES inscripciones(id) ON DELETE CASCADE,
  campo           TEXT NOT NULL CHECK (campo IN ('entrada', 'salida')),
  valor_anterior  TIMESTAMPTZ,
  valor_nuevo     TIMESTAMPTZ,
  motivo          TEXT NOT NULL CHECK (length(trim(motivo)) >= 5),
  corregido_por   UUID NOT NULL REFERENCES usuarios(id),
  corregido_en    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE correcciones_asistencia ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON correcciones_asistencia FROM PUBLIC, anon;
GRANT SELECT ON correcciones_asistencia TO authenticated;

DROP POLICY IF EXISTS correcciones_select_admin ON correcciones_asistencia;
CREATE POLICY correcciones_select_admin ON correcciones_asistencia
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') IN ('admin', 'superadmin'));

-- 6. HELPERS
CREATE OR REPLACE FUNCTION public._hora_local(p_fecha DATE, p_hora TIME)
RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE
AS $$ SELECT (p_fecha + p_hora) AT TIME ZONE 'America/Asuncion'; $$;

CREATE OR REPLACE FUNCTION public._firma_qr_modo(
  p_secreto TEXT, p_sesion_id UUID, p_modo TEXT, p_ventana BIGINT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
SET search_path TO 'public', 'extensions'
AS $$
  SELECT left(encode(hmac(
    p_sesion_id::text || ':' || p_modo || ':' || p_ventana::text,
    p_secreto, 'sha256'), 'hex'), 20);
$$;

-- Solo el validador asignado, activo y vigente (ni admin ni superadmin)
CREATE OR REPLACE FUNCTION public.puede_validar_evento(p_evento_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM usuarios u
    WHERE u.id = auth.uid()
      AND u.activo = TRUE
      AND u.rol = 'validador'
      AND u.evento_asignado_id = p_evento_id
      AND u.vigente_hasta > NOW()
  );
$$;

-- Gestión de lectura: admin, superadmin o el validador del evento
CREATE OR REPLACE FUNCTION public.puede_gestionar_evento(p_evento_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM usuarios u
    WHERE u.id = auth.uid()
      AND u.activo = TRUE
      AND (
        u.rol IN ('admin', 'superadmin')
        OR (u.rol = 'validador'
            AND u.evento_asignado_id = p_evento_id
            AND u.vigente_hasta > NOW())
      )
  );
$$;

-- 7. SESIÓN: abrir y cerrar (solo validador)
CREATE OR REPLACE FUNCTION public.abrir_sesion_asistencia(p_evento_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT puede_validar_evento(p_evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para gestionar la asistencia de este evento';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM eventos WHERE id = p_evento_id AND estado = 'vigente') THEN
    RAISE EXCEPTION 'El evento no existe o no está vigente';
  END IF;

  INSERT INTO sesiones_asistencia (evento_id, validador_id)
  VALUES (p_evento_id, auth.uid())
  ON CONFLICT (evento_id) WHERE abierta DO NOTHING;

  SELECT id INTO v_id
  FROM sesiones_asistencia WHERE evento_id = p_evento_id AND abierta;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cerrar_sesion_asistencia(p_sesion_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_evento_id UUID;
BEGIN
  SELECT evento_id INTO v_evento_id
  FROM sesiones_asistencia WHERE id = p_sesion_id;

  IF NOT FOUND OR NOT puede_validar_evento(v_evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para cerrar esta sesión';
  END IF;

  UPDATE sesiones_asistencia
  SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL,
      modo = NULL, modo_desde = NULL, modo_hasta = NULL
  WHERE id = p_sesion_id;
END;
$$;

-- Cierre parcial: cierra solo la entrada o la salida activa y deja la
-- sesión abierta. No pide clave (cerrar no abre acceso); reabrir sí.
CREATE OR REPLACE FUNCTION public.cerrar_modo_asistencia(p_sesion_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_evento_id UUID;
BEGIN
  SELECT evento_id INTO v_evento_id
  FROM sesiones_asistencia WHERE id = p_sesion_id AND abierta;

  IF NOT FOUND OR NOT puede_validar_evento(v_evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para cerrar este registro';
  END IF;

  UPDATE sesiones_asistencia
  SET pin = NULL, pin_expira_en = NULL,
      modo = NULL, modo_desde = NULL, modo_hasta = NULL
  WHERE id = p_sesion_id;
END;
$$;

-- 8. ACTIVAR ENTRADA / SALIDA
--    Solo la ejecuta la Edge Function (service_role), después de
--    verificar la clave del validador en el servidor (4B).
--    Entrada: desde 15 min antes de hora_inicio hasta hora_inicio + tolerancia.
--    Salida:  desde 15 min antes de hora_fin (antes, con autorización del
--             admin) hasta hora_fin + tolerancia de salida, sin importar
--             cuándo se activó. Tope: 00:00 del día siguiente.
CREATE OR REPLACE FUNCTION public.activar_modo_asistencia(
  p_sesion_id UUID, p_validador_id UUID, p_modo TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_ses    sesiones_asistencia%ROWTYPE;
  v_ev     eventos%ROWTYPE;
  v_ahora  TIMESTAMPTZ := NOW();
  v_inicio TIMESTAMPTZ;
  v_fin    TIMESTAMPTZ;
  v_desde  TIMESTAMPTZ;
  v_hasta  TIMESTAMPTZ;
BEGIN
  IF p_modo NOT IN ('entrada', 'salida') THEN
    RAISE EXCEPTION 'Modo inválido';
  END IF;

  SELECT * INTO v_ses
  FROM sesiones_asistencia WHERE id = p_sesion_id AND abierta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sesión de asistencia no está abierta';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM usuarios u
    WHERE u.id = p_validador_id AND u.rol = 'validador' AND u.activo
      AND u.evento_asignado_id = v_ses.evento_id AND u.vigente_hasta > v_ahora
  ) THEN
    RAISE EXCEPTION 'No tenés permiso para gestionar este evento';
  END IF;

  SELECT * INTO v_ev FROM eventos WHERE id = v_ses.evento_id FOR UPDATE;
  IF v_ev.estado <> 'vigente' THEN
    RAISE EXCEPTION 'El evento ya no está vigente';
  END IF;

  v_inicio := _hora_local(v_ev.fecha, v_ev.hora_inicio);
  v_fin    := _hora_local(v_ev.fecha, v_ev.hora_fin);

  IF p_modo = 'entrada' THEN
    v_desde := v_inicio - INTERVAL '15 minutes';
    v_hasta := v_inicio + make_interval(mins => v_ev.tolerancia_entrada_min);
    IF v_ahora < v_desde THEN
      RAISE EXCEPTION 'La entrada se puede activar desde las %',
        to_char(v_desde AT TIME ZONE 'America/Asuncion', 'HH24:MI');
    END IF;
  ELSE
    v_desde := v_fin - INTERVAL '15 minutes';
    v_hasta := LEAST(
      v_fin + make_interval(mins => v_ev.tolerancia_salida_min),
      _hora_local(v_ev.fecha + 1, TIME '00:00')
    );
    IF v_ahora < v_desde AND v_ev.salida_anticipada_en IS NULL THEN
      RAISE EXCEPTION 'La salida se puede activar desde las %. Antes, requiere autorización del administrador',
        to_char(v_desde AT TIME ZONE 'America/Asuncion', 'HH24:MI');
    END IF;
  END IF;

  IF v_ahora > v_hasta THEN
    RAISE EXCEPTION 'El plazo para registrar la % ya terminó', p_modo;
  END IF;

  -- Un solo modo activo: cambiar de modo apaga el PIN anterior
  UPDATE sesiones_asistencia SET
    modo          = p_modo,
    modo_desde    = CASE WHEN modo IS DISTINCT FROM p_modo OR modo_desde IS NULL
                         THEN v_ahora ELSE modo_desde END,
    pin           = CASE WHEN modo IS DISTINCT FROM p_modo THEN NULL ELSE pin END,
    pin_expira_en = CASE WHEN modo IS DISTINCT FROM p_modo THEN NULL ELSE pin_expira_en END,
    modo_hasta    = v_hasta
  WHERE id = p_sesion_id;

  RETURN v_hasta;
END;
$$;

-- 9. QR rotativo (60 s) y PIN (20 s a pedido), solo validador
CREATE OR REPLACE FUNCTION public.obtener_token_qr(p_sesion_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_ses     sesiones_asistencia%ROWTYPE;
  v_ventana BIGINT;
BEGIN
  SELECT * INTO v_ses FROM sesiones_asistencia WHERE id = p_sesion_id;
  IF NOT FOUND OR NOT v_ses.abierta THEN
    RAISE EXCEPTION 'La sesión de asistencia no está abierta';
  END IF;
  IF NOT puede_validar_evento(v_ses.evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para gestionar este evento';
  END IF;
  IF v_ses.modo IS NULL THEN
    RAISE EXCEPTION 'No hay un registro de entrada o salida activo';
  END IF;
  IF NOW() > v_ses.modo_hasta THEN
    RAISE EXCEPTION 'El plazo de registro terminó';
  END IF;

  v_ventana := floor(extract(epoch FROM NOW()) / 60)::BIGINT;

  RETURN p_sesion_id::text || ':' || v_ses.modo || ':' || v_ventana::text || ':' ||
         _firma_qr_modo(v_ses.secreto, p_sesion_id, v_ses.modo, v_ventana);
END;
$$;

DROP FUNCTION IF EXISTS public.activar_pin(UUID, INTEGER);

CREATE OR REPLACE FUNCTION public.activar_pin(p_sesion_id UUID)
RETURNS TABLE (pin_codigo TEXT, vence_en TIMESTAMPTZ)
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

  v_pin := lpad(
    ((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::BIGINT) % 10000)::TEXT,
    4, '0');
  v_expira := LEAST(NOW() + INTERVAL '20 seconds', v_ses.modo_hasta);

  UPDATE sesiones_asistencia
  SET pin = v_pin, pin_expira_en = v_expira
  WHERE id = p_sesion_id;

  RETURN QUERY SELECT v_pin, v_expira;
END;
$$;

-- 10. MARCAJE DEL ALUMNO
CREATE OR REPLACE FUNCTION public._registrar_marcaje(
  p_sesion sesiones_asistencia, p_metodo TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_ent TIMESTAMPTZ;
  v_sal TIMESTAMPTZ;
BEGIN
  SELECT entrada_en, salida_en INTO v_ent, v_sal
  FROM inscripciones
  WHERE usuario_id = auth.uid() AND evento_id = p_sesion.evento_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No estás inscripto a este evento';
  END IF;

  IF p_sesion.modo = 'entrada' THEN
    IF v_ent IS NOT NULL THEN
      RAISE EXCEPTION 'Tu entrada ya fue registrada';
    END IF;
    UPDATE inscripciones
    SET entrada_en = NOW(), metodo_entrada = p_metodo, sesion_id = p_sesion.id
    WHERE usuario_id = auth.uid() AND evento_id = p_sesion.evento_id;
  ELSE
    IF v_ent IS NULL THEN
      RAISE EXCEPTION 'Primero tenés que registrar tu entrada';
    END IF;
    IF v_sal IS NOT NULL THEN
      RAISE EXCEPTION 'Tu salida ya fue registrada';
    END IF;
    UPDATE inscripciones
    SET salida_en         = NOW(),
        metodo_salida     = p_metodo,
        metodo_validacion = p_metodo,   -- compatibilidad con la pantalla actual
        fecha_marcaje     = NOW(),
        fecha_validacion  = NOW(),
        validado_por      = p_sesion.validador_id,
        sesion_id         = p_sesion.id
    WHERE usuario_id = auth.uid() AND evento_id = p_sesion.evento_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.marcar_asistencia_qr(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_partes    TEXT[];
  v_sesion_id UUID;
  v_ventana   BIGINT;
  v_actual    BIGINT;
  v_seg       INT;
  v_ses       sesiones_asistencia%ROWTYPE;
BEGIN
  IF rol_actual() IS DISTINCT FROM 'alumno' THEN
    RAISE EXCEPTION 'Solo los alumnos pueden marcar asistencia';
  END IF;

  v_partes := string_to_array(COALESCE(p_token, ''), ':');
  IF array_length(v_partes, 1) IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'Código QR inválido';
  END IF;

  BEGIN
    v_sesion_id := v_partes[1]::UUID;
    v_ventana   := v_partes[3]::BIGINT;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Código QR inválido';
  END;

  SELECT s.* INTO v_ses
  FROM sesiones_asistencia s JOIN eventos e ON e.id = s.evento_id
  WHERE s.id = v_sesion_id AND s.abierta AND e.estado = 'vigente';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sesión de asistencia no está abierta';
  END IF;

  IF v_ses.modo IS NULL OR NOW() > v_ses.modo_hasta THEN
    RAISE EXCEPTION 'El registro de entrada o salida no está habilitado en este momento';
  END IF;

  -- Ventana actual, o la anterior durante los primeros 10 s de la nueva
  v_actual := floor(extract(epoch FROM NOW()) / 60)::BIGINT;
  v_seg    := (floor(extract(epoch FROM NOW()))::BIGINT % 60)::INT;
  IF NOT (v_ventana = v_actual OR (v_ventana = v_actual - 1 AND v_seg < 10)) THEN
    RAISE EXCEPTION 'El código QR expiró. Escaneá el que está proyectado ahora';
  END IF;

  IF v_partes[4] IS DISTINCT FROM
     _firma_qr_modo(v_ses.secreto, v_sesion_id, v_partes[2], v_ventana) THEN
    RAISE EXCEPTION 'Código QR inválido';
  END IF;

  IF v_partes[2] IS DISTINCT FROM v_ses.modo THEN
    RAISE EXCEPTION 'Ese código QR corresponde a otro registro (entrada o salida)';
  END IF;

  PERFORM _registrar_marcaje(v_ses, 'qr');
END;
$$;

CREATE OR REPLACE FUNCTION public.marcar_asistencia_pin(p_evento_id UUID, p_pin TEXT)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_ses      sesiones_asistencia%ROWTYPE;
  v_ent      TIMESTAMPTZ;
  v_sal      TIMESTAMPTZ;
  v_intentos INT;
BEGIN
  IF rol_actual() IS DISTINCT FROM 'alumno' THEN
    RAISE EXCEPTION 'Solo los alumnos pueden marcar asistencia';
  END IF;

  SELECT entrada_en, salida_en INTO v_ent, v_sal
  FROM inscripciones
  WHERE usuario_id = auth.uid() AND evento_id = p_evento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No estás inscripto a este evento';
  END IF;

  SELECT s.* INTO v_ses
  FROM sesiones_asistencia s JOIN eventos e ON e.id = s.evento_id
  WHERE s.evento_id = p_evento_id AND s.abierta AND e.estado = 'vigente';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No hay una sesión de asistencia abierta para este evento';
  END IF;

  IF v_ses.modo IS NULL OR NOW() > v_ses.modo_hasta THEN
    RETURN 'registro_cerrado';
  END IF;

  IF v_ses.modo = 'entrada' THEN
    IF v_ent IS NOT NULL THEN
      RAISE EXCEPTION 'Tu entrada ya fue registrada';
    END IF;
  ELSE
    IF v_ent IS NULL THEN
      RAISE EXCEPTION 'Primero tenés que registrar tu entrada';
    END IF;
    IF v_sal IS NOT NULL THEN
      RAISE EXCEPTION 'Tu salida ya fue registrada';
    END IF;
  END IF;

  IF v_ses.pin IS NULL OR v_ses.pin_expira_en <= NOW() THEN
    RETURN 'pin_no_activo';
  END IF;

  INSERT INTO intentos_pin (sesion_id, usuario_id, modo)
  VALUES (v_ses.id, auth.uid(), v_ses.modo)
  ON CONFLICT DO NOTHING;

  SELECT intentos INTO v_intentos
  FROM intentos_pin
  WHERE sesion_id = v_ses.id AND usuario_id = auth.uid() AND modo = v_ses.modo
  FOR UPDATE;

  IF v_intentos >= 5 THEN
    RETURN 'bloqueado';
  END IF;

  IF p_pin IS DISTINCT FROM v_ses.pin THEN
    UPDATE intentos_pin SET intentos = intentos + 1
    WHERE sesion_id = v_ses.id AND usuario_id = auth.uid() AND modo = v_ses.modo;
    RETURN 'incorrecto';
  END IF;

  PERFORM _registrar_marcaje(v_ses, 'pin');
  RETURN 'ok';
END;
$$;

-- 11. RESUMEN (admin, superadmin y validador del evento)
DROP FUNCTION IF EXISTS public.resumen_asistencia(UUID);

CREATE OR REPLACE FUNCTION public.resumen_asistencia(p_evento_id UUID)
RETURNS TABLE (inscriptos INT, con_entrada INT, presentes INT)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  IF NOT puede_gestionar_evento(p_evento_id) THEN
    RAISE EXCEPTION 'No tenés permiso para ver este evento';
  END IF;

  RETURN QUERY
  SELECT COUNT(*)::INT,
         COUNT(*) FILTER (WHERE entrada_en IS NOT NULL)::INT,
         COUNT(*) FILTER (WHERE asistencia_confirmada)::INT
  FROM inscripciones
  WHERE evento_id = p_evento_id;
END;
$$;

-- 12. SALIDA ANTICIPADA (admin / superadmin): habilita la salida antes
--     de los 15 min previos a hora_fin. El plazo de los alumnos no cambia:
--     sigue venciendo a hora_fin + tolerancia de salida.
CREATE OR REPLACE FUNCTION public.autorizar_salida_anticipada(p_evento_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(rol_actual(), '') NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Solo un administrador puede autorizar una salida anticipada';
  END IF;

  UPDATE eventos SET salida_anticipada_en = NOW()
  WHERE id = p_evento_id
    AND estado = 'vigente'
    AND fecha = (NOW() AT TIME ZONE 'America/Asuncion')::DATE
    AND salida_anticipada_en IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El evento no está vigente, no es de hoy o ya tiene la salida anticipada autorizada';
  END IF;
END;
$$;

-- 13. CORRECCIÓN DEL ADMIN (entrada, salida o ambos, con motivo)
DROP FUNCTION IF EXISTS public.corregir_asistencia(UUID[], BOOLEAN);

CREATE OR REPLACE FUNCTION public.corregir_asistencia(
  p_inscripcion_ids UUID[],
  p_campo           TEXT,      -- 'entrada' | 'salida' | 'ambos'
  p_registrar       BOOLEAN,   -- TRUE registra, FALSE revoca
  p_motivo          TEXT)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  r       inscripciones%ROWTYPE;
  v_ent   TIMESTAMPTZ;
  v_sal   TIMESTAMPTZ;
  v_m_ent TEXT;
  v_m_sal TEXT;
  v_ahora TIMESTAMPTZ := NOW();
  v_n     INT := 0;
BEGIN
  IF COALESCE(rol_actual(), '') NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Solo un administrador puede corregir asistencias';
  END IF;
  IF p_campo NOT IN ('entrada', 'salida', 'ambos') THEN
    RAISE EXCEPTION 'Campo inválido';
  END IF;
  IF length(trim(COALESCE(p_motivo, ''))) < 5 THEN
    RAISE EXCEPTION 'Indicá el motivo de la corrección (mínimo 5 caracteres)';
  END IF;

  FOR r IN
    SELECT * FROM inscripciones WHERE id = ANY(p_inscripcion_ids) FOR UPDATE
  LOOP
    v_ent := r.entrada_en;
    v_sal := r.salida_en;

    IF p_registrar THEN
      IF p_campo IN ('entrada', 'ambos') AND v_ent IS NULL THEN
        v_ent := v_ahora;
      END IF;
      IF p_campo IN ('salida', 'ambos') AND v_sal IS NULL THEN
        IF v_ent IS NULL THEN
          RAISE EXCEPTION 'Hay alumnos sin entrada registrada: registrá primero la entrada';
        END IF;
        v_sal := v_ahora;
      END IF;
    ELSE
      IF p_campo IN ('entrada', 'ambos') THEN
        v_ent := NULL;
        v_sal := NULL;           -- la salida exige entrada
      ELSE
        v_sal := NULL;
      END IF;
    END IF;

    IF v_ent IS NOT DISTINCT FROM r.entrada_en
       AND v_sal IS NOT DISTINCT FROM r.salida_en THEN
      CONTINUE;
    END IF;

    IF v_ent IS DISTINCT FROM r.entrada_en THEN
      INSERT INTO correcciones_asistencia
        (inscripcion_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
      VALUES (r.id, 'entrada', r.entrada_en, v_ent, trim(p_motivo), auth.uid());
    END IF;
    IF v_sal IS DISTINCT FROM r.salida_en THEN
      INSERT INTO correcciones_asistencia
        (inscripcion_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
      VALUES (r.id, 'salida', r.salida_en, v_sal, trim(p_motivo), auth.uid());
    END IF;

    v_m_ent := CASE WHEN v_ent IS NULL THEN NULL
                    WHEN v_ent IS DISTINCT FROM r.entrada_en THEN 'manual'
                    ELSE r.metodo_entrada END;
    v_m_sal := CASE WHEN v_sal IS NULL THEN NULL
                    WHEN v_sal IS DISTINCT FROM r.salida_en THEN 'manual'
                    ELSE r.metodo_salida END;

    UPDATE inscripciones SET
      entrada_en        = v_ent,
      salida_en         = v_sal,
      metodo_entrada    = v_m_ent,
      metodo_salida     = v_m_sal,
      metodo_validacion = v_m_sal,      -- compatibilidad con la pantalla actual
      fecha_marcaje     = v_sal,
      fecha_validacion  = v_ahora,
      validado_por      = auth.uid(),
      hash_certificado  = CASE WHEN v_ent IS NOT NULL AND v_sal IS NOT NULL
                               THEN r.hash_certificado ELSE NULL END
    WHERE id = r.id;

    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END;
$$;

-- 14. HORAS ACREDITADAS: asistencia completa y evento NO cancelado.
--     Las asistencias de eventos cancelados se conservan como historial.
--     Certificados y reportes deben leer siempre de esta vista.
CREATE OR REPLACE VIEW public.vista_horas_acreditadas AS
SELECT i.id AS inscripcion_id,
       i.usuario_id,
       i.evento_id,
       e.horas_otorgadas,
       i.salida_en
FROM inscripciones i
JOIN eventos e ON e.id = i.evento_id
WHERE i.asistencia_confirmada AND e.estado <> 'cancelado';

-- Vista interna: se consulta solo a través de funciones
REVOKE ALL ON public.vista_horas_acreditadas FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.mis_horas_acreditadas()
RETURNS INT
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(horas_otorgadas), 0)::INT
  FROM vista_horas_acreditadas WHERE usuario_id = auth.uid();
$$;

-- 15. PERMISOS DE EJECUCIÓN
REVOKE EXECUTE ON FUNCTION
  public._sync_asistencia_confirmada(),
  public._bloquear_certificado_cancelado(),
  public._bloquear_cambio_horario(),
  public._hora_local(DATE, TIME),
  public._firma_qr_modo(TEXT, UUID, TEXT, BIGINT),
  public._registrar_marcaje(sesiones_asistencia, TEXT),
  public.activar_modo_asistencia(UUID, UUID, TEXT)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.activar_modo_asistencia(UUID, UUID, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION
  public.puede_validar_evento(UUID),
  public.puede_gestionar_evento(UUID),
  public.abrir_sesion_asistencia(UUID),
  public.cerrar_sesion_asistencia(UUID),
  public.cerrar_modo_asistencia(UUID),
  public.obtener_token_qr(UUID),
  public.activar_pin(UUID),
  public.marcar_asistencia_qr(TEXT),
  public.marcar_asistencia_pin(UUID, TEXT),
  public.resumen_asistencia(UUID),
  public.autorizar_salida_anticipada(UUID),
  public.corregir_asistencia(UUID[], TEXT, BOOLEAN, TEXT),
  public.mis_horas_acreditadas()
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.puede_validar_evento(UUID),
  public.puede_gestionar_evento(UUID),
  public.abrir_sesion_asistencia(UUID),
  public.cerrar_sesion_asistencia(UUID),
  public.cerrar_modo_asistencia(UUID),
  public.obtener_token_qr(UUID),
  public.activar_pin(UUID),
  public.marcar_asistencia_qr(TEXT),
  public.marcar_asistencia_pin(UUID, TEXT),
  public.resumen_asistencia(UUID),
  public.autorizar_salida_anticipada(UUID),
  public.corregir_asistencia(UUID[], TEXT, BOOLEAN, TEXT),
  public.mis_horas_acreditadas()
TO authenticated;