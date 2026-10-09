
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Resultado del alta de un validador. La clave se devuelve UNA sola
/// vez: el servidor no la guarda en claro, así que no se puede recuperar.
class ValidadorCreado {
  final String codigo;
  final String password;
  final DateTime vigenteHasta;

  const ValidadorCreado({
    required this.codigo,
    required this.password,
    required this.vigenteHasta,
  });
}

/// Error con mensaje listo para mostrar al usuario.
class AltaException implements Exception {
  final String mensaje;
  const AltaException(this.mensaje);

  @override
  String toString() => mensaje;
}

class AdminUsuariosService {
  AdminUsuariosService._();

  static const _funcion = 'crear-usuario';

  /// Alta de alumno o admin. El correo se arma en el servidor con
  /// [correoLocal] + dominio institucional.
  static Future<void> crearUsuario({
    required String rol, // 'alumno' | 'admin'
    required String nombreCompleto,
    required String ci,
    required String correoLocal,
    required String carrera,
    required String password,
  }) async {
    await _invocar({
      'rol': rol,
      'nombre_completo': nombreCompleto,
      'ci': ci,
      'correo_local': correoLocal,
      'carrera': carrera,
      'password': password,
    });
  }

  /// Alta de validador temporal. Código y clave los genera el servidor.
  /// Si [vigenteHasta] es nulo, vence 1 hora después de `hora_fin`.
  static Future<ValidadorCreado> crearValidador({
    required String nombreCompleto,
    required String eventoId,
    DateTime? vigenteHasta,
  }) async {
    final data = await _invocar({
      'rol': 'validador',
      'nombre_completo': nombreCompleto,
      'evento_id': eventoId,
      if (vigenteHasta != null)
        'vigente_hasta': vigenteHasta.toUtc().toIso8601String(),
    });

    return ValidadorCreado(
      codigo: data['codigo'] as String,
      password: data['password'] as String,
      vigenteHasta: DateTime.parse(data['vigente_hasta'] as String).toLocal(),
    );
  }

  static Future<Map<String, dynamic>> _invocar(
    Map<String, dynamic> cuerpo,
  ) async {
    try {
      final r = await supabase.functions.invoke(_funcion, body: cuerpo);
      final data = r.data;
      if (data is Map<String, dynamic> && data['exito'] == true) {
        return data;
      }
      throw AltaException(_errorDe(data));
    } on FunctionException catch (e) {
      // La función responde 400/403 con { "error": "..." }.
      throw AltaException(_errorDe(e.details));
    } on AltaException {
      rethrow;
    } catch (_) {
      throw const AltaException(
        'No se pudo conectar con el servidor. Revisá tu conexión.',
      );
    }
  }

  static String _errorDe(dynamic data) {
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    return 'No se pudo completar el alta. Intentá nuevamente.';
  }
}