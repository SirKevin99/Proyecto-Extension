import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Certificado del alumno (fase 7, paso 7.3c), tal como lo devuelve
/// `mis_certificados()` (script 20).
/// - Nombre del alumno y datos del evento: al día.
/// - Carrera y firmantes: copia fija del momento de la emisión.
/// - Pendiente: la carrera todavía no tiene firmantes completos.
class Certificado {
  final int id;
  final bool emitido;
  final String alumno;
  final String eventoId;
  final String evento;
  final DateTime fecha;
  final String ubicacion;
  final int horas;
  final String carrera;
  final String? facultad;
  final String? decanoNombre;
  final String? decanoCargo;
  final String? directorNombre;
  final String? directorCargo;

  const Certificado({
    required this.id,
    required this.emitido,
    required this.alumno,
    required this.eventoId,
    required this.evento,
    required this.fecha,
    required this.ubicacion,
    required this.horas,
    required this.carrera,
    required this.facultad,
    required this.decanoNombre,
    required this.decanoCargo,
    required this.directorNombre,
    required this.directorCargo,
  });

  /// Se puede generar el PDF (emitido y con todos los firmantes).
  bool get disponible =>
      emitido &&
      facultad != null &&
      decanoNombre != null &&
      decanoCargo != null &&
      directorNombre != null &&
      directorCargo != null;

  /// `Certificado-[evento]-[aaaa-mm-dd].pdf`, sin caracteres que los
  /// sistemas de archivos no aceptan.
  String get nombreArchivo {
    final limpio = evento
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    final corto = limpio.length > 60 ? limpio.substring(0, 60) : limpio;
    String dos(int n) => n.toString().padLeft(2, '0');
    return 'Certificado-$corto-${fecha.year}-${dos(fecha.month)}-${dos(fecha.day)}.pdf';
  }

  factory Certificado.fromMap(Map<String, dynamic> m) => Certificado(
        id: (m['certificado_id'] as num).toInt(),
        emitido: m['estado'] == 'emitido',
        alumno: m['alumno'] as String,
        eventoId: m['evento_id'] as String,
        evento: m['evento'] as String,
        fecha: DateTime.parse(m['fecha'] as String),
        ubicacion: m['ubicacion'] as String? ?? '',
        horas: (m['horas'] as num?)?.toInt() ?? 0,
        carrera: m['carrera'] as String,
        facultad: m['facultad'] as String?,
        decanoNombre: m['decano_nombre'] as String?,
        decanoCargo: m['decano_cargo'] as String?,
        directorNombre: m['director_nombre'] as String?,
        directorCargo: m['director_cargo'] as String?,
      );
}

class CertificadosException implements Exception {
  final String mensaje;
  const CertificadosException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Certificados del alumno autenticado (emitidos y pendientes), del
/// evento más reciente al más antiguo. Necesita conexión.
final misCertificadosProvider =
    FutureProvider.autoDispose<List<Certificado>>((ref) async {
  try {
    final filas = await supabase.rpc('mis_certificados');
    return (filas as List)
        .map((f) => Certificado.fromMap(f as Map<String, dynamic>))
        .toList();
  } on PostgrestException catch (e) {
    throw CertificadosException(e.message);
  } catch (_) {
    throw const CertificadosException(
      'No se pudieron cargar tus certificados. Revisá tu conexión.',
    );
  }
});