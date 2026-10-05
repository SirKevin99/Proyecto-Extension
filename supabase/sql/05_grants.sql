-- Acceso al schema
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Tablas: RLS decide qué filas; el GRANT solo habilita la operación.
GRANT SELECT, INSERT, UPDATE ON public.usuarios TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.eventos TO authenticated;

-- inscripciones: solo lectura. Toda escritura pasa por RPC SECURITY DEFINER.
GRANT SELECT ON public.inscripciones TO authenticated;

-- sesiones_asistencia e intentos_pin quedan SIN acceso directo (a propósito).

-- Funciones que el cliente llama o que usan las policies
GRANT EXECUTE ON FUNCTION
  public.rol_actual(),
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
  public.inscribirse_a_evento(UUID)
TO authenticated;

-- La vista del login (ya la tenías, se repite por seguridad)
GRANT SELECT ON public.vista_resolucion_ci TO anon, authenticated;