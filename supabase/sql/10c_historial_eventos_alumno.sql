-- 10c_historial_eventos_alumno.sql
-- COMPLEMENTO de 10_asistencia_entrada_salida.sql (ejecutar DESPUÉS de ese).
-- NO ejecutar todavía: solo se prepara.
--
-- Historial de eventos del alumno autenticado. Los eventos finalizados y
-- cancelados no son visibles para el alumno por RLS, así que el historial se
-- sirve por esta función, que solo devuelve SUS inscripciones.

CREATE OR REPLACE FUNCTION public.mis_eventos_historial()
RETURNS TABLE (
  evento_id       UUID,
  nombre          TEXT,
  fecha           DATE,
  hora_inicio     TIME,
  hora_fin        TIME,
  ubicacion       TEXT,
  horas_otorgadas INT,
  estado          TEXT,
  entrada_en      TIMESTAMPTZ,
  salida_en       TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  IF COALESCE(rol_actual(), '') <> 'alumno' THEN
    RAISE EXCEPTION 'Solo los alumnos tienen historial de eventos';
  END IF;

  RETURN QUERY
  SELECT e.id,
         e.nombre::TEXT,
         e.fecha::DATE,
         e.hora_inicio::TIME,
         e.hora_fin::TIME,
         e.ubicacion::TEXT,
         e.horas_otorgadas::INT,
         e.estado::TEXT,
         i.entrada_en,
         i.salida_en
  FROM inscripciones i
  JOIN eventos e ON e.id = i.evento_id
  WHERE i.usuario_id = auth.uid()
  ORDER BY e.fecha DESC, e.hora_inicio DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mis_eventos_historial() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mis_eventos_historial() TO authenticated;