import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/home/home_admin_screen.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/recuperar_password_screen.dart';
import '../features/eventos/detalle_evento_screen.dart';
import '../features/eventos/lista_eventos_screen.dart';
import '../features/home/home_estudiante_screen.dart';
import 'secure_storage.dart';

/// Rutas nombradas de la app. Las rutas de cada rol viven bajo un
/// prefijo propio para poder protegerlas por prefijo en el redirect.
class AppRoutes {
  AppRoutes._();

  // --- Públicas ---
  static const String login = '/login';
  static const String recuperarPassword = '/recuperar-password';
  static const String validadorHash = '/validar-certificado';

  // --- Alumno ---
  static const String homeEstudiante = '/home-estudiante';
  static const String listaEventos = '/eventos';
  static const String detalleEvento = '/eventos/:id';
  static const String marcarAsistencia = '/eventos/:id/marcar';
  static const String certificados = '/certificados';
  static const String carnetQr = '/carnet';
  static const String perfil = '/perfil';

  // --- Administrador (prefijo /admin) ---
  static const String homeAdmin = '/admin';
  static const String crearEvento = '/admin/eventos/crear';
  static const String gestionAsistencia = '/admin/eventos/:id/asistencia';
  static const String altaUsuario = '/admin/usuarios/nuevo';
  static const String altaValidador = '/admin/validadores/nuevo';

  // --- Validador temporal (prefijo /validador) ---
  static const String homeValidador = '/validador';

  // Helpers para evitar replaceFirst(':id', ...) repetido en las pantallas.
  static String detalleEventoPath(String id) => '/eventos/$id';
  static String marcarAsistenciaPath(String id) => '/eventos/$id/marcar';
  static String gestionAsistenciaPath(String id) =>
      '/admin/eventos/$id/asistencia';
}

/// Roles válidos, según el CHECK constraint de la tabla `usuarios`.
enum RolUsuario { alumno, admin, validador }

RolUsuario? rolDesdeString(String? valor) {
  switch (valor) {
    case 'alumno':
      return RolUsuario.alumno;
    case 'admin':
      return RolUsuario.admin;
    case 'validador':
      return RolUsuario.validador;
    default:
      return null; // incluye 'docente' (rol eliminado)
  }
}

/// Copia en memoria de la sesión, porque el `redirect` de GoRouter es
/// síncrono y `flutter_secure_storage` es asíncrono.
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

/// Notifica a GoRouter cuándo re-evaluar el `redirect` (login / logout).
class AppRouterRefresh extends ChangeNotifier {
  static final AppRouterRefresh instance = AppRouterRefresh._();
  AppRouterRefresh._();

  void refrescar() => notifyListeners();
}

const Set<String> _rutasPublicas = {
  AppRoutes.login,
  AppRoutes.recuperarPassword,
  AppRoutes.validadorHash, // verificación pública de certificados
};

bool _esRuta(String ruta, String base) =>
    ruta == base || ruta.startsWith('$base/');

/// Roles autorizados para una ruta. `null` = sin restricción de rol.
Set<RolUsuario>? _rolesPermitidos(String ruta) {
  if (_esRuta(ruta, '/admin')) return {RolUsuario.admin};
  if (_esRuta(ruta, '/validador')) return {RolUsuario.validador};

  if (_esRuta(ruta, AppRoutes.homeEstudiante) ||
      _esRuta(ruta, AppRoutes.listaEventos) ||
      _esRuta(ruta, AppRoutes.certificados) ||
      _esRuta(ruta, AppRoutes.carnetQr) ||
      _esRuta(ruta, AppRoutes.perfil)) {
    return {RolUsuario.alumno};
  }
  return null;
}

String _homePorRol(RolUsuario rol) {
  switch (rol) {
    case RolUsuario.admin:
      return AppRoutes.homeAdmin;
    case RolUsuario.validador:
      return AppRoutes.homeValidador;
    case RolUsuario.alumno:
      return AppRoutes.homeEstudiante;
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.login,
  refreshListenable: AppRouterRefresh.instance,
  redirect: (context, state) {
    final session = SessionSnapshot.instance;
    final ruta = state.matchedLocation;
    final esPublica = _rutasPublicas.contains(ruta);

    // 1. Sin sesión: solo rutas públicas.
    if (!session.autenticado) {
      return esPublica ? null : AppRoutes.login;
    }

    // 2. Sesión con rol desconocido (ej. un 'docente' viejo): no se
    //    le da acceso a nada protegido.
    final rol = session.rol;
    if (rol == null) {
      return esPublica ? null : AppRoutes.login;
    }

    // 3. Ya autenticado en la pantalla de login: a su home.
    if (ruta == AppRoutes.login) {
      return _homePorRol(rol);
    }

    // 4. Guardia de rol por prefijo.
    final permitidos = _rolesPermitidos(ruta);
    if (permitidos != null && !permitidos.contains(rol)) {
      return _homePorRol(rol);
    }

    return null;
  },
  routes: [
    // ---------------- Públicas ----------------
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.recuperarPassword,
      builder: (context, state) => const RecuperarPasswordScreen(),
    ),
    GoRoute(
      path: AppRoutes.validadorHash,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Validador de certificados (módulo Certificados)',
      ),
    ),

    // ---------------- Alumno ----------------
    GoRoute(
      path: AppRoutes.homeEstudiante,
      builder: (context, state) => const HomeEstudianteScreen(),
    ),
    GoRoute(
      path: AppRoutes.listaEventos,
      builder: (context, state) => const ListaEventosScreen(),
    ),
    GoRoute(
      path: AppRoutes.detalleEvento,
      builder: (context, state) => DetalleEventoScreen(
        eventoId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: AppRoutes.marcarAsistencia,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Marcar asistencia (código / PIN)',
      ),
    ),
    GoRoute(
      path: AppRoutes.certificados,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Certificados (módulo Certificados)',
      ),
    ),
    GoRoute(
      path: AppRoutes.carnetQr,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Carnet QR (módulo Perfil)',
      ),
    ),
    GoRoute(
      path: AppRoutes.perfil,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Perfil (módulo Perfil)',
      ),
    ),

    // ---------------- Administrador ----------------
    GoRoute(
  path: AppRoutes.homeAdmin,
  builder: (context, state) => const HomeAdminScreen(),
),
    GoRoute(
      path: AppRoutes.crearEvento,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Crear evento (pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.gestionAsistencia,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Corrección de asistencia (pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.altaUsuario,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Alta de usuario (pendiente)',
      ),
    ),
    GoRoute(
      path: AppRoutes.altaValidador,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Alta de validador (pendiente)',
      ),
    ),

    // ---------------- Validador temporal ----------------
    GoRoute(
      path: AppRoutes.homeValidador,
      builder: (context, state) => const _PlaceholderScreen(
        titulo: 'Panel del validador: QR y PIN (pendiente)',
      ),
    ),
  ],
);

/// Pantalla temporal mientras no existen las screens reales.
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