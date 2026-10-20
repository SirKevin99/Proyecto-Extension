import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Administración de carreras y de sus firmantes (solo superadmin, fase 7).
/// Desde el script 20 cada carrera guarda su facultad, su decano/a y su
/// director/a; se cargan con la tabla editable (`guardar_firmantes`).

class CarreraAdmin {
  final int id;
  final String nombre;
  final bool activa;
  final String? facultad;
  final String? decanoNombre;
  final String? decanoCargo; // 'Decano' | 'Decana'
  final String? directorNombre;
  final String? directorCargo; // Director/a | Coordinador/a
  final int alumnosActivos;
  final int eventosVigentes;
  final int certificadosPendientes;

  const CarreraAdmin({
    required this.id,
    required this.nombre,
    required this.activa,
    required this.facultad,
    required this.decanoNombre,
    required this.decanoCargo,
    required this.directorNombre,
    required this.directorCargo,
    required this.alumnosActivos,
    required this.eventosVigentes,
    required this.certificadosPendientes,
  });

  /// Sin facultad, decano/a o director/a: no se emiten certificados.
  bool get faltanFirmantes =>
      facultad == null || decanoNombre == null || directorNombre == null;

  factory CarreraAdmin.fromMap(Map<String, dynamic> m) => CarreraAdmin(
        id: (m['id'] as num).toInt(),
        nombre: m['nombre'] as String,
        activa: m['activa'] as bool,
        facultad: m['facultad'] as String?,
        decanoNombre: m['decano_nombre'] as String?,
        decanoCargo: m['decano_cargo'] as String?,
        directorNombre: m['director_nombre'] as String?,
        directorCargo: m['director_cargo'] as String?,
        alumnosActivos: (m['alumnos_activos'] as num?)?.toInt() ?? 0,
        eventosVigentes: (m['eventos_vigentes'] as num?)?.toInt() ?? 0,
        certificadosPendientes:
            (m['certificados_pendientes'] as num?)?.toInt() ?? 0,
      );
}

/// Una fila de la tabla de firmantes tal como se envía a guardar.
/// [id] null = carrera nueva. Los vacíos se envían como null.
class FilaFirmantes {
  final int? id;
  final String nombre;
  final String? facultad;
  final String? decanoNombre;
  final String? decanoCargo;
  final String? directorNombre;
  final String? directorCargo;

  const FilaFirmantes({
    required this.id,
    required this.nombre,
    required this.facultad,
    required this.decanoNombre,
    required this.decanoCargo,
    required this.directorNombre,
    required this.directorCargo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'facultad': facultad,
        'decano_nombre': decanoNombre,
        'decano_cargo': decanoCargo,
        'director_nombre': directorNombre,
        'director_cargo': directorCargo,
      };
}

class ResultadoFirmantes {
  final int creadas;
  final int actualizadas;
  final int usuariosRenombrados;
  final int certificadosEmitidos;

  const ResultadoFirmantes({
    required this.creadas,
    required this.actualizadas,
    required this.usuariosRenombrados,
    required this.certificadosEmitidos,
  });

  factory ResultadoFirmantes.fromMap(Map<String, dynamic> m) =>
      ResultadoFirmantes(
        creadas: (m['creadas'] as num?)?.toInt() ?? 0,
        actualizadas: (m['actualizadas'] as num?)?.toInt() ?? 0,
        usuariosRenombrados: (m['usuarios_renombrados'] as num?)?.toInt() ?? 0,
        certificadosEmitidos:
            (m['certificados_emitidos'] as num?)?.toInt() ?? 0,
      );
}

/// Datos para la alerta previa a desactivar (resumen_carrera, script 19).
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

/// Todas las carreras (activas primero) con firmantes y totales.
final carrerasAdminProvider =
    FutureProvider.autoDispose<List<CarreraAdmin>>((ref) async {
  final filas = await CarrerasAdminService._llamar(
      () => supabase.rpc('listar_carreras_admin'));
  return (filas as List)
      .map((f) => CarreraAdmin.fromMap(f as Map<String, dynamic>))
      .toList();
});

class CarrerasAdminService {
  CarrerasAdminService._();

  /// Ejecuta la llamada y traduce los errores a un mensaje en español.
  /// Los RAISE EXCEPTION de los scripts ya vienen redactados para el usuario.
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

  /// Guarda las filas nuevas o modificadas de la tabla (todas o ninguna).
  static Future<ResultadoFirmantes> guardarFirmantes(
      List<FilaFirmantes> filas) async {
    final r = await _llamar(() => supabase.rpc('guardar_firmantes', params: {
          'p_filas': filas.map((f) => f.toJson()).toList(),
        }));
    return ResultadoFirmantes.fromMap(r as Map<String, dynamic>);
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