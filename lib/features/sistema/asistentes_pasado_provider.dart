import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'carga_alumnos_csv.dart';
import 'carga_alumnos_provider.dart';

/// Asistentes de los eventos cargados como pasados (fase 8, paso 8.3,
/// solo superadmin; script 22).
///
/// Se cargan sin horas: el servidor registra entrada = hora de inicio y
/// salida = hora de fin. Dos formas: elegir alumnos de la lista o subir el
/// CSV de la fase 6. Los alumnos del CSV que no existen se crean antes con
/// la Edge Function `alta-masiva-alumnos` (si el superadmin lo confirma).

/// Máximo de asistentes por carga (también lo exige el servidor).
const maxAsistentesPorCarga = 300;

/// Máximo de resultados de la búsqueda en la lista.
const limiteBusquedaAlumnos = 200;

final _reCi = RegExp(r'^\d{4,10}$');
final _reCorreo = RegExp(r'^[a-z0-9._-]+@uninorte\.edu\.py$');

// ---------------------------------------------------------------
// Datos del evento
// ---------------------------------------------------------------

class ResumenEventoPasado {
  final String eventoId;
  final String nombre;
  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final int horasOtorgadas;
  final int? cuposMaximos; // null = sin límite
  final int? cuposDisponibles; // null = sin límite
  final int inscriptos;
  final int asistentesCompletos;

  /// Nombres de las carreras habilitadas (incluye las desactivadas).
  final List<String> carreras;

  const ResumenEventoPasado({
    required this.eventoId,
    required this.nombre,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.horasOtorgadas,
    required this.cuposMaximos,
    required this.cuposDisponibles,
    required this.inscriptos,
    required this.asistentesCompletos,
    required this.carreras,
  });

  bool get sinLimite => cuposMaximos == null;

  factory ResumenEventoPasado.fromMap(Map<String, dynamic> m) =>
      ResumenEventoPasado(
        eventoId: m['evento_id'] as String,
        nombre: m['nombre'] as String,
        fecha: DateTime.parse(m['fecha'] as String),
        horaInicio: m['hora_inicio'] as String,
        horaFin: m['hora_fin'] as String,
        horasOtorgadas: (m['horas_otorgadas'] as num).toInt(),
        cuposMaximos: (m['cupos_maximos'] as num?)?.toInt(),
        cuposDisponibles: (m['cupos_disponibles'] as num?)?.toInt(),
        inscriptos: (m['inscriptos'] as num?)?.toInt() ?? 0,
        asistentesCompletos: (m['asistentes_completos'] as num?)?.toInt() ?? 0,
        carreras: ((m['carreras'] as List?) ?? const [])
            .map((c) => c as String)
            .toList(),
      );
}

final resumenEventoPasadoProvider = FutureProvider.autoDispose
    .family<ResumenEventoPasado, String>((ref, eventoId) async {
  try {
    final r = await supabase.rpc('resumen_evento_pasado', params: {
      'p_evento_id': eventoId,
    });
    return ResumenEventoPasado.fromMap(r as Map<String, dynamic>);
  } on PostgrestException catch (e) {
    throw AsistentesException(e.message);
  } catch (_) {
    throw const AsistentesException(
      'No se pudo conectar con el servidor. Revisá tu conexión.',
    );
  }
});

// ---------------------------------------------------------------
// Lista y carga
// ---------------------------------------------------------------

/// Alumno que se puede cargar como asistente.
class AlumnoElegible {
  final String id;
  final String nombre;
  final String ci;
  final String carrera;

  /// Ya está inscripto sin asistencia completa (se completará).
  final bool inscripto;

  const AlumnoElegible({
    required this.id,
    required this.nombre,
    required this.ci,
    required this.carrera,
    required this.inscripto,
  });

  factory AlumnoElegible.fromMap(Map<String, dynamic> m) => AlumnoElegible(
        id: m['usuario_id'] as String,
        nombre: m['nombre_completo'] as String? ?? '',
        ci: m['ci'] as String? ?? '',
        carrera: m['carrera'] as String? ?? '',
        inscripto: m['inscripto'] as bool? ?? false,
      );
}

/// Resultado de un alumno en cargar_asistentes_evento_pasado.
class ResultadoAsistente {
  final String usuarioId;
  final String resultado; // agregado | completado | ya_estaba | rechazado
  final String? detalle;

  const ResultadoAsistente({
    required this.usuarioId,
    required this.resultado,
    required this.detalle,
  });

  bool get cargado => resultado == 'agregado' || resultado == 'completado';

  String get legible => switch (resultado) {
        'agregado' => 'Agregado',
        'completado' => 'Asistencia completada',
        'ya_estaba' => 'Ya estaba cargado',
        'rechazado' => 'Rechazado',
        _ => resultado,
      };

  factory ResultadoAsistente.fromMap(Map<String, dynamic> m) =>
      ResultadoAsistente(
        usuarioId: m['usuario_id'] as String,
        resultado: m['resultado'] as String? ?? '',
        detalle: m['detalle'] as String?,
      );
}

/// Error con mensaje listo para mostrar al usuario.
class AsistentesException implements Exception {
  final String mensaje;
  const AsistentesException(this.mensaje);

  @override
  String toString() => mensaje;
}

class AsistentesPasadoService {
  AsistentesPasadoService._();

  static const _sinConexion = AsistentesException(
    'No se pudo conectar con el servidor. Revisá tu conexión.',
  );

  /// Alumnos activos de las carreras habilitadas sin asistencia completa.
  static Future<List<AlumnoElegible>> buscar(
    String eventoId,
    String busqueda,
  ) async {
    try {
      final filas = await supabase.rpc('alumnos_para_evento_pasado', params: {
        'p_evento_id': eventoId,
        'p_busqueda': busqueda.trim().isEmpty ? null : busqueda.trim(),
        'p_limite': limiteBusquedaAlumnos,
      });
      return (filas as List)
          .map((f) => AlumnoElegible.fromMap(f as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AsistentesException(e.message);
    } catch (_) {
      throw _sinConexion;
    }
  }

  /// Carga los asistentes (todo o nada si se supera el cupo).
  static Future<List<ResultadoAsistente>> cargar(
    String eventoId,
    List<String> usuarioIds,
    String motivo,
  ) async {
    try {
      final filas =
          await supabase.rpc('cargar_asistentes_evento_pasado', params: {
        'p_evento_id': eventoId,
        'p_usuario_ids': usuarioIds,
        'p_motivo': motivo,
      });
      return (filas as List)
          .map((f) => ResultadoAsistente.fromMap(f as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AsistentesException(e.message);
    } catch (_) {
      throw _sinConexion;
    }
  }
}

// ---------------------------------------------------------------
// CSV: clasificación de las filas
// ---------------------------------------------------------------

enum EstadoFilaAsistente {
  /// Alumno registrado y activo: se agrega como asistente.
  seAgrega,

  /// Alumno registrado con la cuenta desactivada: se agrega solo si se
  /// elige reactivarla.
  desactivado,

  /// No está registrado: se crea y se agrega solo si se confirma.
  noRegistrado,

  error,
}

/// Fila del CSV de asistentes. [reactivar] lo elige el superadmin; el
/// resultado final se completa al terminar la carga.
class FilaAsistente {
  final FilaCsv datos;
  final EstadoFilaAsistente estado;
  final String? error;
  final UsuarioExistente? existente;

  bool reactivar = false; // por defecto: no reactivar

  /// Resultado final para la pantalla y el informe.
  String? resultado;
  String? detalle;

  FilaAsistente({
    required this.datos,
    required this.estado,
    this.error,
    this.existente,
  });

  /// Fila para la Edge Function alta-masiva-alumnos (se envían todas, como
  /// en la fase 6, para que el lote quede completo en la auditoría).
  Map<String, dynamic> aPayload({required bool registrarNuevos}) {
    final base = <String, dynamic>{
      'fila': datos.numero,
      'ci': datos.ci,
      'nombre_completo': datos.nombre,
      'correo': datos.correo,
      'carrera': datos.carrera,
      'horas_requeridas': datos.horas,
    };
    return switch (estado) {
      EstadoFilaAsistente.error => {
          ...base,
          'accion': 'omitir',
          'rechazo_previo': error,
        },
      EstadoFilaAsistente.seAgrega => {...base, 'accion': 'omitir'},
      EstadoFilaAsistente.desactivado => {
          ...base,
          'accion': 'omitir',
          'reactivar': reactivar,
        },
      EstadoFilaAsistente.noRegistrado => {
          ...base,
          'accion': registrarNuevos ? 'crear' : 'omitir',
        },
    };
  }
}

/// Clasifica las filas del CSV para cargarlas como asistentes.
/// - Alumno registrado: vale su carrera REGISTRADA, que debe estar
///   habilitada en el evento. Sus datos no se modifican.
/// - Alumno nuevo: mismas validaciones que la fase 6 y, además, la
///   carrera del archivo debe estar habilitada en el evento.
List<FilaAsistente> clasificarFilasAsistentes({
  required List<FilaCsv> filas,
  required Set<String> carrerasOficiales, // activas
  required Set<String> carrerasEvento,
  required List<UsuarioExistente> existentes,
}) {
  final porCi = {for (final u in existentes) u.ci: u};
  final porCorreo = {for (final u in existentes) u.correo.toLowerCase(): u};

  // Repetidos dentro del archivo: todas las filas involucradas son error.
  final conteoCi = <String, int>{};
  final conteoCorreo = <String, int>{};
  for (final f in filas) {
    if (f.ci.isNotEmpty) conteoCi[f.ci] = (conteoCi[f.ci] ?? 0) + 1;
    final correo = f.correo.toLowerCase();
    if (correo.isNotEmpty) {
      conteoCorreo[correo] = (conteoCorreo[correo] ?? 0) + 1;
    }
  }

  FilaAsistente conError(FilaCsv f, String mensaje) =>
      FilaAsistente(datos: f, estado: EstadoFilaAsistente.error, error: mensaje);

  return filas.map((f) {
    final correo = f.correo.toLowerCase();

    if (!_reCi.hasMatch(f.ci)) {
      return conError(f, 'La C.I. debe tener entre 4 y 10 dígitos, sin puntos');
    }
    if ((conteoCi[f.ci] ?? 0) > 1) {
      return conError(f, 'C.I. repetida en el archivo');
    }
    if (correo.isNotEmpty && (conteoCorreo[correo] ?? 0) > 1) {
      return conError(f, 'Correo repetido en el archivo');
    }

    // --- Alumno registrado ---
    final u = porCi[f.ci];
    if (u != null) {
      if (u.rol != 'alumno') {
        return conError(
            f, 'La C.I. pertenece a un ${u.rolLegible}; no se puede cargar');
      }
      if (!carrerasEvento.contains(u.carrera)) {
        return conError(
          f,
          'Su carrera registrada (${u.carrera}) no está habilitada en este '
          'evento',
        );
      }
      return FilaAsistente(
        datos: f,
        estado: u.activo
            ? EstadoFilaAsistente.seAgrega
            : EstadoFilaAsistente.desactivado,
        existente: u,
      );
    }

    // --- Alumno no registrado ---
    final datosError =
        validarDatosAlumno(f.nombre, f.carrera, f.horas, carrerasOficiales);
    if (datosError != null) return conError(f, datosError);
    if (!carrerasEvento.contains(f.carrera.trim())) {
      return conError(
          f, 'La carrera "${f.carrera}" no está habilitada en este evento');
    }
    if (!_reCorreo.hasMatch(correo)) {
      return conError(
          f, 'El correo debe ser válido y del dominio @uninorte.edu.py');
    }
    final otro = porCorreo[correo];
    if (otro != null) {
      return conError(f, 'El correo ya lo usa la C.I. ${otro.ci}');
    }
    return FilaAsistente(datos: f, estado: EstadoFilaAsistente.noRegistrado);
  }).toList();
}