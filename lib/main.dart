import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/router.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.init();
  await initializeDateFormatting('es');

  // Cargamos la sesión persistida (si existe) ANTES de pintar la
  // primera pantalla, para que el redirect del router decida
  // correctamente entre login / home-estudiante / home-docente
  // sin parpadeo hacia el login.
  await SessionSnapshot.instance.cargarDesdeStorage();

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