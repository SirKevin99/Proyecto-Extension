-- =========================================================
-- 1. ROLES: se elimina 'docente', se agrega 'validador'
-- =========================================================
UPDATE usuarios SET rol = 'admin' WHERE rol = 'docente';

ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS usuarios_rol_check;
ALTER TABLE usuarios
  ADD CONSTRAINT usuarios_rol_check
  CHECK (rol IN ('alumno', 'admin', 'validador'));

-- Campos del perfil temporal (solo se usan si rol = 'validador')
ALTER TABLE usuarios
  ADD COLUMN IF NOT EXISTS evento_asignado_id UUID
    REFERENCES eventos(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS vigente_hasta TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS activo BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE usuarios
  ADD CONSTRAINT usuarios_validador_chk
  CHECK (
    rol <> 'validador'
    OR (evento_asignado_id IS NOT NULL AND vigente_hasta IS NOT NULL)
  );

-- =========================================================
-- 2. SESIONES DE ASISTENCIA (secreto del QR y PIN)
--    Sin policies: solo accesible vía RPC SECURITY DEFINER.
-- =========================================================
CREATE TABLE sesiones_asistencia (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  evento_id UUID NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
  validador_id UUID NOT NULL REFERENCES usuarios(id),
  secreto TEXT NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
  pin TEXT,
  pin_expira_en TIMESTAMPTZ,
  abierta BOOLEAN NOT NULL DEFAULT TRUE,
  abierta_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cerrada_en TIMESTAMPTZ
);

CREATE INDEX idx_sesiones_evento ON sesiones_asistencia (evento_id);

ALTER TABLE sesiones_asistencia ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sesiones_asistencia FROM anon, authenticated;

-- Límite de intentos de PIN por alumno y sesión
CREATE TABLE intentos_pin (
  sesion_id UUID REFERENCES sesiones_asistencia(id) ON DELETE CASCADE,
  usuario_id UUID REFERENCES usuarios(id) ON DELETE CASCADE,
  intentos INT NOT NULL DEFAULT 0,
  PRIMARY KEY (sesion_id, usuario_id)
);

ALTER TABLE intentos_pin ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON intentos_pin FROM anon, authenticated;

-- =========================================================
-- 3. INSCRIPCIONES: método y trazabilidad del marcaje
-- =========================================================
ALTER TABLE inscripciones
  ADD COLUMN IF NOT EXISTS metodo_validacion TEXT
    CHECK (metodo_validacion IN ('qr', 'pin', 'manual')),
  ADD COLUMN IF NOT EXISTS fecha_marcaje TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sesion_id UUID
    REFERENCES sesiones_asistencia(id);

-- =========================================================
-- 4. FUNCIÓN AUXILIAR (evita recursión infinita en RLS)
-- =========================================================
CREATE OR REPLACE FUNCTION public.rol_actual()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT rol FROM usuarios WHERE id = auth.uid();
$$;

-- =========================================================
-- 5. RLS: reemplazo de policies que mencionaban 'docente'
-- =========================================================

-- usuarios
DROP POLICY IF EXISTS "usuarios_select_docente_admin" ON usuarios;
DROP POLICY IF EXISTS "usuarios_update_solo_admin" ON usuarios;
DROP POLICY IF EXISTS "usuarios_insert_solo_admin" ON usuarios;
DROP POLICY IF EXISTS "usuarios_insert_propio_alumno" ON usuarios;

CREATE POLICY "usuarios_select_admin" ON usuarios
  FOR SELECT TO authenticated USING (rol_actual() = 'admin');

CREATE POLICY "usuarios_insert_admin" ON usuarios
  FOR INSERT TO authenticated WITH CHECK (rol_actual() = 'admin');

CREATE POLICY "usuarios_update_admin" ON usuarios
  FOR UPDATE TO authenticated USING (rol_actual() = 'admin');

-- eventos
DROP POLICY IF EXISTS "eventos_select_propio_docente" ON eventos;
DROP POLICY IF EXISTS "eventos_insert_docente" ON eventos;

CREATE POLICY "eventos_select_admin" ON eventos
  FOR SELECT TO authenticated USING (rol_actual() = 'admin');

CREATE POLICY "eventos_insert_admin" ON eventos
  FOR INSERT TO authenticated
  WITH CHECK (rol_actual() = 'admin' AND creado_por = auth.uid());

CREATE POLICY "eventos_update_admin" ON eventos
  FOR UPDATE TO authenticated USING (rol_actual() = 'admin');

-- inscripciones (alumno solo lee las suyas; NO hay UPDATE directo:
-- todo marcaje/corrección pasa por RPC)
DROP POLICY IF EXISTS "inscripciones_select_docente" ON inscripciones;

CREATE POLICY "inscripciones_select_admin" ON inscripciones
  FOR SELECT TO authenticated USING (rol_actual() = 'admin');

-- =========================================================
-- 6. Login: un validador vencido o inactivo no resuelve correo
-- =========================================================
CREATE OR REPLACE VIEW vista_resolucion_ci
WITH (security_invoker = false) AS
SELECT ci, correo_institucional, rol
FROM usuarios
WHERE activo = TRUE
  AND (vigente_hasta IS NULL OR vigente_hasta > NOW());