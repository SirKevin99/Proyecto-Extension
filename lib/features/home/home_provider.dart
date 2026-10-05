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

// ---------------------------------------------------------------
// Panel de administración
// ---------------------------------------------------------------

class EventoResumen {
  final String id;
  final String nombre;
  final DateTime fecha;
  final int inscriptos;
  final int cuposMaximos;
  final int pendientes;

  const EventoResumen({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.inscriptos,
    required this.cuposMaximos,
    required this.pendientes,
  });
}

class MetricasAdmin {
  final String nombreCompleto;
  final int eventosActivos;
  final int totalInscriptos;
  final int pendientesValidacion;
  final int validadoresActivos;
  final List<EventoResumen> proximosEventos;
  final List<EventoResumen> eventosPorRevisar;

  const MetricasAdmin({
    required this.nombreCompleto,
    required this.eventosActivos,
    required this.totalInscriptos,
    required this.pendientesValidacion,
    required this.validadoresActivos,
    required this.proximosEventos,
    required this.eventosPorRevisar,
  });
}

final metricasAdminProvider =
    FutureProvider.autoDispose<MetricasAdmin>((ref) async {
  final userId = supabase.auth.currentUser!.id;

  final perfil = await supabase
      .from('usuarios')
      .select('nombre_completo')
      .eq('id', userId)
      .single();

  // RLS: el admin ve todos los eventos e inscripciones.
  final eventos = await supabase
      .from('eventos')
      .select(
        'id, nombre, fecha, cupos_maximos, activo, '
        'inscripciones(id, asistencia_confirmada)',
      )
      .order('fecha');

  final validadores = await supabase
      .from('usuarios')
      .select('id')
      .eq('rol', 'validador')
      .eq('activo', true)
      .gt('vigente_hasta', DateTime.now().toUtc().toIso8601String());

  final hoy = DateTime.now();
  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

  int eventosActivos = 0;
  int totalInscriptos = 0;
  int pendientesValidacion = 0;
  final proximos = <EventoResumen>[];
  final porRevisar = <EventoResumen>[];

  for (final fila in eventos as List) {
    final activo = fila['activo'] as bool? ?? false;
    final inscripciones = (fila['inscripciones'] as List?) ?? const [];
    final pendientes = inscripciones
        .where((i) => (i['asistencia_confirmada'] as bool? ?? false) == false)
        .length;
    final fecha = DateTime.parse(fila['fecha'] as String);
    final yaOcurrio = fecha.isBefore(hoySinHora);

    final resumen = EventoResumen(
      id: fila['id'] as String,
      nombre: fila['nombre'] as String,
      fecha: fecha,
      inscriptos: inscripciones.length,
      cuposMaximos: fila['cupos_maximos'] as int,
      pendientes: pendientes,
    );

    if (activo) eventosActivos += 1;
    totalInscriptos += inscripciones.length;

    if (yaOcurrio) {
      // Solo los eventos ya realizados tienen "pendientes" con sentido.
      pendientesValidacion += pendientes;
      if (pendientes > 0) porRevisar.add(resumen);
    } else if (activo) {
      proximos.add(resumen);
    }
  }

  proximos.sort((a, b) => a.fecha.compareTo(b.fecha));
  porRevisar.sort((a, b) => b.fecha.compareTo(a.fecha)); // más reciente primero

  return MetricasAdmin(
    nombreCompleto: perfil['nombre_completo'] as String,
    eventosActivos: eventosActivos,
    totalInscriptos: totalInscriptos,
    pendientesValidacion: pendientesValidacion,
    validadoresActivos: (validadores as List).length,
    proximosEventos: proximos.take(5).toList(),
    eventosPorRevisar: porRevisar.take(5).toList(),
  );
});

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
    eventosInscriptos: inscripciones.length,
    eventosPendientesAsistencia: pendientes,
  );
});