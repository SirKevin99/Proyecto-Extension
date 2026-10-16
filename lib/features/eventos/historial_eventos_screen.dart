import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import 'admin_eventos_provider.dart' show EstadoEvento;

/// Cómo quedó la participación del alumno en un evento.
enum SituacionHistorial {
  /// Entrada y salida registradas en un evento no cancelado: suma horas.
  acreditado,

  /// Evento vigente en el que todavía puede completar su asistencia.
  enCurso,

  /// Evento finalizado sin entrada y salida completas: no suma horas.
  noAcreditado,

  /// Evento cancelado: no suma horas aunque haya marcado.
  cancelado,
}

class EventoHistorial {
  final String id;
  final String nombre;
  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final String ubicacion;
  final int horasOtorgadas;
  final EstadoEvento estado;
  final DateTime? entradaEn;
  final DateTime? salidaEn;

  const EventoHistorial({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.ubicacion,
    required this.horasOtorgadas,
    required this.estado,
    this.entradaEn,
    this.salidaEn,
  });

  bool get completo => entradaEn != null && salidaEn != null;

  SituacionHistorial get situacion {
    if (estado == EstadoEvento.cancelado) return SituacionHistorial.cancelado;
    if (completo) return SituacionHistorial.acreditado;
    if (estado == EstadoEvento.vigente) return SituacionHistorial.enCurso;
    return SituacionHistorial.noAcreditado;
  }
}

/// Todas las inscripciones del alumno, de cualquier estado de evento.
/// Se resuelve en el servidor porque el alumno no puede leer los eventos
/// finalizados o cancelados directamente (RLS).
final historialEventosProvider =
    FutureProvider.autoDispose<List<EventoHistorial>>((ref) async {
  final data = await supabase.rpc('mis_eventos_historial');

  DateTime? hora(Object? valor) =>
      valor == null ? null : DateTime.parse(valor as String).toLocal();

  return (data as List).map((f) {
    return EventoHistorial(
      id: f['evento_id'] as String,
      nombre: f['nombre'] as String,
      fecha: DateTime.parse(f['fecha'] as String),
      horaInicio: (f['hora_inicio'] as String).substring(0, 5),
      horaFin: (f['hora_fin'] as String).substring(0, 5),
      ubicacion: f['ubicacion'] as String? ?? '',
      horasOtorgadas: (f['horas_otorgadas'] as num?)?.toInt() ?? 0,
      estado: EstadoEvento.desdeTexto(f['estado'] as String?),
      entradaEn: hora(f['entrada_en']),
      salidaEn: hora(f['salida_en']),
    );
  }).toList();
});