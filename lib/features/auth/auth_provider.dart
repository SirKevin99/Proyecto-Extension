import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router.dart';
import '../../core/secure_storage.dart';
import '../../core/supabase_client.dart';

enum AuthStatus { inicial, cargando, autenticado, error }

class AuthState {
  final AuthStatus status;
  final String? mensajeError;
  final RolUsuario? rol;

  const AuthState({
    this.status = AuthStatus.inicial,
    this.mensajeError,
    this.rol,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? mensajeError,
    RolUsuario? rol,
  }) {
    return AuthState(
      status: status ?? this.status,
      mensajeError: mensajeError,
      rol: rol ?? this.rol,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  static final RegExp _codigoValidador = RegExp(r'^VAL-\d{4}$');

  /// [identificador] es la C.I. numérica (alumno / admin) o el código
  /// `VAL-####` (validador temporal).
  Future<void> login({
    required String identificador,
    required String password,
  }) async {
    final id = identificador.trim().toUpperCase();
    final esValidador = _codigoValidador.hasMatch(id);

    state = state.copyWith(status: AuthStatus.cargando, mensajeError: null);

    try {
      // 1. Resolver el correo (el usuario aún no está autenticado, por
      //    eso se usa la vista pública y acotada, no la tabla).
      //    La vista excluye validadores vencidos o inactivos.
      final resuelto = await supabase
          .from('vista_resolucion_ci')
          .select('correo_institucional')
          .eq('ci', id)
          .maybeSingle();

      if (resuelto == null) {
        _fallar(
          esValidador
              ? 'El código no existe o su vigencia ya venció.'
              : 'La cédula ingresada no está registrada.',
        );
        return;
      }

      // 2. Autenticar contra Supabase Auth.
      final authResponse = await supabase.auth.signInWithPassword(
        email: resuelto['correo_institucional'] as String,
        password: password,
      );

      final session = authResponse.session;
      final user = authResponse.user;
      if (session == null || user == null) {
        _fallar('No se pudo iniciar sesión. Verificá tu contraseña.');
        return;
      }

      // 3. Rol real desde la fila propia (ya autenticado).
      final perfil = await supabase
          .from('usuarios')
          .select('rol, activo, vigente_hasta')
          .eq('id', user.id)
          .maybeSingle();

      final rol = rolDesdeString(perfil?['rol'] as String?);
      final activo = perfil?['activo'] as bool? ?? false;
      final vigenteHasta = perfil?['vigente_hasta'] as String?;
      final vencido = vigenteHasta != null &&
          DateTime.parse(vigenteHasta).isBefore(DateTime.now());

      if (perfil == null || rol == null || !activo || vencido) {
        await supabase.auth.signOut();
        _fallar(
          rol == RolUsuario.validador || vencido
              ? 'Tu acceso temporal ya venció.'
              : 'Tu cuenta no tiene un perfil habilitado. '
                  'Contactá al administrador.',
        );
        return;
      }

      // 4. Persistir en almacenamiento seguro.
      await SecureStorageService.instance.guardarTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken ?? '',
      );
      await SecureStorageService.instance.guardarDatosUsuario(
        ci: id,
        rol: perfil['rol'] as String,
      );

      // 5. Refrescar el snapshot: el redirect del router lleva al home
      //    que corresponda al rol.
      await SessionSnapshot.instance.cargarDesdeStorage();
      AppRouterRefresh.instance.refrescar();

      state = state.copyWith(status: AuthStatus.autenticado, rol: rol);
    } on AuthException catch (e) {
      _fallar(_mensajeAuthLegible(e.message));
    } catch (_) {
      _fallar('Ocurrió un error inesperado. Intentá nuevamente.');
    }
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
    await SecureStorageService.instance.limpiarSesion();
    SessionSnapshot.instance.limpiar();
    AppRouterRefresh.instance.refrescar();
    state = const AuthState();
  }

  void limpiarError() {
    state = state.copyWith(status: AuthStatus.inicial, mensajeError: null);
  }

  void _fallar(String mensaje) {
    state = state.copyWith(status: AuthStatus.error, mensajeError: mensaje);
  }

  String _mensajeAuthLegible(String original) {
    final texto = original.toLowerCase();
    if (texto.contains('invalid login credentials')) {
      return 'Identificación o contraseña incorrecta.';
    }
    if (texto.contains('banned')) {
      return 'Tu acceso temporal ya venció.';
    }
    return 'No se pudo iniciar sesión. Intentá nuevamente.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);