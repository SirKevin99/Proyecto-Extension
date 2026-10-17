import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase_client.dart';

/// Carrera de la lista oficial (tabla `carreras`).
class Carrera {
  final int id;
  final String nombre;

  const Carrera({required this.id, required this.nombre});

  factory Carrera.fromMap(Map<String, dynamic> m) => Carrera(
        id: (m['id'] as num).toInt(),
        nombre: m['nombre'] as String,
      );
}

/// Carreras activas, ordenadas por nombre.
/// La usan el alta de usuarios y la creación/edición de eventos.
final carrerasProvider =
    FutureProvider.autoDispose<List<Carrera>>((ref) async {
  final filas = await supabase
      .from('carreras')
      .select('id, nombre')
      .eq('activa', true)
      .order('nombre');

  return (filas as List)
      .map((f) => Carrera.fromMap(f as Map<String, dynamic>))
      .toList();
});