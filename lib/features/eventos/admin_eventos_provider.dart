import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';

enum EstadoEvento {
  vigente,
  finalizado,
  cancelado;

  static EstadoEvento desdeTexto(String? valor) => switch (valor) {
        'finalizado' => EstadoEvento.finalizado,
        'cancelado' => EstadoEvento.cancelado,
        _ => EstadoEvento.vigente,
      };
}

class EventoAdmin {
  final String id;
  final String nombre;
  final DateTime fecha;
  final String horaInicio;
  final String ubicacion;
  final EstadoEvento estado;
  final int? cuposMaximos; // null = ilimitado
  final int inscriptos;

  /// Cargado como evento pasado por el superadmin (fase 8, script 21).
  final bool cargaHistorica;

  const EventoAdmin({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.horaInicio,
    required this.ubicacion,
    required this.estado,
    required this.cuposMaximos,
    required this.inscriptos,
    this.cargaHistorica = false,
  });

  bool get vigente => estado == EstadoEvento.vigente;

  /// La fecha del evento es anterior a hoy (hora del dispositivo).
  bool get fechaPasada {
    final ahora = DateTime.now();
    return fecha.isBefore(DateTime(ahora.year, ahora.month, ahora.day));
  }
}

/// Todos los eventos, sin importar su estado.
/// RLS: el admin ve todos los eventos e inscripciones.
final adminEventosProvider =
    FutureProvider.autoDispose<List<EventoAdmin>>((ref) async {
  final data = await supabase
      .from('eventos')
      .select(
        'id, nombre, fecha, hora_inicio, ubicacion, estado, cupos_maximos, '
        'carga_historica, inscripciones(id)',
      )
      .order('fecha', ascending: false);

  return (data as List).map((fila) {
    final inscripciones = (fila['inscripciones'] as List?) ?? const [];

    return EventoAdmin(
      id: fila['id'] as String,
      nombre: fila['nombre'] as String,
      fecha: DateTime.parse(fila['fecha'] as String),
      horaInicio: (fila['hora_inicio'] as String).substring(0, 5),
      ubicacion: fila['ubicacion'] as String,
      estado: EstadoEvento.desdeTexto(fila['estado'] as String?),
      cuposMaximos: fila['cupos_maximos'] as int?,
      inscriptos: inscripciones.length,
      cargaHistorica: fila['carga_historica'] as bool? ?? false,
    );
  }).toList();
});

/// Cierra un evento vigente. Lo resuelve el servidor (RPC), que además
/// cierra las sesiones de asistencia y deshabilita al validador asignado.
Future<void> finalizarEvento(String eventoId) async {
  await supabase.rpc('finalizar_evento', params: {'p_evento_id': eventoId});
}

Future<void> cancelarEvento(String eventoId) async {
  await supabase.rpc('cancelar_evento', params: {'p_evento_id': eventoId});
}

/// Reactiva un evento cancelado con fecha pasada como finalizado
/// (solo superadmin, fase 8, script 21). El servidor emite los
/// certificados de quienes tienen entrada y salida. Devuelve cuántos
/// asistentes tienen la asistencia completa.
Future<int> reactivarEventoCancelado(String eventoId, String motivo) async {
  final completos = await supabase.rpc('reactivar_evento_cancelado', params: {
    'p_evento_id': eventoId,
    'p_motivo': motivo,
  });
  return (completos as num?)?.toInt() ?? 0;
}