import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Administración de carreras y facultades (solo superadmin, fase 7).
/// Todas las escrituras van por las RPC del script 19.

class CarreraAdmin {
  final int id;
  final String nombre;
  final bool activa;
  final int? facultadId;
  final String? facultad;
  final String? directorNombre;
  final String? directorCargo; // 'Director' | 'Directora'
  final int alumnosActivos;
  final int eventosVigentes;

  const CarreraAdmin({
    required this.id,
    required this.nombre,
    required this.activa,
    required this.facultadId,
    required this.facultad,
    required this.directorNombre,
    required this.directorCargo,
    required this.alumnosActivos,
    required this.eventosVigentes,
  });

  /// Sin facultad o sin director/a: el certificado no tendría firmantes.
  bool get faltanFirmantes => facultadId == null || directorNombre == null;

  factory CarreraAdmin.fromMap(Map<String, dynamic> m) => CarreraAdmin(
        id: (m['id'] as num).toInt(),
        nombre: m['nombre'] as String,
        activa: m['activa'] as bool,
        facultadId: (m['facultad_id'] as num?)?.toInt(),
        facultad: m['facultad'] as String?,
        directorNombre: m['director_nombre'] as String?,
        directorCargo: m['director_cargo'] as String?,
        alumnosActivos: (m['alumnos_activos'] as num?)?.toInt() ?? 0,
        eventosVigentes: (m['eventos_vigentes'] as num?)?.toInt() ?? 0,
      );
}

class Facultad {
  final int id;
  final String nombre;
  final String decanoNombre;
  final String decanoCargo; // 'Decano' | 'Decana'

  const Facultad({
    required this.id,
    required this.nombre,
    required this.decanoNombre,
    required this.decanoCargo,
  });

  factory Facultad.fromMap(Map<String, dynamic> m) => Facultad(
        id: (m['id'] as num).toInt(),
        nombre: m['nombre'] as String,
        decanoNombre: m['decano_nombre'] as String,
        decanoCargo: m['decano_cargo'] as String,
      );
}

/// Datos para la alerta previa a desactivar (resumen_carrera).
class ResumenCarrera {
  final int alumnosActivos;
  final int adminsActivos;
  final int eventosVigentes;
  final int eventosSoloEstaCarrera;
  final List<String> muestraAlumnos; // "Nombre · C.I. 1234"
  final List<String> muestraEventos; // "Nombre · dd/mm/aaaa"

  const ResumenCarrera({
    required this.alumnosActivos,
    required this.adminsActivos,
    required this.eventosVigentes,
    required this.eventosSoloEstaCarrera,
    required this.muestraAlumnos,
    required this.muestraEventos,
  });

  factory ResumenCarrera.fromMap(Map<String, dynamic> m) {
    String fecha(String? iso) {
      final d = iso == null ? null : DateTime.tryParse(iso);
      if (d == null) return iso ?? '';
      String dos(int n) => n.toString().padLeft(2, '0');
      return '${dos(d.day)}/${dos(d.month)}/${d.year}';
    }

    final alumnos = (m['muestra_alumnos'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((a) => '${a['nombre']} · C.I. ${a['ci']}')
        .toList();
    final eventos = (m['muestra_eventos'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((e) => '${e['nombre']} · ${fecha(e['fecha'] as String?)}')
        .toList();

    return ResumenCarrera(
      alumnosActivos: (m['alumnos_activos'] as num?)?.toInt() ?? 0,
      adminsActivos: (m['admins_activos'] as num?)?.toInt() ?? 0,
      eventosVigentes: (m['eventos_vigentes'] as num?)?.toInt() ?? 0,
      eventosSoloEstaCarrera:
          (m['eventos_solo_esta_carrera'] as num?)?.toInt() ?? 0,
      muestraAlumnos: alumnos,
      muestraEventos: eventos,
    );
  }
}

class CarrerasException implements Exception {
  final String mensaje;
  const CarrerasException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Todas las carreras (activas primero) con totales.
final carrerasAdminProvider =
    FutureProvider.autoDispose<List<CarreraAdmin>>((ref) async {
  final filas = await CarrerasAdminService._llamar(
      () => supabase.rpc('listar_carreras_admin'));
  return (filas as List)
      .map((f) => CarreraAdmin.fromMap(f as Map<String, dynamic>))
      .toList();
});

/// Facultades ordenadas por nombre.
final facultadesProvider = FutureProvider.autoDispose<List<Facultad>>(
    (ref) => CarrerasAdminService.listarFacultades());

class CarrerasAdminService {
  CarrerasAdminService._();

  /// Ejecuta la llamada y traduce los errores a un mensaje en español.
  /// Los RAISE EXCEPTION del script 19 ya vienen redactados para el usuario.
  static Future<dynamic> _llamar(Future<dynamic> Function() llamada) async {
    try {
      return await llamada();
    } on PostgrestException catch (e) {
      throw CarrerasException(e.message.isNotEmpty
          ? e.message
          : 'No se pudo completar la operación');
    } catch (_) {
      throw const CarrerasException(
          'No se pudo conectar con el servidor. Revisá tu conexión.');
    }
  }

  static Future<List<Facultad>> listarFacultades() async {
    final filas = await _llamar(() => supabase
        .from('facultades')
        .select('id, nombre, decano_nombre, decano_cargo')
        .order('nombre'));
    return (filas as List)
        .map((f) => Facultad.fromMap(f as Map<String, dynamic>))
        .toList();
  }

  static Future<int> crearFacultad({
    required String nombre,
    required String decanoNombre,
    required String decanoCargo,
  }) async {
    final id = await _llamar(() => supabase.rpc('crear_facultad', params: {
          'p_nombre': nombre,
          'p_decano_nombre': decanoNombre,
          'p_decano_cargo': decanoCargo,
        }));
    return (id as num).toInt();
  }

  static Future<void> editarFacultad({
    required int id,
    required String nombre,
    required String decanoNombre,
    required String decanoCargo,
  }) async {
    await _llamar(() => supabase.rpc('editar_facultad', params: {
          'p_facultad_id': id,
          'p_nombre': nombre,
          'p_decano_nombre': decanoNombre,
          'p_decano_cargo': decanoCargo,
        }));
  }

  static Future<int> crearCarrera({
    required String nombre,
    required int facultadId,
    required String directorNombre,
    required String directorCargo,
  }) async {
    final id = await _llamar(() => supabase.rpc('crear_carrera', params: {
          'p_nombre': nombre,
          'p_facultad_id': facultadId,
          'p_director_nombre': directorNombre,
          'p_director_cargo': directorCargo,
        }));
    return (id as num).toInt();
  }

  /// Devuelve cuántos usuarios se actualizaron por el cambio de nombre
  /// (0 si el nombre no cambió).
  static Future<int> editarCarrera({
    required int id,
    required String nombre,
    required int facultadId,
    required String directorNombre,
    required String directorCargo,
  }) async {
    final n = await _llamar(() => supabase.rpc('editar_carrera', params: {
          'p_carrera_id': id,
          'p_nombre': nombre,
          'p_facultad_id': facultadId,
          'p_director_nombre': directorNombre,
          'p_director_cargo': directorCargo,
        }));
    return (n as num?)?.toInt() ?? 0;
  }

  static Future<ResumenCarrera> resumen(int id) async {
    final r = await _llamar(
        () => supabase.rpc('resumen_carrera', params: {'p_carrera_id': id}));
    return ResumenCarrera.fromMap(r as Map<String, dynamic>);
  }

  static Future<void> desactivar(int id) async {
    await _llamar(() =>
        supabase.rpc('desactivar_carrera', params: {'p_carrera_id': id}));
  }

  static Future<void> reactivar(int id) async {
    await _llamar(() =>
        supabase.rpc('reactivar_carrera', params: {'p_carrera_id': id}));
  }
}