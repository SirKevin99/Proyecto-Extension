import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class ValidadorActivo {
  final String id;
  final String? codigo; // VAL-#### (null si el script 12 no está aplicado)
  final String nombre;
  final String? eventoNombre;
  final DateTime? eventoFecha;
  final DateTime vigenteHasta;

  const ValidadorActivo({
    required this.id,
    required this.codigo,
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
      codigo: f['codigo'] as String?,
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

// ---------------------------------------------------------------
// Ajuste 3: restablecer la clave de un validador
// ---------------------------------------------------------------

/// Resultado del restablecimiento. La clave se devuelve UNA sola vez:
/// el servidor no la guarda en claro.
class ClaveRestablecida {
  final String codigo;
  final String password;
  final DateTime vigenteHasta;

  const ClaveRestablecida({
    required this.codigo,
    required this.password,
    required this.vigenteHasta,
  });
}

/// Error con mensaje listo para mostrar al usuario.
class RestablecerClaveException implements Exception {
  final String mensaje;
  const RestablecerClaveException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Llama a la Edge Function `restablecer-clave-validador`.
/// El servidor verifica que quien llama sea admin y que el validador
/// esté activo y vigente, y deja la acción auditada.
Future<ClaveRestablecida> restablecerClaveValidador(String validadorId) async {
  try {
    final r = await supabase.functions.invoke(
      'restablecer-clave-validador',
      body: {'validador_id': validadorId},
    );
    final data = r.data;
    if (data is Map<String, dynamic> && data['exito'] == true) {
      return ClaveRestablecida(
        codigo: data['codigo'] as String,
        password: data['password'] as String,
        vigenteHasta:
            DateTime.parse(data['vigente_hasta'] as String).toLocal(),
      );
    }
    throw RestablecerClaveException(_errorDe(data));
  } on FunctionException catch (e) {
    // La función responde 400/403/500 con { "error": "..." }.
    throw RestablecerClaveException(_errorDe(e.details));
  } on RestablecerClaveException {
    rethrow;
  } catch (_) {
    throw const RestablecerClaveException(
      'No se pudo conectar con el servidor. Revisá tu conexión.',
    );
  }
}

String _errorDe(dynamic data) {
  if (data is Map && data['error'] is String) {
    return data['error'] as String;
  }
  return 'No se pudo restablecer la clave. Intentá nuevamente.';
}