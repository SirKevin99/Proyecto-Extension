import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';

// ---------------------------------------------------------------
// Modelos ligeros de este módulo (solo lo que la UI necesita).
// Los modelos completos de dominio (Usuario, Evento, Inscripcion)
// se centralizan en shared/modelos cuando lleguemos a ese punto.
// ---------------------------------------------------------------

class ProgresoEstudiante {
  final String nombreCompleto;
  final String carrera;
  final int horasCompletadas;
  final int horasRequeridas;
  final int eventosInscriptos;
  final int eventosPendientesAsistencia;

  const ProgresoEstudiante({
    required this.nombreCompleto,
    required this.carrera,
    required this.horasCompletadas,
    required this.horasRequeridas,
    required this.eventosInscriptos,
    required this.eventosPendientesAsistencia,
  });

  double get porcentaje =>
      horasRequeridas == 0 ? 0 : (horasCompletadas / horasRequeridas).clamp(0, 1);

  int get horasFaltantes =>
      (horasRequeridas - horasCompletadas).clamp(0, horasRequeridas);
}

class MetricasDocente {
  final String nombreCompleto;
  final int eventosActivos;
  final int totalInscriptos;
  final int pendientesValidacion;
  final List<EventoResumen> proximosEventos;

  const MetricasDocente({
    required this.nombreCompleto,
    required this.eventosActivos,
    required this.totalInscriptos,
    required this.pendientesValidacion,
    required this.proximosEventos,
  });
}

class EventoResumen {
  final String id;
  final String nombre;
  final DateTime fecha;
  final int inscriptos;
  final int cuposMaximos;

  const EventoResumen({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.inscriptos,
    required this.cuposMaximos,
  });
}

// ---------------------------------------------------------------
// Provider: progreso del estudiante autenticado
// ---------------------------------------------------------------

final progresoEstudianteProvider =
    FutureProvider.autoDispose<ProgresoEstudiante>((ref) async {
  final userId = supabase.auth.currentUser!.id;

  final perfil = await supabase
      .from('usuarios')
      .select('nombre_completo, carrera, horas_requeridas')
      .eq('id', userId)
      .single();

  // Traemos las inscripciones del alumno con las horas otorgadas
  // por cada evento, para sumar solo las de asistencia confirmada.
  final inscripciones = await supabase
      .from('inscripciones')
      .select('asistencia_confirmada, eventos(horas_otorgadas)')
      .eq('usuario_id', userId);

  int horasCompletadas = 0;
  int pendientes = 0;

  for (final fila in inscripciones as List) {
    final confirmada = fila['asistencia_confirmada'] as bool? ?? false;
    final evento = fila['eventos'] as Map<String, dynamic>?;
    final horas = evento?['horas_otorgadas'] as int? ?? 0;

    if (confirmada) {
      horasCompletadas += horas;
    } else {
      pendientes += 1;
    }
  }

  return ProgresoEstudiante(
    nombreCompleto: perfil['nombre_completo'] as String,
    carrera: perfil['carrera'] as String,
    horasCompletadas: horasCompletadas,
    horasRequeridas: perfil['horas_requeridas'] as int? ?? 120,
    eventosInscriptos: (inscripciones).length,
    eventosPendientesAsistencia: pendientes,
  );
});

// ---------------------------------------------------------------
// Provider: métricas del docente autenticado
// ---------------------------------------------------------------

final metricasDocenteProvider =
    FutureProvider.autoDispose<MetricasDocente>((ref) async {
  final userId = supabase.auth.currentUser!.id;

  final perfil = await supabase
      .from('usuarios')
      .select('nombre_completo')
      .eq('id', userId)
      .single();

  final eventos = await supabase
      .from('eventos')
      .select(
        'id, nombre, fecha, cupos_maximos, cupos_disponibles, activo, inscripciones(id, asistencia_confirmada)',
      )
      .eq('creado_por', userId)
      .order('fecha');

  int eventosActivos = 0;
  int totalInscriptos = 0;
  int pendientesValidacion = 0;
  final proximos = <EventoResumen>[];

  final hoy = DateTime.now();
  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

  for (final fila in eventos as List) {
    final activo = fila['activo'] as bool? ?? false;
    final inscripcionesEvento =
        (fila['inscripciones'] as List?) ?? const [];

    if (activo) eventosActivos += 1;
    totalInscriptos += inscripcionesEvento.length;
    pendientesValidacion += inscripcionesEvento
        .where((i) => (i['asistencia_confirmada'] as bool? ?? false) == false)
        .length;

    final fechaEvento = DateTime.parse(fila['fecha'] as String);
    if (!fechaEvento.isBefore(hoySinHora)) {
      proximos.add(EventoResumen(
        id: fila['id'] as String,
        nombre: fila['nombre'] as String,
        fecha: fechaEvento,
        inscriptos: inscripcionesEvento.length,
        cuposMaximos: fila['cupos_maximos'] as int,
      ));
    }
  }

  proximos.sort((a, b) => a.fecha.compareTo(b.fecha));

  return MetricasDocente(
    nombreCompleto: perfil['nombre_completo'] as String,
    eventosActivos: eventosActivos,
    totalInscriptos: totalInscriptos,
    pendientesValidacion: pendientesValidacion,
    proximosEventos: proximos.take(5).toList(),
  );
});