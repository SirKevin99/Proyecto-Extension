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

  double get porcentaje => horasRequeridas == 0
      ? 0
      : (horasCompletadas / horasRequeridas).clamp(0, 1);

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
  final String horaInicio;
  final int inscriptos;
  final int? cuposMaximos;

  const EventoResumen({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.horaInicio,
    required this.inscriptos,
    required this.cuposMaximos,
  });
}

class MetricasAdmin {
  final String nombreCompleto;
  final int eventosVigentes;
  final int totalInscriptos;
  final int validadoresActivos;
  final List<EventoResumen> eventosVigentesLista;

  const MetricasAdmin({
    required this.nombreCompleto,
    required this.eventosVigentes,
    required this.totalInscriptos,
    required this.validadoresActivos,
    required this.eventosVigentesLista,
  });
}

final metricasAdminProvider = FutureProvider.autoDispose<MetricasAdmin>((
  ref,
) async {
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
        'id, nombre, fecha, hora_inicio, cupos_maximos, estado, '
        'inscripciones(id)',
      )
      .order('fecha');

  final validadores = await supabase
      .from('usuarios')
      .select('id')
      .eq('rol', 'validador')
      .eq('activo', true)
      .gt('vigente_hasta', DateTime.now().toUtc().toIso8601String());

  int totalInscriptos = 0;
  final vigentes = <EventoResumen>[];

  for (final fila in eventos as List) {
    final inscripciones = (fila['inscripciones'] as List?) ?? const [];
    totalInscriptos += inscripciones.length;

    if ((fila['estado'] as String?) == 'vigente') {
      vigentes.add(
        EventoResumen(
          id: fila['id'] as String,
          nombre: fila['nombre'] as String,
          fecha: DateTime.parse(fila['fecha'] as String),
          horaInicio: (fila['hora_inicio'] as String).substring(0, 5),
          inscriptos: inscripciones.length,
          cuposMaximos: fila['cupos_maximos'] as int?,
        ),
      );
    }
  }

  vigentes.sort((a, b) => a.fecha.compareTo(b.fecha));

  return MetricasAdmin(
    nombreCompleto: perfil['nombre_completo'] as String,
    eventosVigentes: vigentes.length,
    totalInscriptos: totalInscriptos,
    validadoresActivos: (validadores as List).length,
    eventosVigentesLista: vigentes,
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

      // Horas acreditadas: asistencia completa (entrada y salida) en eventos no
      // cancelados. Se calcula en el servidor porque el alumno no ve los eventos
      // ya finalizados o cancelados (RLS), así que no podría sumarlas acá.
      final horas = await supabase.rpc('mis_horas_acreditadas');
      final horasCompletadas = (horas as num?)?.toInt() ?? 0;

      // `eventos` solo viene con datos si el evento sigue vigente (RLS).
      final inscripciones = await supabase
          .from('inscripciones')
          .select('asistencia_confirmada, eventos(id)')
          .eq('usuario_id', userId);

      // Pendientes: eventos vigentes en los que todavía no completó la asistencia.
      int pendientes = 0;
      for (final fila in inscripciones as List) {
        final confirmada = fila['asistencia_confirmada'] as bool? ?? false;
        final evento = fila['eventos'];
        if (!confirmada && evento != null) pendientes += 1;
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
