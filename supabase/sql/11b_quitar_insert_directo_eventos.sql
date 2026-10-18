-- =========================================================
-- 11b_quitar_insert_directo_eventos.sql
-- Cierre de la fase 4G (complemento del script 11).
--
-- Desde el ajuste 0 la app crea eventos con la RPC crear_evento
-- (evento + carreras en una transacción). La policy que permitía
-- el INSERT directo sobre eventos ya no se usa y permitiría crear
-- eventos SIN carreras, saltando la regla "mínimo una carrera".
--
-- Ejecutar SOLO cuando todo el equipo tenga develop actualizado
-- (una app vieja dejaría de poder crear eventos).
-- NO EJECUTAR sin autorización.
-- =========================================================

BEGIN;

DROP POLICY IF EXISTS "eventos_insert_admin" ON public.eventos;

-- Verificación: no debe quedar ninguna policy que permita INSERT
-- sobre eventos (ni explícita ni por ALL). Si queda, se revierte todo.
DO $$
DECLARE
  v_restantes TEXT;
BEGIN
  SELECT string_agg(policyname, ', ')
  INTO v_restantes
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'eventos'
    AND cmd IN ('INSERT', 'ALL');

  IF v_restantes IS NOT NULL THEN
    RAISE EXCEPTION 'Quedan policies que permiten INSERT en eventos: %', v_restantes;
  END IF;
END;
$$;

COMMIT;