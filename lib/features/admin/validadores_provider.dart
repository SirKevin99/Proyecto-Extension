import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';

class ValidadorActivo {
  final String id;
  final String nombre;
  final String? eventoNombre;
  final DateTime? eventoFecha;
  final DateTime vigenteHasta;

  const ValidadorActivo({
    required this.id,
    required this.nombre,
    required this.eventoNombre,
    required this.eventoFecha,
    required this.vigenteHasta,
  });
}

/// Validadores vigentes. El servidor (RPC) solo responde a admin y superadmin.
final validadoresProvider =
    FutureProvider.autoDispose<List<ValidadorActivo>>((ref) async {
  final data = await supabase.rpc('listar_validadores');

  return (data as List).map((f) {
    final fecha = f['evento_fecha'] as String?;
    return ValidadorActivo(
      id: f['id'] as String,
      nombre: f['nombre_completo'] as String,
      eventoNombre: f['evento_nombre'] as String?,
      eventoFecha: fecha == null ? null : DateTime.parse(fecha),
      vigenteHasta: DateTime.parse(f['vigente_hasta'] as String).toLocal(),
    );
  }).toList();
});

Future<void> desactivarValidador(String id) async {
  await supabase.rpc('desactivar_validador', params: {'p_usuario_id': id});
}