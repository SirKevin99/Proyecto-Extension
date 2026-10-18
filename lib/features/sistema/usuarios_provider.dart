import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Usuario visible en "Administración del sistema" (fase 5, solo superadmin).
/// Incluye alumnos, administradores y el superadmin (este último solo se
/// muestra; no se edita). Los validadores se gestionan en su propia pantalla.
class UsuarioSistema {
  final String id;
  final String nombreCompleto;
  final String ci;
  final String correo;
  final String carrera;
  final String rol;
  final bool activo;
  final int horasRequeridas;

  const UsuarioSistema({
    required this.id,
    required this.nombreCompleto,
    required this.ci,
    required this.correo,
    required this.carrera,
    required this.rol,
    required this.activo,
    required this.horasRequeridas,
  });

  /// Solo alumnos y administradores se editan desde la app.
  bool get esEditable => rol == 'alumno' || rol == 'admin';

  String get rolLegible => switch (rol) {
        'alumno' => 'Alumno',
        'admin' => 'Administrador',
        'superadmin' => 'Superadmin',
        _ => rol,
      };

  factory UsuarioSistema.fromMap(Map<String, dynamic> m) => UsuarioSistema(
        id: m['id'] as String,
        nombreCompleto: m['nombre_completo'] as String,
        ci: m['ci'] as String,
        correo: m['correo_institucional'] as String,
        carrera: m['carrera'] as String,
        rol: m['rol'] as String,
        activo: m['activo'] as bool? ?? false,
        horasRequeridas: (m['horas_requeridas'] as num?)?.toInt() ?? 120,
      );
}

enum FiltroRolUsuario { todos, alumno, admin }

enum FiltroEstadoUsuario { todos, activos, inactivos }

class FiltrosUsuarios {
  final String busqueda;
  final FiltroRolUsuario rol;
  final FiltroEstadoUsuario estado;

  const FiltrosUsuarios({
    this.busqueda = '',
    this.rol = FiltroRolUsuario.todos,
    this.estado = FiltroEstadoUsuario.todos,
  });

  FiltrosUsuarios copyWith({
    String? busqueda,
    FiltroRolUsuario? rol,
    FiltroEstadoUsuario? estado,
  }) {
    return FiltrosUsuarios(
      busqueda: busqueda ?? this.busqueda,
      rol: rol ?? this.rol,
      estado: estado ?? this.estado,
    );
  }

  // Necesarios para usar los filtros como clave del provider .family
  @override
  bool operator ==(Object other) =>
      other is FiltrosUsuarios &&
      other.busqueda == busqueda &&
      other.rol == rol &&
      other.estado == estado;

  @override
  int get hashCode => Object.hash(busqueda, rol, estado);
}

const _columnas = 'id, nombre_completo, ci, correo_institucional, carrera, '
    'rol, activo, horas_requeridas';

/// Máximo de filas por consulta. Con más resultados, se pide afinar la búsqueda.
const limiteUsuarios = 200;

/// Lista filtrada en el servidor. La lectura la permite la policy
/// usuarios_select_admin (script 15).
final usuariosSistemaProvider = FutureProvider.autoDispose
    .family<List<UsuarioSistema>, FiltrosUsuarios>((ref, f) async {
  final roles = switch (f.rol) {
    FiltroRolUsuario.todos => ['alumno', 'admin', 'superadmin'],
    FiltroRolUsuario.alumno => ['alumno'],
    FiltroRolUsuario.admin => ['admin'],
  };

  var consulta =
      supabase.from('usuarios').select(_columnas).inFilter('rol', roles);

  if (f.estado != FiltroEstadoUsuario.todos) {
    consulta = consulta.eq('activo', f.estado == FiltroEstadoUsuario.activos);
  }

  final texto = _limpiarBusqueda(f.busqueda);
  if (texto.isNotEmpty) {
    consulta =
        consulta.or('nombre_completo.ilike.%$texto%,ci.ilike.%$texto%');
  }

  final filas = await consulta.order('nombre_completo').limit(limiteUsuarios);

  return (filas as List)
      .map((m) => UsuarioSistema.fromMap(m as Map<String, dynamic>))
      .toList();
});

/// Quita caracteres que alteran la sintaxis del filtro `or` de PostgREST.
String _limpiarBusqueda(String texto) =>
    texto.trim().replaceAll(RegExp(r'[,()%*\\:"]'), '');

/// Error con mensaje listo para mostrar al usuario.
class GestionUsuarioException implements Exception {
  final String mensaje;
  const GestionUsuarioException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Operaciones del superadmin (funciones del script 16).
class GestionUsuariosService {
  GestionUsuariosService._();

  static Future<UsuarioSistema> obtener(String id) {
    return _ejecutar(() async {
      final fila = await supabase
          .from('usuarios')
          .select(_columnas)
          .eq('id', id)
          .maybeSingle();
      if (fila == null) {
        throw const GestionUsuarioException('El usuario no existe');
      }
      return UsuarioSistema.fromMap(fila);
    });
  }

  static Future<void> editar({
    required String id,
    required String nombreCompleto,
    required String ci,
    required String carrera,
    required int horasRequeridas,
    required String rol, // 'alumno' | 'admin'
  }) {
    return _ejecutar(() => supabase.rpc('editar_usuario', params: {
          'p_usuario_id': id,
          'p_nombre': nombreCompleto,
          'p_ci': ci,
          'p_carrera': carrera,
          'p_horas_requeridas': horasRequeridas,
          'p_rol': rol,
        }));
  }

  static Future<void> desactivar(String id) => _ejecutar(
      () => supabase.rpc('desactivar_usuario', params: {'p_usuario_id': id}));

  static Future<void> reactivar(String id) => _ejecutar(
      () => supabase.rpc('reactivar_usuario', params: {'p_usuario_id': id}));

  static Future<T> _ejecutar<T>(Future<T> Function() accion) async {
    try {
      return await accion();
    } on GestionUsuarioException {
      rethrow;
    } on PostgrestException catch (e) {
      // Los RAISE EXCEPTION del servidor ya vienen en español.
      throw GestionUsuarioException(e.message);
    } catch (_) {
      throw const GestionUsuarioException(
        'No se pudo conectar con el servidor. Revisá tu conexión.',
      );
    }
  }
}