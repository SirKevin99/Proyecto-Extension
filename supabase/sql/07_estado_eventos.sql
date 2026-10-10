-- =========================================================
-- 07_estado_eventos.sql
-- Estado del evento: vigente | finalizado | cancelado
-- =========================================================

-- 1. Columna de estado, migrando lo existente
ALTER TABLE eventos
  ADD COLUMN IF NOT EXISTS estado TEXT NOT NULL DEFAULT 'vigente'
  CHECK (estado IN ('vigente', 'finalizado', 'cancelado'));

UPDATE eventos SET estado = CASE WHEN activo THEN 'vigente' ELSE 'cancelado' END;

UPDATE eventos SET estado = 'finalizado'
WHERE estado = 'vigente'
  AND fecha < (NOW() AT TIME ZONE 'America/Asuncion')::date;

CREATE INDEX IF NOT EXISTS idx_eventos_estado ON eventos (estado);

-- 2. `activo` se mantiene como columna derivada (activo = vigente).
--    Así siguen funcionando las policies y RPC que ya filtran por `activo`.
CREATE OR REPLACE FUNCTION public._sync_activo_evento()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.activo := (NEW.estado = 'vigente');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_sync_activo ON eventos;
CREATE TRIGGER trg_eventos_sync_activo
  BEFORE INSERT OR UPDATE OF estado ON eventos
  FOR EACH ROW EXECUTE FUNCTION public._sync_activo_evento();

UPDATE eventos SET activo = (estado = 'vigente');

-- 3. Cierre automático: pasadas las 23:59:59 del día del evento
--    (hora de Paraguay). También cierra sesiones de asistencia y
--    desactiva al validador del evento.
CREATE OR REPLACE FUNCTION public.finalizar_eventos_vencidos()
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_finalizados INT;
BEGIN
  WITH fin AS (
    UPDATE eventos SET estado = 'finalizado'
    WHERE estado = 'vigente'
      AND fecha < (NOW() AT TIME ZONE 'America/Asuncion')::date
    RETURNING id
  ),
  cierre AS (
    UPDATE sesiones_asistencia s
    SET abierta = FALSE, cerrada_en = NOW(), pin = NULL, pin_expira_en = NULL
    FROM fin
    WHERE s.evento_id = fin.id AND s.abierta
    RETURNING s.id
  ),
  validadores AS (
    UPDATE usuarios u SET activo = FALSE
    FROM fin
    WHERE u.rol = 'validador' AND u.evento_asignado_id = fin.id AND u.activo
    RETURNING u.id
  )
  SELECT COUNT(*)::INT INTO v_finalizados FROM fin;

  RETURN v_finalizados;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.finalizar_eventos_vencidos()
  FROM PUBLIC, anon, authenticated;

-- Cada minuto, para que el cambio ocurra casi a las 00:00:00
SELECT cron.schedule(
  'finalizar-eventos-vencidos',
  '* * * * *',
  $$SELECT public.finalizar_eventos_vencidos()$$
);

-- 4. Finalizar o cancelar manualmente (admin y superadmin)
CREATE OR REPLACE FUNCTION public._cerrar_evento(p_evento_id UUID, p_estado TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF rol_actual() NOT IN ('admin', 'superadmin') THEN
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

CREATE OR REPLACE FUNCTION public.finalizar_evento(p_evento_id UUID)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$ SELECT public._cerrar_evento(p_evento_id, 'finalizado'); $$;

CREATE OR REPLACE FUNCTION public.cancelar_evento(p_evento_id UUID)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$ SELECT public._cerrar_evento(p_evento_id, 'cancelado'); $$;

REVOKE EXECUTE ON FUNCTION public._cerrar_evento(UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION
  public.finalizar_evento(UUID), public.cancelar_evento(UUID)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.finalizar_evento(UUID), public.cancelar_evento(UUID)
  TO authenticated;