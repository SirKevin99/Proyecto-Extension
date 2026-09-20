import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router.dart';
import '../../core/secure_storage.dart';
import '../../core/supabase_client.dart';

/// Estados posibles del proceso de autenticación.
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

  /// Login por C.I.: resuelve el correo institucional vinculado a la
  /// cédula consultando la tabla `usuarios`, y autentica contra
  /// Supabase Auth con ese correo + password.
  Future<void> login({
    required String ci,
    required String password,
  }) async {
    state = state.copyWith(status: AuthStatus.cargando, mensajeError: null);

    try {
      // 1. Resolver correo institucional a partir de la C.I.
      //    Esta consulta debe estar permitida por RLS solo para
      //    lectura de la columna `correo_institucional` y `rol`
      //    (sin exponer datos sensibles de otros usuarios).
      final resultado = await supabase
          .from('usuarios')
          .select('correo_institucional, rol')
          .eq('ci', ci)
          .maybeSingle();

      if (resultado == null) {
        state = state.copyWith(
          status: AuthStatus.error,
          mensajeError: 'La cédula ingresada no está registrada.',
        );
        return;
      }

      final correo = resultado['correo_institucional'] as String;
      final rol = rolDesdeString(resultado['rol'] as String?);

      // 2. Autenticar contra Supabase Auth con el correo resuelto.
      final authResponse = await supabase.auth.signInWithPassword(
        email: correo,
        password: password,
      );

      final session = authResponse.session;
      if (session == null) {
        state = state.copyWith(
          status: AuthStatus.error,
          mensajeError: 'No se pudo iniciar sesión. Verificá tu contraseña.',
        );
        return;
      }

      // 3. Guardar tokens y datos de sesión en almacenamiento seguro.
      await SecureStorageService.instance.guardarTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken ?? '',
      );
      await SecureStorageService.instance.guardarDatosUsuario(
        ci: ci,
        rol: resultado['rol'] as String? ?? 'alumno',
      );

      // 4. Refrescar snapshot de sesión para que el router reevalúe
      //    el redirect y navegue al home correspondiente.
      await SessionSnapshot.instance.cargarDesdeStorage();
      AppRouterRefresh.instance.refrescar();

      state = state.copyWith(status: AuthStatus.autenticado, rol: rol);
    } on AuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        mensajeError: _mensajeAuthLegible(e.message),
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        mensajeError: 'Ocurrió un error inesperado. Intentá nuevamente.',
      );
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

  String _mensajeAuthLegible(String mensajeOriginal) {
    if (mensajeOriginal.toLowerCase().contains('invalid login credentials')) {
      return 'Cédula o contraseña incorrecta.';
    }
    return mensajeOriginal;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);