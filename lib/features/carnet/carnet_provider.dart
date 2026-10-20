import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/secure_storage.dart';
import '../../core/supabase_client.dart';

/// Datos del carnet del alumno (fase 7, paso 7.2).
/// Solo identifica al alumno: no marca asistencia ni se verifica.
class DatosCarnet {
  final String ci;
  final String nombreCompleto;
  final String carrera;
  final String correo;

  /// Momento en que se leyeron del servidor por última vez.
  final DateTime actualizadoEn;

  const DatosCarnet({
    required this.ci,
    required this.nombreCompleto,
    required this.carrera,
    required this.correo,
    required this.actualizadoEn,
  });

  /// Texto del QR: legible con cualquier lector, sin firma ni código.
  /// Empieza con la marca BOM de UTF-8 (U+FEFF, invisible): algunos lectores
  /// (p. ej. el de los teléfonos Xiaomi) adivinan la codificación y, con
  /// pocas letras acentuadas, las mostraban como caracteres japoneses
  /// (prueba 2.4 del paso 7.2). `qr_flutter` 4.1 no permite declarar la
  /// codificación (ECI) de otra forma.
  String get textoQr => '\uFEFF'
      'UniNorte - Carnet de alumno\n'
      'C.I.: $ci\n'
      'Nombre: $nombreCompleto\n'
      'Carrera: $carrera\n'
      'Correo: $correo';

  Map<String, dynamic> toJson() => {
        'ci': ci,
        'nombre_completo': nombreCompleto,
        'carrera': carrera,
        'correo': correo,
        'actualizado_en': actualizadoEn.toUtc().toIso8601String(),
      };

  factory DatosCarnet.fromJson(Map<String, dynamic> m) => DatosCarnet(
        ci: m['ci'] as String,
        nombreCompleto: m['nombre_completo'] as String,
        carrera: m['carrera'] as String,
        correo: m['correo'] as String,
        actualizadoEn: DateTime.parse(m['actualizado_en'] as String).toLocal(),
      );
}

/// Resultado para la pantalla: los datos y si vienen del teléfono
/// (sin conexión) en lugar del servidor.
class CarnetResultado {
  final DatosCarnet datos;
  final bool sinConexion;

  const CarnetResultado({required this.datos, required this.sinConexion});
}

class CarnetException implements Exception {
  final String mensaje;
  const CarnetException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Intenta leer los datos del servidor y los guarda en el teléfono.
/// Si no hay conexión (o falla), muestra los últimos datos guardados.
/// Los datos guardados se borran al cerrar sesión (`limpiarSesion`).
final carnetProvider =
    FutureProvider.autoDispose<CarnetResultado>((ref) async {
  try {
    final datos = await CarnetService.leerDelServidor();
    await CarnetService.guardar(datos);
    return CarnetResultado(datos: datos, sinConexion: false);
  } catch (_) {
    final guardados = await CarnetService.leerGuardados();
    if (guardados != null) {
      return CarnetResultado(datos: guardados, sinConexion: true);
    }
    throw const CarnetException(
      'No se pudo cargar tu carnet. Conectate a internet una vez para '
      'guardarlo en el teléfono; después podrás verlo sin conexión.',
    );
  }
});

class CarnetService {
  CarnetService._();

  /// Sin conexión, la consulta puede tardar mucho en fallar: se corta antes
  /// para mostrar enseguida los datos guardados.
  static const Duration _espera = Duration(seconds: 8);

  static Future<DatosCarnet> leerDelServidor() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw const CarnetException('Sesión no disponible');
    }

    // RLS: el alumno solo puede leer su propia fila (usuarios_select_propio).
    final fila = await supabase
        .from('usuarios')
        .select('ci, nombre_completo, carrera, correo_institucional')
        .eq('id', userId)
        .single()
        .timeout(_espera);

    return DatosCarnet(
      ci: fila['ci'] as String,
      nombreCompleto: fila['nombre_completo'] as String,
      carrera: fila['carrera'] as String,
      correo: fila['correo_institucional'] as String,
      actualizadoEn: DateTime.now(),
    );
  }

  static Future<void> guardar(DatosCarnet datos) async {
    try {
      await SecureStorageService.instance
          .guardarCarnet(jsonEncode(datos.toJson()));
    } catch (_) {
      // Si no se puede guardar, el carnet igual se muestra con conexión.
    }
  }

  static Future<DatosCarnet?> leerGuardados() async {
    try {
      final texto = await SecureStorageService.instance.obtenerCarnet();
      if (texto == null || texto.isEmpty) return null;
      return DatosCarnet.fromJson(jsonDecode(texto) as Map<String, dynamic>);
    } catch (_) {
      return null; // dato corrupto o ilegible: se trata como inexistente
    }
  }
}