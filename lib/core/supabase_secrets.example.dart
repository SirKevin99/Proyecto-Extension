/// Plantilla de credenciales. Para usar el proyecto:
///   1. Copiá este archivo como `supabase_secrets.dart` (misma carpeta).
///   2. Renombrá la clase a `SupabaseSecrets`.
///   3. Completá la URL y la clave publicable de tu proyecto Supabase.
///
/// `supabase_secrets.dart` está en .gitignore y no debe subirse nunca.
/// Jamás pongas la service_role key en el cliente.
class SupabaseSecretsExample {
  SupabaseSecretsExample._();

  static const String url = 'https://TU-PROYECTO.supabase.co';
  static const String anonKey = 'TU-CLAVE-PUBLICABLE';
}