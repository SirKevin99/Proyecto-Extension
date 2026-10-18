-- =========================================================
-- 12_restablecer_clave_validador.sql
-- Ajuste 3 (fase 4G): el admin restablece la clave de un validador.
--
-- - Tabla auditoria_validadores: quién restableció la clave,
--   de qué validador y cuándo. Solo la escribe la Edge Function
--   restablecer-clave-validador (service_role); el admin solo lee.
-- - listar_validadores() ahora devuelve también el código VAL-####
--   (columna ci), necesario para entregarlo junto con la clave nueva.
--   Cambia el tipo de retorno, por eso se hace DROP + CREATE.
--
-- Todo en una transacción. NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

-- 1. AUDITORÍA -----------------------------------------------
CREATE TABLE IF NOT EXISTS public.auditoria_validadores (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  validador_id   UUID NOT NULL REFERENCES public.usuarios(id),
  evento_id      UUID REFERENCES public.eventos(id) ON DELETE SET NULL,
  accion         TEXT NOT NULL CHECK (accion IN ('restablecer_clave')),
  realizado_por  UUID NOT NULL REFERENCES public.usuarios(id),
  realizado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auditoria_validadores_validador
  ON public.auditoria_validadores (validador_id, realizado_en DESC);

ALTER TABLE public.auditoria_validadores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auditoria_validadores_select_admin"
  ON public.auditoria_validadores;
CREATE POLICY "auditoria_validadores_select_admin"
  ON public.auditoria_validadores
  FOR SELECT TO authenticated
  USING (COALESCE(rol_actual(), '') IN ('admin', 'superadmin'));

REVOKE ALL ON public.auditoria_validadores FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.auditoria_validadores TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.auditoria_validadores TO service_role;

-- 2. LISTA DE VALIDADORES (agrega el código) -----------------
DROP FUNCTION IF EXISTS public.listar_validadores();

CREATE FUNCTION public.listar_validadores()
RETURNS TABLE (
  id              UUID,
  codigo          TEXT,
  nombre_completo TEXT,
  evento_id       UUID,
  evento_nombre   TEXT,
  evento_fecha    DATE,
  vigente_hasta   TIMESTAMPTZ
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
         u.ci::TEXT,
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

COMMIT;