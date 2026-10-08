import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';

class InscriptoAsistencia {
  final String inscripcionId;
  final String nombre;
  final String ci;
  final bool presente;
  final String? metodo; // 'qr' | 'pin' | 'manual'
  final DateTime? fechaMarcaje;

  const InscriptoAsistencia({
    required this.inscripcionId,
    required this.nombre,
    required this.ci,
    required this.presente,
    this.metodo,
    this.fechaMarcaje,
  });
}

class GestionAsistenciaData {
  final String eventoNombre;
  final List<InscriptoAsistencia> inscriptos;

  const GestionAsistenciaData({
    required this.eventoNombre,
    required this.inscriptos,
  });

  int get presentes => inscriptos.where((i) => i.presente).length;
}

/// Inscriptos de un evento. RLS: solo el admin puede leer todas las
/// inscripciones y los datos de los alumnos.
final gestionAsistenciaProvider = FutureProvider.autoDispose
    .family<GestionAsistenciaData, String>((ref, eventoId) async {
  final evento =
      await supabase.from('eventos').select('nombre').eq('id', eventoId).single();

  final filas = await supabase
      .from('inscripciones')
      .select(
        'id, asistencia_confirmada, metodo_validacion, fecha_marcaje, '
        'usuario:usuarios!usuario_id(nombre_completo, ci)',
      )
      .eq('evento_id', eventoId);

  final inscriptos = <InscriptoAsistencia>[];
  for (final fila in filas as List) {
    final usuario = fila['usuario'] as Map<String, dynamic>?;
    final marcaje = fila['fecha_marcaje'] as String?;
    inscriptos.add(InscriptoAsistencia(
      inscripcionId: fila['id'] as String,
      nombre: usuario?['nombre_completo'] as String? ?? 'Sin nombre',
      ci: usuario?['ci'] as String? ?? '-',
      presente: fila['asistencia_confirmada'] as bool? ?? false,
      metodo: fila['metodo_validacion'] as String?,
      fechaMarcaje: marcaje == null ? null : DateTime.parse(marcaje).toLocal(),
    ));
  }

  inscriptos.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

  return GestionAsistenciaData(
    eventoNombre: evento['nombre'] as String,
    inscriptos: inscriptos,
  );
});

class CorreccionService {
  CorreccionService._();

  /// Valida o revoca las inscripciones indicadas (individual o en lote).
  /// La RPC audita con `validado_por = auth.uid()` y `fecha_validacion`.
  static Future<int> corregir(List<String> ids, {required bool confirmada}) async {
    final r = await supabase.rpc('corregir_asistencia', params: {
      'p_inscripcion_ids': ids,
      'p_confirmada': confirmada,
    });
    return r as int;
  }
}