import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacenamiento seguro de tokens de sesión y datos sensibles.
///
/// Prohibido usar `shared_preferences` para JWTs (ver requerimiento
/// de seguridad del proyecto). Esta clase es el único punto de acceso
/// permitido al almacenamiento persistente de credenciales.
class SecureStorageService {
  SecureStorageService._();

  static final SecureStorageService instance = SecureStorageService._();

 final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _keyAccessToken = 'sb_access_token';
  static const String _keyRefreshToken = 'sb_refresh_token';
  static const String _keyUserCi = 'user_ci';
  static const String _keyUserRol = 'user_rol';
  static const String _keyCarnet = 'carnet_alumno';

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
  // Datos de sesión auxiliares (no sensibles, pero útiles para
  // guardias de router y UI condicional por rol)
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
  // Carnet del alumno (fase 7): últimos datos leídos del servidor,
  // en JSON, para mostrar el carnet sin conexión. Se borra al cerrar
  // sesión junto con todo lo demás.
  // ---------------------------------------------------------------

  Future<void> guardarCarnet(String json) =>
      _storage.write(key: _keyCarnet, value: json);

  Future<String?> obtenerCarnet() => _storage.read(key: _keyCarnet);

  // ---------------------------------------------------------------
  // Limpieza total (logout)
  // ---------------------------------------------------------------

  Future<void> limpiarSesion() async {
    await _storage.deleteAll();
  }
}