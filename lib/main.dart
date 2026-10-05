import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/router.dart';
import 'core/secure_storage.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SupabaseConfig.init();
    await initializeDateFormatting('es');

    await SessionSnapshot.instance.cargarDesdeStorage();

    // Si el snapshot dice "autenticado" pero Supabase no tiene sesión
    // (token vencido, storage limpiado), se descarta.
    if (SessionSnapshot.instance.autenticado &&
        supabase.auth.currentSession == null) {
      await SecureStorageService.instance.limpiarSesion();
      SessionSnapshot.instance.limpiar();
    }
  } catch (e) {
    runApp(_ErrorDeInicio(mensaje: e.toString()));
    return;
  }

  runApp(const ProviderScope(child: UniNorteApp()));
}

class UniNorteApp extends StatelessWidget {
  const UniNorteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'UniNorte Extensiones',
      debugShowCheckedModeBanner: false,
      theme: UniNorteTheme.lightTheme,
      routerConfig: appRouter,
    );
  }
}

/// Se muestra si falla el arranque, en lugar de una pantalla en blanco.
class _ErrorDeInicio extends StatelessWidget {
  final String mensaje;
  const _ErrorDeInicio({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: UniNorteColors.azulMarino,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'No se pudo iniciar la aplicación',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  mensaje,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}