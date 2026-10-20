import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Filtro por origen de la auditoría (fase 5, solo superadmin).
/// 'carreras' incluye carreras y facultades (fase 7, script 19).
enum OrigenAuditoria {
  todos,
  usuarios,
  eventos,
  asistencias,
  validadores,
  carreras,
}

extension OrigenAuditoriaX on OrigenAuditoria {
  /// Valor que espera listar_auditoria (NULL = todos).
  String? get valor => this == OrigenAuditoria.todos ? null : name;

  String get etiqueta => switch (this) {
        OrigenAuditoria.todos => 'Todo',
        OrigenAuditoria.usuarios => 'Usuarios',
        OrigenAuditoria.eventos => 'Eventos',
        OrigenAuditoria.asistencias => 'Asistencias',
        OrigenAuditoria.validadores => 'Validadores',
        OrigenAuditoria.carreras => 'Carreras',
      };
}

/// Una fila de listar_auditoria (script 17).
class RegistroAuditoria {
  final String origen; // usuarios | eventos | asistencias | validadores | carreras
  final String accion; // alta | modificacion | baja | correccion | cambio_horario | restablecer_clave
  final String? entidad; // nombre del usuario, evento o "alumno · evento"
  final Map<String, dynamic> detalle;
  final String? motivo;
  final String? actorNombre; // NULL = sistema (acciones automáticas)
  final String? actorRol;
  final DateTime realizadoEn;

  const RegistroAuditoria({
    required this.origen,
    required this.accion,
    required this.entidad,
    required this.detalle,
    required this.motivo,
    required this.actorNombre,
    required this.actorRol,
    required this.realizadoEn,
  });

  factory RegistroAuditoria.fromMap(Map<String, dynamic> m) =>
      RegistroAuditoria(
        origen: m['origen'] as String,
        accion: m['accion'] as String,
        entidad: m['entidad'] as String?,
        detalle: (m['detalle'] as Map?)?.cast<String, dynamic>() ?? const {},
        motivo: m['motivo'] as String?,
        actorNombre: m['actor_nombre'] as String?,
        actorRol: m['actor_rol'] as String?,
        realizadoEn: DateTime.parse(m['realizado_en'] as String).toLocal(),
      );
}

/// Error con mensaje listo para mostrar al usuario.
class AuditoriaException implements Exception {
  final String mensaje;
  const AuditoriaException(this.mensaje);

  @override
  String toString() => mensaje;
}

class AuditoriaService {
  AuditoriaService._();

  static const int tamanoPagina = 50;
  static final DateFormat _formatoFecha = DateFormat('yyyy-MM-dd');

  /// [desde] y [hasta] son fechas de Paraguay, ambas inclusive.
  static Future<List<RegistroAuditoria>> listar({
    OrigenAuditoria origen = OrigenAuditoria.todos,
    DateTime? desde,
    DateTime? hasta,
    int offset = 0,
  }) async {
    try {
      final filas = await supabase.rpc('listar_auditoria', params: {
        'p_origen': origen.valor,
        'p_desde': desde == null ? null : _formatoFecha.format(desde),
        'p_hasta': hasta == null ? null : _formatoFecha.format(hasta),
        'p_limite': tamanoPagina,
        'p_offset': offset,
      });
      return (filas as List)
          .map((f) => RegistroAuditoria.fromMap(f as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AuditoriaException(e.message);
    } catch (_) {
      throw const AuditoriaException(
        'No se pudo conectar con el servidor. Revisá tu conexión.',
      );
    }
  }
}