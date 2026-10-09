-- service_role (la usa solo la Edge Function) salta RLS,
-- pero necesita permisos de tabla.
GRANT USAGE ON SCHEMA public TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.usuarios TO service_role;
GRANT SELECT ON public.eventos TO service_role;
GRANT SELECT ON public.inscripciones TO service_role;