-- =========================================================
-- 14_varios_validadores.sql
-- Ajuste 1 (fase 4G): varios validadores por evento (máximo 5).
--
-- Lo que ya funcionaba sin cambios (scripts 10 y 10b):
-- - abrir_sesion_asistencia devuelve la sesión abierta si existe:
--   todos los validadores del evento comparten la misma sesión.
-- - QR, PIN, cerrar/reabrir modo y estado verifican "validador
--   asignado al evento", no "quién abrió la sesión".
-- - activar-modo pide la clave propia de cada validador.
--
-- Cambios de este script:
-- 1. Máximo 5 validadores activos y vigentes por evento (trigger).
-- 2. Auditoría: se guarda qué validador activó el modo actual
--    (modo_activado_por) y el marcaje del alumno se atribuye a él.
-- 3. Deshabilitar o vencer a UN validador ya no cierra la sesión
--    compartida si quedan otros validadores activos del evento.
--
-- Todo en una transacción. NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

-- 1. MÁXIMO 5 VALIDADORES ACTIVOS POR EVENTO --------------------
CREATE OR REPLACE FUNCTION public._limitar_validadores_por_evento()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_otros INT;
BEGIN
  IF NEW.rol = 'validador'
     AND NEW.activo
     AND NEW.vigente_hasta > NOW()
     AND NEW.evento_asignado_id IS NOT NULL THEN

    -- Serializa altas simultáneas para el mismo evento.
    PERFORM 1 FROM eventos WHERE id = NEW.evento_asignado_id FOR UPDATE;

    SELECT COUNT(*) INTO v_otros
    FROM usuarios
    WHERE rol = 'validador'
      AND activo
      AND vigente_hasta > NOW()
      AND evento_asignado_id = NEW.evento_asignado_id
      AND id <> NEW.id;

    IF v_otros >= 5 THEN
      RAISE EXCEPTION 'Este evento ya tiene 5 validadores activos (máximo permitido)';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_usuarios_limitar_validadores ON public.usuarios;
CREATE TRIGGER trg_usuarios_limitar_validadores
  BEFORE INSERT OR UPDATE OF rol, activo, vigente_hasta, evento_asignado_id
  ON public.usuarios
  FOR EACH ROW EXECUTE FUNCTION public._limitar_validadores_por_evento();

-- 2. QUIÉN ACTIVÓ EL MODO ACTUAL ----------------------------------
ALTER TABLE public.sesiones_asistencia
  ADD COLUMN IF NOT EXISTS modo_activado_por UUID REFERENCES public.usuarios(id);

-- 2.1 activar_modo_asistencia: igual que en 10 + modo_activado_por
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
    modo              = p_modo,
    modo_desde        = CASE WHEN modo IS DISTINCT FROM p_modo OR modo_desde IS NULL
                             THEN v_ahora ELSE modo_desde END,
    pin               = CASE WHEN modo IS DISTINCT FROM p_modo THEN NULL ELSE pin END,
    pin_expira_en     = CASE WHEN modo IS DISTINCT FROM p_modo THEN NULL ELSE pin_expira_en END,
    modo_hasta        = v_hasta,
    modo_activado_por = p_validador_id
  WHERE id = p_sesion_id;

  RETURN v_hasta;
END;
$$;

-- 2.2 Cerrar el modo o la sesión también limpia modo_activado_por
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
      modo = NULL, modo_desde = NULL, modo_hasta = NULL,
      modo_activado_por = NULL
  WHERE id = p_sesion_id;
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
      modo = NULL, modo_desde = NULL, modo_hasta = NULL,
      modo_activado_por = NULL
  WHERE id = p_sesion_id;
END;
$$;

-- 2.3 Marcaje: se atribuye al validador que activó el modo
--     (si no hay dato, al que abrió la sesión, como antes)
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
        validado_por      = COALESCE(p_sesion.modo_activado_por, p_sesion.validador_id),
        sesion_id         = p_sesion.id
    WHERE usuario_id = auth.uid() AND evento_id = p_sesion.evento_id;
  END IF;
END;
$$;

-- 3. DESHABILITAR / VENCER UN VALIDADOR --------------------------
--    La sesión del evento solo se cierra si no queda ningún otro
--    validador activo y vigente de ese evento.

-- 3.1 desactivar_validador (antes en 08)
CREATE OR REPLACE FUNCTION public.desactivar_validador(p_usuario_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_evento_id UUID;
BEGIN
  IF COALESCE(rol_actual(), '') NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Solo un administrador puede desactivar validadores';
  END IF;

  UPDATE usuarios SET activo = FALSE
  WHERE id = p_usuario_id AND rol = 'validador' AND activo
  RETURNING evento_asignado_id INTO v_evento_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El validador no existe o ya está desactivado';
  END IF;

  UPDATE sesiones_asistencia
  SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL,
      modo = NULL, modo_desde = NULL, modo_hasta = NULL,
      modo_activado_por = NULL
  WHERE evento_id = v_evento_id
    AND abierta
    AND NOT EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.rol = 'validador' AND u.activo
        AND u.vigente_hasta > NOW()
        AND u.evento_asignado_id = v_evento_id
    );
END;
$$;

-- 3.2 expirar_validadores (antes en 03; lo ejecuta pg_cron cada 5 min)
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

  -- 2. Cerrar las sesiones abiertas de eventos que ya no tienen
  --    ningún validador activo y vigente (invalida QR y PIN)
  UPDATE sesiones_asistencia s
  SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL,
      modo = NULL, modo_desde = NULL, modo_hasta = NULL,
      modo_activado_por = NULL
  WHERE s.abierta
    AND NOT EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.rol = 'validador' AND u.activo
        AND u.vigente_hasta > NOW()
        AND u.evento_asignado_id = s.evento_id
    );

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

-- 4. PERMISOS --------------------------------------------------
REVOKE EXECUTE ON FUNCTION
  public._limitar_validadores_por_evento(),
  public._registrar_marcaje(sesiones_asistencia, TEXT),
  public.activar_modo_asistencia(UUID, UUID, TEXT),
  public.expirar_validadores()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.activar_modo_asistencia(UUID, UUID, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION
  public.cerrar_modo_asistencia(UUID),
  public.cerrar_sesion_asistencia(UUID),
  public.desactivar_validador(UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.cerrar_modo_asistencia(UUID),
  public.cerrar_sesion_asistencia(UUID),
  public.desactivar_validador(UUID)
TO authenticated;

COMMIT;