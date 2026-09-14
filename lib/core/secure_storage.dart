import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacenamiento seguro de tokens de sesión y datos sensibles.
///
/// Prohibido usar `shared_preferences` para JWTs (requerimiento de seguridad).
class SecureStorageService {
  SecureStorageService._();

  static final SecureStorageService instance = SecureStorageService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _keyAccessToken = 'sb_access_token';
  static const String _keyRefreshToken = 'sb_refresh_token';
  static const String _keyUserCi = 'user_ci';
  static const String _keyUserRol = 'user_rol';

  // ---------------------------------------------------------------
  // Tokens de sesión
  // ---------------------------------------------------------------

  Future<void> guardarTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
  }

  Future<String?> obtenerAccessToken() => _storage.read(key: _keyAccessToken);

  Future<String?> obtenerRefreshToken() =>
      _storage.read(key: _keyRefreshToken);

  // ---------------------------------------------------------------
  // Datos de sesión auxiliares
  // ---------------------------------------------------------------

  Future<void> guardarDatosUsuario({
    required String ci,
    required String rol,
  }) async {
    await _storage.write(key: _keyUserCi, value: ci);
    await _storage.write(key: _keyUserRol, value: rol);
  }

  Future<String?> obtenerRol() => _storage.read(key: _keyUserRol);

  Future<String?> obtenerCi() => _storage.read(key: _keyUserCi);

  // ---------------------------------------------------------------
  // Limpieza total (logout)
  // ---------------------------------------------------------------

  Future<void> limpiarSesion() async {
    await _storage.deleteAll();
  }
}