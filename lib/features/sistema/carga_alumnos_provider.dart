import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'carga_alumnos_csv.dart';

/// Carga masiva de alumnos por CSV (fase 6, solo superadmin).
///
/// Flujo: la app lee el CSV, consulta las coincidencias con
/// `verificar_carga_alumnos` (script 18), arma la vista previa y envía las
/// filas en tandas de 50 a la Edge Function `alta-masiva-alumnos`, que
/// vuelve a validar todo y registra cada fila en el detalle del lote.

/// Filas por tanda enviada a la Edge Function.
const filasPorTanda = 50;

/// Sufijo de la clave inicial (decisión de Kevin: C.I. + "abc").
const sufijoClaveInicial = 'abc';

final _reCi = RegExp(r'^\d{4,10}$');
final _reCorreo = RegExp(r'^[a-z0-9._-]+@uninorte\.edu\.py$');
final _reHoras = RegExp(r'^\d{1,3}$');

/// Usuario ya registrado cuya C.I. o correo coincide con el archivo.
class UsuarioExistente {
  final String id;
  final String ci;
  final String nombreCompleto;
  final String correo;
  final String carrera;
  final int? horasRequeridas;
  final String rol;
  final bool activo;

  const UsuarioExistente({
    required this.id,
    required this.ci,
    required this.nombreCompleto,
    required this.correo,
    required this.carrera,
    required this.horasRequeridas,
    required this.rol,
    required this.activo,
  });

  String get rolLegible => switch (rol) {
        'alumno' => 'alumno',
        'admin' => 'administrador',
        'superadmin' => 'superadmin',
        'validador' => 'validador',
        _ => rol,
      };

  factory UsuarioExistente.fromMap(Map<String, dynamic> m) => UsuarioExistente(
        id: m['usuario_id'] as String,
        ci: m['ci'] as String? ?? '',
        nombreCompleto: m['nombre_completo'] as String? ?? '',
        correo: m['correo'] as String? ?? '',
        carrera: m['carrera'] as String? ?? '',
        horasRequeridas: (m['horas_requeridas'] as num?)?.toInt(),
        rol: m['rol'] as String? ?? '',
        activo: m['activo'] as bool? ?? false,
      );
}

enum EstadoFila { nuevo, existente, error }

enum AccionExistente { omitir, actualizar }

/// Fila de la vista previa. [accion] y [reactivar] los elige el superadmin
/// (solo para filas en estado `existente`).
class FilaPrevia {
  final FilaCsv datos;
  final EstadoFila estado;
  final String? error;
  final String? aviso;
  final UsuarioExistente? existente;

  /// Una C.I. existente solo se puede actualizar si los datos son válidos.
  final bool puedeActualizar;

  AccionExistente accion = AccionExistente.omitir; // por defecto: omitir
  bool reactivar = false; // por defecto: no reactivar

  FilaPrevia({
    required this.datos,
    required this.estado,
    this.error,
    this.aviso,
    this.existente,
    this.puedeActualizar = false,
  });

  bool get existenteDesactivado => existente != null && !existente!.activo;

  /// Datos que se envían a la Edge Function.
  Map<String, dynamic> aPayload() {
    final base = <String, dynamic>{
      'fila': datos.numero,
      'ci': datos.ci,
      'nombre_completo': datos.nombre,
      'correo': datos.correo,
      'carrera': datos.carrera,
      'horas_requeridas': datos.horas,
    };
    switch (estado) {
      case EstadoFila.error:
        // Se registra en el lote como rechazada, sin procesarla.
        return {...base, 'accion': 'omitir', 'rechazo_previo': error};
      case EstadoFila.nuevo:
        return {...base, 'accion': 'crear'};
      case EstadoFila.existente:
        final actualizar =
            accion == AccionExistente.actualizar && puedeActualizar;
        return {
          ...base,
          'accion': actualizar ? 'actualizar' : 'omitir',
          'reactivar': reactivar && existenteDesactivado,
        };
    }
  }
}

/// Nombre sin espacios dobles (igual que el servidor).
String normalizarNombre(String nombre) =>
    nombre.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Nombre, carrera y horas (mismas reglas que el servidor y editar_usuario).
String? validarDatosAlumno(
  String nombre,
  String carrera,
  String horas,
  Set<String> carreras,
) {
  if (normalizarNombre(nombre).length < 3) return 'Falta el nombre completo';
  if (!carreras.contains(carrera.trim())) {
    return carrera.trim().isEmpty
        ? 'Falta la carrera'
        : 'La carrera "$carrera" no está en la lista oficial';
  }
  if (!_reHoras.hasMatch(horas)) {
    return 'Las horas requeridas deben ser un número entero';
  }
  final h = int.parse(horas);
  if (h < 1 || h > 500) return 'Las horas requeridas deben estar entre 1 y 500';
  return null;
}

/// Clasifica cada fila: nueva, C.I. existente (omitir/actualizar) o error.
List<FilaPrevia> clasificarFilas({
  required List<FilaCsv> filas,
  required Set<String> carreras,
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
    if (correo.isNotEmpty) conteoCorreo[correo] = (conteoCorreo[correo] ?? 0) + 1;
  }

  FilaPrevia conError(FilaCsv f, String mensaje) =>
      FilaPrevia(datos: f, estado: EstadoFila.error, error: mensaje);

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

    final datosError = validarDatosAlumno(f.nombre, f.carrera, f.horas, carreras);

    // --- C.I. ya registrada ---
    final u = porCi[f.ci];
    if (u != null) {
      if (u.rol != 'alumno') {
        return conError(
            f, 'La C.I. pertenece a un ${u.rolLegible}; no se puede cargar');
      }
      final avisos = <String>[
        if (datosError != null) 'Solo se puede omitir: $datosError',
        if (correo != u.correo.toLowerCase())
          'El correo del archivo es distinto al registrado; no se cambia',
      ];
      return FilaPrevia(
        datos: f,
        estado: EstadoFila.existente,
        existente: u,
        puedeActualizar: datosError == null,
        aviso: avisos.isEmpty ? null : avisos.join('. '),
      );
    }

    // --- C.I. nueva ---
    if (datosError != null) return conError(f, datosError);
    if (!_reCorreo.hasMatch(correo)) {
      return conError(f, 'El correo debe ser válido y del dominio @uninorte.edu.py');
    }
    final otro = porCorreo[correo];
    if (otro != null) {
      return conError(f, 'El correo ya lo usa la C.I. ${otro.ci}');
    }
    return FilaPrevia(datos: f, estado: EstadoFila.nuevo);
  }).toList();
}

/// Resultado de una fila, devuelto por la Edge Function.
class ResultadoFila {
  final int fila;
  final String resultado; // creado | actualizado | omitido | rechazado
  final bool reactivado;
  final String? error;

  const ResultadoFila({
    required this.fila,
    required this.resultado,
    required this.reactivado,
    required this.error,
  });

  String get resultadoLegible => switch (resultado) {
        'creado' => 'Creado',
        'actualizado' => 'Actualizado',
        'omitido' => 'Omitido',
        'rechazado' => 'Rechazado',
        _ => resultado,
      };

  factory ResultadoFila.fromMap(Map<String, dynamic> m) => ResultadoFila(
        fila: (m['fila'] as num).toInt(),
        resultado: m['resultado'] as String? ?? '',
        reactivado: m['reactivado'] as bool? ?? false,
        error: m['error'] as String?,
      );
}

class RespuestaTanda {
  final String cargaId;
  final List<ResultadoFila> resultados;
  const RespuestaTanda({required this.cargaId, required this.resultados});
}

/// Error con mensaje listo para mostrar al usuario.
class CargaAlumnosException implements Exception {
  final String mensaje;
  const CargaAlumnosException(this.mensaje);

  @override
  String toString() => mensaje;
}

const _sinConexion = CargaAlumnosException(
  'No se pudo conectar con el servidor. Revisá tu conexión.',
);

class CargaAlumnosService {
  CargaAlumnosService._();

  /// Usuarios cuya C.I. o correo coincide con alguna fila (script 18).
  static Future<List<UsuarioExistente>> verificar(List<FilaCsv> filas) async {
    final cis = filas.map((f) => f.ci).where(_reCi.hasMatch).toSet().toList();
    final correos = filas
        .map((f) => f.correo.toLowerCase())
        .where(_reCorreo.hasMatch)
        .toSet()
        .toList();

    try {
      final respuesta = await supabase.rpc('verificar_carga_alumnos', params: {
        'p_cis': cis,
        'p_correos': correos,
      });
      return (respuesta as List)
          .map((m) => UsuarioExistente.fromMap(m as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw CargaAlumnosException(e.message);
    } catch (_) {
      throw _sinConexion;
    }
  }

  /// Envía una tanda. Reenviar la misma tanda es seguro: el servidor no
  /// reprocesa las filas que ya registró.
  static Future<RespuestaTanda> enviarTanda({
    required String? cargaId,
    required String nombreArchivo,
    required int totalFilas,
    required bool ultima,
    required List<Map<String, dynamic>> filas,
  }) async {
    try {
      final respuesta = await supabase.functions.invoke(
        'alta-masiva-alumnos',
        body: {
          'carga_id': ?cargaId, // falta en la primera tanda
          'nombre_archivo': nombreArchivo,
          'total_filas': totalFilas,
          'ultima_tanda': ultima,
          'filas': filas,
        },
      );
      final data = respuesta.data;
      if (data is! Map || data['exito'] != true) {
        throw CargaAlumnosException(
          data is Map && data['error'] is String
              ? data['error'] as String
              : 'Respuesta inválida del servidor',
        );
      }
      return RespuestaTanda(
        cargaId: data['carga_id'] as String,
        resultados: (data['resultados'] as List)
            .map((m) => ResultadoFila.fromMap(m as Map<String, dynamic>))
            .toList(),
      );
    } on CargaAlumnosException {
      rethrow;
    } on FunctionException catch (e) {
      final d = e.details;
      throw CargaAlumnosException(
        d is Map && d['error'] is String
            ? d['error'] as String
            : 'El servidor rechazó la tanda (código ${e.status})',
      );
    } catch (_) {
      throw _sinConexion;
    }
  }
}