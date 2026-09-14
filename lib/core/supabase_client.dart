import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuración e inicialización global de Supabase
class SupabaseConfig {
  SupabaseConfig._();

  static const String _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String _anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Dominio institucional fijo usado para resolver C.I. -> correo.
  static const String dominioInstitucional = '@uninorte.edu.py';

  /// Debe llamarse una sola vez en `main()` antes de `runApp`.
  static Future<void> init() async {
    assert(
      _url.isNotEmpty && _anonKey.isNotEmpty,
      'SUPABASE_URL y SUPABASE_ANON_KEY deben definirse vía --dart-define',
    );

    await Supabase.initialize(
      url: _url,
      anonKey: _anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }
}

/// Acceso rápido al cliente Supabase desde cualquier parte de la app.
final supabase = Supabase.instance.client;