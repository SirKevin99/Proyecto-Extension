import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuración y acceso centralizado al cliente de Supabase.
///
/// Las credenciales se inyectan vía `--dart-define` para no exponer
/// secretos en el repositorio:
///
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=xxxx
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
  if (_url.isEmpty || _anonKey.isEmpty) {
    throw StateError(
      'Faltan SUPABASE_URL y SUPABASE_ANON_KEY. '
      'Ejecutá la app con --dart-define para ambas.',
    );
  }

  await Supabase.initialize(
    url: _url,
    publishableKey: _anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}
}

/// Acceso rápido al cliente Supabase desde cualquier parte de la app.
///
/// Uso: `supabase.from('eventos').select()`
final SupabaseClient supabase = Supabase.instance.client;