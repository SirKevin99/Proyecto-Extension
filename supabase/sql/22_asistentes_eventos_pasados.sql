-- =========================================================
-- 22_asistentes_eventos_pasados.sql
-- Fase 8, paso 8.3: asistentes de los eventos cargados como pasados
-- (solo superadmin).
--
-- Decisiones (Pedro, 20/10, con autorización de Kevin; recomendaciones
-- del asistente aceptadas; ESTADO_PROYECTO.md, sección 13):
-- - Solo en eventos con carga_historica = TRUE (script 21).
-- - Los asistentes se cargan sin horas: entrada = hora de inicio y salida
--   = hora de fin del evento, método "manual". Suman horas y reciben
--   certificado (con la carrera y los firmantes de hoy).
-- - Se eligen de la lista o con el CSV de la fase 6. Los alumnos nuevos
--   del CSV los crea antes la Edge Function alta-masiva-alumnos (sin
--   cambios); esta función solo recibe ids de alumnos existentes.
-- - Vale la carrera REGISTRADA del alumno: debe estar habilitada en el
--   evento. La cuenta debe estar activa y ser de un alumno.
-- - Si la carga supera el cupo, se rechaza completa.
-- - Hasta 300 alumnos por carga. Motivo obligatorio (10+ caracteres),
--   registrado en la auditoría (contexto carga_asistentes_pasado).
-- - Un alumno ya inscripto sin asistencia completa (por ejemplo, porque se
--   le revocó) se completa con la hora de inicio y la de fin; queda en
--   correcciones_asistencia con el motivo.
-- - corregir_asistencia (10): en los eventos cargados como pasados,
--   "registrar" usa la hora de inicio y la de fin en lugar de la hora
--   actual. En los demás eventos no cambia nada.
--
-- Requiere: 10, 11, 16 (_es_superadmin), 17, 20 y 21.
-- Todo en una transacción. NO EJECUTAR sin autorización de Kevin.
-- =========================================================

BEGIN;

-- 1. AUDITORÍA: contexto nuevo ---------------------------------------
ALTER TABLE public.auditoria_cambios
  DROP CONSTRAINT IF EXISTS auditoria_cambios_contexto_check;
ALTER TABLE public.auditoria_cambios
  ADD CONSTRAINT auditoria_cambios_contexto_check
  CHECK (contexto IS NULL
         OR contexto IN ('carga_evento_pasado',
                         'edicion_evento_pasado',
                         'reactivacion_evento',
                         'carga_asistentes_pasado'));

-- 2. AYUDANTE: evento cargado como pasado, bloqueado -------------------
CREATE OR REPLACE FUNCTION public._evento_pasado_para_asistentes(p_evento_id UUID)
RETURNS public.eventos
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ev eventos%ROWTYPE;
BEGIN
  SELECT * INTO v_ev FROM eventos WHERE id = p_evento_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El evento no existe';
  END IF;
  IF NOT v_ev.carga_historica THEN
    RAISE EXCEPTION 'Solo se cargan asistentes en los eventos cargados como pasados';
  END IF;
  IF v_ev.estado <> 'finalizado' THEN
    RAISE EXCEPTION 'El evento no está finalizado';
  END IF;
  RETURN v_ev;
END;
$$;

-- 3. DATOS DEL EVENTO PARA LA PANTALLA --------------------------------
-- Nombre, fecha, horario, cupo, asistentes y carreras habilitadas
-- (también las desactivadas, que la app no conoce por nombre).
CREATE OR REPLACE FUNCTION public.resumen_evento_pasado(p_evento_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev eventos%ROWTYPE;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede cargar asistentes de eventos pasados';
  END IF;

  SELECT * INTO v_ev FROM eventos WHERE id = p_evento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El evento no existe';
  END IF;
  IF NOT v_ev.carga_historica THEN
    RAISE EXCEPTION 'Solo se cargan asistentes en los eventos cargados como pasados';
  END IF;

  RETURN jsonb_build_object(
    'evento_id',         v_ev.id,
    'nombre',            v_ev.nombre,
    'fecha',             v_ev.fecha,
    'hora_inicio',       to_char(v_ev.hora_inicio, 'HH24:MI'),
    'hora_fin',          to_char(v_ev.hora_fin, 'HH24:MI'),
    'horas_otorgadas',   v_ev.horas_otorgadas,
    'estado',            v_ev.estado,
    'cupos_maximos',     v_ev.cupos_maximos,
    'cupos_disponibles', v_ev.cupos_disponibles,
    'inscriptos', (SELECT COUNT(*) FROM inscripciones WHERE evento_id = v_ev.id),
    'asistentes_completos', (
      SELECT COUNT(*) FROM inscripciones
      WHERE evento_id = v_ev.id
        AND entrada_en IS NOT NULL AND salida_en IS NOT NULL),
    'carreras', (
      SELECT COALESCE(jsonb_agg(c.nombre ORDER BY c.nombre), '[]'::JSONB)
      FROM evento_carreras ec JOIN carreras c ON c.id = ec.carrera_id
      WHERE ec.evento_id = v_ev.id)
  );
END;
$$;

-- 4. ALUMNOS QUE SE PUEDEN CARGAR (lista con búsqueda) ------------------
-- Alumnos activos de las carreras habilitadas, sin asistencia completa en
-- el evento. "inscripto" = ya está inscripto (se completará).
-- Búsqueda por nombre (sin distinguir mayúsculas) o por inicio de la C.I.
-- Hasta 200 resultados.
CREATE OR REPLACE FUNCTION public.alumnos_para_evento_pasado(
  p_evento_id UUID,
  p_busqueda  TEXT DEFAULT NULL,
  p_limite    INT  DEFAULT 200
)
RETURNS TABLE (
  usuario_id      UUID,
  nombre_completo TEXT,
  ci              TEXT,
  carrera         TEXT,
  inscripto       BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_q      TEXT := NULLIF(_texto_limpio(p_busqueda), '');
  v_limite INT  := LEAST(GREATEST(COALESCE(p_limite, 200), 1), 200);
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede cargar asistentes de eventos pasados';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM eventos
                 WHERE id = p_evento_id AND carga_historica) THEN
    RAISE EXCEPTION 'Solo se cargan asistentes en los eventos cargados como pasados';
  END IF;

  RETURN QUERY
  SELECT u.id,
         u.nombre_completo::TEXT,
         u.ci::TEXT,
         u.carrera::TEXT,
         (i.id IS NOT NULL)
  FROM usuarios u
  JOIN carreras c ON c.nombre = u.carrera
  JOIN evento_carreras ec ON ec.carrera_id = c.id AND ec.evento_id = p_evento_id
  LEFT JOIN inscripciones i ON i.usuario_id = u.id AND i.evento_id = p_evento_id
  WHERE u.rol = 'alumno'
    AND u.activo
    AND NOT (i.entrada_en IS NOT NULL AND i.salida_en IS NOT NULL)
    AND (v_q IS NULL
         OR u.nombre_completo ILIKE '%' || v_q || '%'
         OR u.ci LIKE v_q || '%')
  ORDER BY u.nombre_completo
  LIMIT v_limite;
END;
$$;

-- 5. CARGAR ASISTENTES ------------------------------------------------
-- p_usuario_ids: alumnos existentes (los nuevos del CSV se crean antes).
-- Devuelve una fila por alumno pedido:
--   agregado   = inscripción nueva con entrada y salida
--   completado = ya estaba inscripto sin asistencia completa
--   ya_estaba  = ya tenía la asistencia completa (no cambia nada)
--   rechazado  = no se cargó (detalle con el motivo)
-- Si los agregados superan el cupo, se rechaza toda la carga.
CREATE OR REPLACE FUNCTION public.cargar_asistentes_evento_pasado(
  p_evento_id   UUID,
  p_usuario_ids UUID[],
  p_motivo      TEXT
)
RETURNS TABLE (
  usuario_id UUID,
  resultado  TEXT,
  detalle    TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_ev        eventos%ROWTYPE;
  v_motivo    TEXT;
  v_ids       UUID[];
  v_entrada   TIMESTAMPTZ;
  v_salida    TIMESTAMPTZ;
  v_nuevos    INT := 0;
  v_id        UUID;
  v_u         usuarios%ROWTYPE;
  v_i         inscripciones%ROWTYPE;
  v_res       TEXT;
  v_det       TEXT;
  -- Resultado por alumno (mismo orden en los cuatro arreglos)
  a_usuario   UUID[] := '{}';
  a_resultado TEXT[] := '{}';
  a_detalle   TEXT[] := '{}';
  a_insc      UUID[] := '{}';
  k           INT;
BEGIN
  IF NOT _es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin puede cargar asistentes de eventos pasados';
  END IF;

  v_ev := _evento_pasado_para_asistentes(p_evento_id);
  v_motivo := _motivo_valido(p_motivo);

  SELECT COALESCE(array_agg(DISTINCT x), '{}')
  INTO v_ids
  FROM unnest(COALESCE(p_usuario_ids, '{}')) AS x
  WHERE x IS NOT NULL;

  IF cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION 'Elegí al menos un alumno';
  END IF;
  IF cardinality(v_ids) > 300 THEN
    RAISE EXCEPTION 'Se pueden cargar hasta 300 asistentes por vez';
  END IF;

  v_entrada := _hora_local(v_ev.fecha, v_ev.hora_inicio);
  v_salida  := _hora_local(v_ev.fecha, v_ev.hora_fin);

  -- 1) Clasificación de cada alumno pedido (sin escribir nada).
  FOREACH v_id IN ARRAY v_ids LOOP
    v_det := NULL;
    SELECT * INTO v_u FROM usuarios WHERE id = v_id;
    IF NOT FOUND THEN
      v_res := 'rechazado';  v_det := 'El usuario no existe';
      v_i := NULL;
    ELSE
      SELECT * INTO v_i FROM inscripciones
      WHERE usuario_id = v_id AND evento_id = v_ev.id
      FOR UPDATE;
      IF NOT FOUND THEN
        v_i := NULL;
      END IF;

      IF v_u.rol <> 'alumno' THEN
        v_res := 'rechazado';  v_det := 'La cuenta no es de un alumno';
      ELSIF NOT v_u.activo THEN
        v_res := 'rechazado';  v_det := 'La cuenta está desactivada';
      ELSIF v_i.id IS NOT NULL
            AND v_i.entrada_en IS NOT NULL AND v_i.salida_en IS NOT NULL THEN
        v_res := 'ya_estaba';  v_det := 'Ya tenía la asistencia registrada';
      ELSIF NOT EXISTS (
              SELECT 1 FROM evento_carreras ec
              JOIN carreras c ON c.id = ec.carrera_id
              WHERE ec.evento_id = v_ev.id AND c.nombre = v_u.carrera) THEN
        v_res := 'rechazado';
        v_det := format('Su carrera (%s) no está habilitada en este evento', v_u.carrera);
      ELSIF v_i.id IS NOT NULL THEN
        v_res := 'completado';
      ELSE
        v_res := 'agregado';
        v_nuevos := v_nuevos + 1;
      END IF;
    END IF;

    a_usuario   := a_usuario   || v_id;
    a_resultado := a_resultado || v_res;
    a_detalle   := a_detalle   || v_det;
    a_insc      := a_insc      || v_i.id;
  END LOOP;

  IF v_ev.cupos_disponibles IS NOT NULL AND v_nuevos > v_ev.cupos_disponibles THEN
    RAISE EXCEPTION '%', format(
      'Supera el cupo del evento: se quieren agregar %s y %s',
      v_nuevos,
      CASE GREATEST(v_ev.cupos_disponibles, 0)
        WHEN 0 THEN 'no quedan lugares'
        WHEN 1 THEN 'queda 1 lugar'
        ELSE 'quedan ' || v_ev.cupos_disponibles || ' lugares' END);
  END IF;

  -- 2) Escritura (auditada con contexto y motivo).
  PERFORM _fijar_contexto_auditoria('carga_asistentes_pasado', v_motivo);

  FOR k IN 1 .. cardinality(a_usuario) LOOP
    IF a_resultado[k] = 'agregado' THEN
      INSERT INTO inscripciones (
        usuario_id, evento_id, entrada_en, salida_en,
        metodo_entrada, metodo_salida, metodo_validacion,
        fecha_marcaje, fecha_validacion, validado_por
      ) VALUES (
        a_usuario[k], v_ev.id, v_entrada, v_salida,
        'manual', 'manual', 'manual',
        v_salida, NOW(), auth.uid()
      )
      RETURNING id INTO v_id;
      -- Los triggers del 20 no actúan al insertar: se emite acá.
      PERFORM _emitir_certificado(v_id);

    ELSIF a_resultado[k] = 'completado' THEN
      -- Ya inscripto sin asistencia completa: se completa. El trigger del 20
      -- emite o reactiva el certificado. Queda como corrección con motivo.
      SELECT * INTO v_i FROM inscripciones WHERE id = a_insc[k];
      IF v_i.entrada_en IS DISTINCT FROM v_entrada THEN
        INSERT INTO correcciones_asistencia
          (inscripcion_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
        VALUES (v_i.id, 'entrada', v_i.entrada_en, v_entrada, v_motivo, auth.uid());
      END IF;
      IF v_i.salida_en IS DISTINCT FROM v_salida THEN
        INSERT INTO correcciones_asistencia
          (inscripcion_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
        VALUES (v_i.id, 'salida', v_i.salida_en, v_salida, v_motivo, auth.uid());
      END IF;

      UPDATE inscripciones SET
        entrada_en        = v_entrada,
        salida_en         = v_salida,
        metodo_entrada    = 'manual',
        metodo_salida     = 'manual',
        metodo_validacion = 'manual',
        fecha_marcaje     = v_salida,
        fecha_validacion  = NOW(),
        validado_por      = auth.uid()
      WHERE id = v_i.id;
    END IF;
  END LOOP;

  IF v_nuevos > 0 AND v_ev.cupos_disponibles IS NOT NULL THEN
    UPDATE eventos SET cupos_disponibles = cupos_disponibles - v_nuevos
    WHERE id = v_ev.id;
  END IF;

  PERFORM _fijar_contexto_auditoria(NULL, NULL);

  RETURN QUERY
  SELECT a_usuario[g.n], a_resultado[g.n], a_detalle[g.n]
  FROM generate_subscripts(a_usuario, 1) AS g(n)
  ORDER BY g.n;
END;
$$;

-- 6. corregir_asistencia (10): hora del evento en eventos pasados --------
-- Igual que en el 10, salvo que en los eventos con carga_historica
-- "registrar" usa la hora de inicio (entrada) y la de fin (salida) en
-- lugar de la hora actual.
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
  v_ev    eventos%ROWTYPE;
  v_ent   TIMESTAMPTZ;
  v_sal   TIMESTAMPTZ;
  v_m_ent TEXT;
  v_m_sal TEXT;
  v_ahora TIMESTAMPTZ := NOW();
  v_h_ent TIMESTAMPTZ;   -- hora a registrar como entrada
  v_h_sal TIMESTAMPTZ;   -- hora a registrar como salida
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

  -- Bloquear primero los eventos asociados, en orden estable.
  PERFORM e.id
  FROM eventos e
  WHERE e.id IN (
    SELECT DISTINCT i.evento_id
    FROM inscripciones i
    WHERE i.id = ANY(p_inscripcion_ids)
  )
  ORDER BY e.id
  FOR UPDATE;

  FOR r IN
    SELECT *
    FROM inscripciones
    WHERE id = ANY(p_inscripcion_ids)
    ORDER BY id
    FOR UPDATE
  LOOP
    SELECT * INTO v_ev FROM eventos WHERE id = r.evento_id;

    -- Impedir correcciones en eventos cancelados.
    IF v_ev.estado = 'cancelado' THEN
      RAISE EXCEPTION
        'No se pueden corregir asistencias de eventos cancelados';
    END IF;

    -- Nuevo (22): en los eventos cargados como pasados se usa el horario
    -- del evento.
    IF v_ev.carga_historica THEN
      v_h_ent := _hora_local(v_ev.fecha, v_ev.hora_inicio);
      v_h_sal := _hora_local(v_ev.fecha, v_ev.hora_fin);
    ELSE
      v_h_ent := v_ahora;
      v_h_sal := v_ahora;
    END IF;

    v_ent := r.entrada_en;
    v_sal := r.salida_en;

    IF p_registrar THEN
      IF p_campo IN ('entrada', 'ambos') AND v_ent IS NULL THEN
        v_ent := v_h_ent;
      END IF;
      IF p_campo IN ('salida', 'ambos') AND v_sal IS NULL THEN
        IF v_ent IS NULL THEN
          RAISE EXCEPTION 'Hay alumnos sin entrada registrada: registrá primero la entrada';
        END IF;
        -- En un evento pasado la entrada pudo registrarse antes con la hora
        -- de la corrección: la salida nunca queda antes de la entrada.
        v_sal := CASE WHEN v_ev.carga_historica THEN GREATEST(v_h_sal, v_ent)
                      ELSE v_h_sal END;
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

-- 7. PERMISOS ---------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public._evento_pasado_para_asistentes(UUID)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION
  public.resumen_evento_pasado(UUID),
  public.alumnos_para_evento_pasado(UUID, TEXT, INT),
  public.cargar_asistentes_evento_pasado(UUID, UUID[], TEXT),
  public.corregir_asistencia(UUID[], TEXT, BOOLEAN, TEXT)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.resumen_evento_pasado(UUID),
  public.alumnos_para_evento_pasado(UUID, TEXT, INT),
  public.cargar_asistentes_evento_pasado(UUID, UUID[], TEXT),
  public.corregir_asistencia(UUID[], TEXT, BOOLEAN, TEXT)
TO authenticated;

-- 8. VERIFICACIÓN FINAL (si falla, se revierte todo) ---------------------
DO $$
BEGIN
  IF to_regprocedure('public._fijar_contexto_auditoria(text, text)') IS NULL
     OR to_regprocedure('public._motivo_valido(text)') IS NULL THEN
    RAISE EXCEPTION 'Faltan funciones del script 21: ejecutalo antes';
  END IF;
  IF to_regprocedure('public._emitir_certificado(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Falta _emitir_certificado (script 20)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'auditoria_cambios_contexto_check'
      AND pg_get_constraintdef(oid) LIKE '%carga_asistentes_pasado%'
  ) THEN
    RAISE EXCEPTION 'El CHECK de auditoria_cambios.contexto no se actualizó';
  END IF;
END;
$$;

COMMIT;