import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';

class EventoAdmin {
  final String id;
  final String nombre;
  final DateTime fecha;
  final String horaInicio;
  final String ubicacion;
  final bool activo;
  final int cuposMaximos;
  final int inscriptos;
  final int pendientes;

  const EventoAdmin({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.horaInicio,
    required this.ubicacion,
    required this.activo,
    required this.cuposMaximos,
    required this.inscriptos,
    required this.pendientes,
  });

  bool get yaOcurrio {
    final hoy = DateTime.now();
    return fecha.isBefore(DateTime(hoy.year, hoy.month, hoy.day));
  }
}

/// Todos los eventos (pasados, de hoy, futuros e inactivos).
/// RLS: el admin ve todos los eventos e inscripciones.
final adminEventosProvider =
    FutureProvider.autoDispose<List<EventoAdmin>>((ref) async {
  final data = await supabase
      .from('eventos')
      .select(
        'id, nombre, fecha, hora_inicio, ubicacion, activo, cupos_maximos, '
        'inscripciones(id, asistencia_confirmada)',
      )
      .order('fecha', ascending: false);

  return (data as List).map((fila) {
    final inscripciones = (fila['inscripciones'] as List?) ?? const [];
    final pendientes = inscripciones
        .where((i) => (i['asistencia_confirmada'] as bool? ?? false) == false)
        .length;

    return EventoAdmin(
      id: fila['id'] as String,
      nombre: fila['nombre'] as String,
      fecha: DateTime.parse(fila['fecha'] as String),
      horaInicio: (fila['hora_inicio'] as String).substring(0, 5),
      ubicacion: fila['ubicacion'] as String,
      activo: fila['activo'] as bool? ?? true,
      cuposMaximos: fila['cupos_maximos'] as int,
      inscriptos: inscripciones.length,
      pendientes: pendientes,
    );
  }).toList();
});