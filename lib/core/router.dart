import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Importa la pantalla real de Login según tu estructura de carpetas
import '../features/auth/login_screen.dart';
import 'secure_storage.dart';

/// Rutas nombradas de la app. Usar estas constantes en vez de
/// strings sueltos para evitar errores de tipeo al navegar.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String recuperarPassword = '/recuperar-password';

  static const String homeEstudiante = '/home-estudiante';
  static const String homeDocente = '/home-docente';

  static const String listaEventos = '/eventos';
  static const String detalleEvento = '/eventos/:id';
  static const String crearEvento = '/eventos/crear';
  static const String gestionAsistencia = '/eventos/:id/asistencia';

  static const String certificados = '/certificados';
  static const String validadorHash = '/validar-certificado';

  static const String carnetQr = '/carnet';
  static const String perfil = '/perfil';
}

/// Roles válidos del sistema, según CHECK constraint de la tabla `usuarios`.
enum RolUsuario { alumno, docente, admin }

RolUsuario? rolDesdeString(String? valor) {
  switch (valor) {
    case 'alumno':
      return RolUsuario.alumno;
    case 'docente':
      return RolUsuario.docente;
    case 'admin':
      return RolUsuario.admin;
    default:
      return null;
  }
}

/// Router centralizado con guardias de autenticación y de rol.
///
/// La lógica de `redirect` es síncrona (requisito de GoRouter), por lo
/// que la sesión (token + rol) se resuelve una vez al arrancar la app
/// mediante [AppRouterRefresh] y se consulta acá vía [SecureStorageService]
/// cacheado en memoria a través de [SessionSnapshot].
class SessionSnapshot {
  SessionSnapshot._();
  static final SessionSnapshot instance = SessionSnapshot._();

  bool autenticado = false;
  RolUsuario? rol;

  Future<void> cargarDesdeStorage() async {
    final token = await SecureStorageService.instance.obtenerAccessToken();
    final rolGuardado = await SecureStorageService.instance.obtenerRol();

    autenticado = token != null && token.isNotEmpty;
    rol = rolDesdeString(rolGuardado);
  }

  void limpiar() {
    autenticado = false;
    rol = null;
  }
}

/// Notifica a GoRouter cuándo debe re-evaluar el `redirect`
/// (ej. tras login o logout).
class AppRouterRefresh extends ChangeNotifier {
  static final AppRouterRefresh instance = AppRouterRefresh._();
  AppRouterRefresh._();

  void refrescar() => notifyListeners();
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.login,
  refreshListenable: AppRouterRefresh.instance,
  redirect: (context, state) {
    final session = SessionSnapshot.instance;
    final rutaActual = state.matchedLocation;

    final rutasPublicas = {
      AppRoutes.login,
      AppRoutes.recuperarPassword,
      AppRoutes.validadorHash, // validación pública de certificados
    };

    final esRutaPublica = rutasPublicas.contains(rutaActual);

    // No autenticado intentando entrar a ruta protegida -> login
    if (!session.autenticado && !esRutaPublica) {
      return AppRoutes.login;
    }

    // Autenticado pero parado en login/recuperar -> mandar a su home
    if (session.autenticado && (rutaActual == AppRoutes.login)) {
      return _homePorRol(session.rol);
    }

    // Guardias específicas por rol para rutas de docente
    final rutasSoloDocente = {
      AppRoutes.homeDocente,
      AppRoutes.crearEvento,
      AppRoutes.gestionAsistencia,
    };

    if (session.autenticado &&
        rutasSoloDocente.contains(rutaActual) &&
        session.rol != RolUsuario.docente &&
        session.rol != RolUsuario.admin) {
      return _homePorRol(session.rol);
    }

    // Guardia: estudiante no puede entrar a home de docente y viceversa
    if (session.autenticado &&
        rutaActual == AppRoutes.homeEstudiante &&
        session.rol == RolUsuario.docente) {
      return AppRoutes.homeDocente;
    }

    return null; // sin redirección
  },
  routes: [
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.recuperarPassword,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Recuperar contraseña (módulo Auth pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.homeEstudiante,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Home Estudiante (módulo Home pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.homeDocente,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Home Docente (módulo Home pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.listaEventos,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Lista de Eventos (módulo Eventos pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.detalleEvento,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Detalle de Evento (módulo Eventos pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.crearEvento,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Crear Evento (módulo Eventos pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.gestionAsistencia,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Gestión de Asistencia (módulo Eventos pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.certificados,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Certificados (módulo Certificados pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.validadorHash,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Validador de Hash (módulo Certificados pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.carnetQr,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Carnet QR (módulo Perfil pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.perfil,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Perfil (módulo Perfil pendiente)',
      ),
    ),
  ],
);

String _homePorRol(RolUsuario? rol) {
  switch (rol) {
    case RolUsuario.docente:
    case RolUsuario.admin:
      return AppRoutes.homeDocente;
    case RolUsuario.alumno:
    case null:
      return AppRoutes.homeEstudiante;
  }
}

/// Pantalla temporal usada mientras no existen las screens reales.
/// Se reemplaza módulo por módulo según `orden_de_implementacion`.
class _PlaceholderScreen extends StatelessWidget {
  final String titulo;
  const _PlaceholderScreen({required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Center(child: Text(titulo)),
    );
  }
}