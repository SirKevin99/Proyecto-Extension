import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import '../eventos/admin_eventos_provider.dart';

class InscriptoAsistencia {
  final String inscripcionId;
  final String nombre;
  final String ci;
  final DateTime? entradaEn;
  final DateTime? salidaEn;
  final String? metodoEntrada; // 'qr' | 'pin' | 'manual'
  final String? metodoSalida;

  /// Registro traído del sistema anterior (antes de entrada/salida).
  final bool migrado;

  const InscriptoAsistencia({
    required this.inscripcionId,
    required this.nombre,
    required this.ci,
    this.entradaEn,
    this.salidaEn,
    this.metodoEntrada,
    this.metodoSalida,
    this.migrado = false,
  });

  bool get tieneEntrada => entradaEn != null;
  bool get completo => entradaEn != null && salidaEn != null;
}

class GestionAsistenciaData {
  final String eventoNombre;
  final EstadoEvento estado;
  final DateTime fecha;
  final DateTime? salidaAnticipadaEn;
  final List<InscriptoAsistencia> inscriptos;

  const GestionAsistenciaData({
    required this.eventoNombre,
    required this.estado,
    required this.fecha,
    required this.salidaAnticipadaEn,
    required this.inscriptos,
  });

  int get completos => inscriptos.where((i) => i.completo).length;
  int get soloEntrada =>
      inscriptos.where((i) => i.tieneEntrada && !i.completo).length;
  int get sinAsistencia => inscriptos.where((i) => !i.tieneEntrada).length;

  bool get esCancelado => estado == EstadoEvento.cancelado;

  bool get esHoy {
    final hoy = DateTime.now();
    return fecha.year == hoy.year &&
        fecha.month == hoy.month &&
        fecha.day == hoy.day;
  }

  /// Se puede autorizar si el evento está vigente, es de hoy y todavía no
  /// se autorizó. El servidor valida lo mismo.
  bool get puedeAutorizarSalidaAnticipada =>
      estado == EstadoEvento.vigente && esHoy && salidaAnticipadaEn == null;
}

/// Inscriptos de un evento. RLS: solo el admin puede leer todas las
/// inscripciones y los datos de los alumnos.
final gestionAsistenciaProvider = FutureProvider.autoDispose
    .family<GestionAsistenciaData, String>((ref, eventoId) async {
      final evento = await supabase
          .from('eventos')
          .select('nombre, estado, fecha, salida_anticipada_en')
          .eq('id', eventoId)
          .single();

      final filas = await supabase
          .from('inscripciones')
          .select(
            'id, entrada_en, salida_en, metodo_entrada, metodo_salida, migrado, '
            'usuario:usuarios!usuario_id(nombre_completo, ci)',
          )
          .eq('evento_id', eventoId);

      DateTime? fechaHora(Object? valor) =>
          valor == null ? null : DateTime.parse(valor as String).toLocal();

      final inscriptos = <InscriptoAsistencia>[];
      for (final fila in filas as List) {
        final usuario = fila['usuario'] as Map<String, dynamic>?;
        inscriptos.add(
          InscriptoAsistencia(
            inscripcionId: fila['id'] as String,
            nombre: usuario?['nombre_completo'] as String? ?? 'Sin nombre',
            ci: usuario?['ci'] as String? ?? '-',
            entradaEn: fechaHora(fila['entrada_en']),
            salidaEn: fechaHora(fila['salida_en']),
            metodoEntrada: fila['metodo_entrada'] as String?,
            metodoSalida: fila['metodo_salida'] as String?,
            migrado: fila['migrado'] as bool? ?? false,
          ),
        );
      }

      inscriptos.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );

      return GestionAsistenciaData(
        eventoNombre: evento['nombre'] as String,
        estado: EstadoEvento.desdeTexto(evento['estado'] as String?),
        fecha: DateTime.parse(evento['fecha'] as String),
        salidaAnticipadaEn: fechaHora(evento['salida_anticipada_en']),
        inscriptos: inscriptos,
      );
    });

class CorreccionService {
  CorreccionService._();

  /// Registra o revoca la entrada, la salida o ambas de las inscripciones
  /// indicadas. El motivo es obligatorio y queda auditado en el servidor.
  ///
  /// [campo]: 'entrada' | 'salida' | 'ambos'. Revocar la entrada también
  /// revoca la salida (no hay salida sin entrada).
  static Future<int> corregir(
    List<String> ids, {
    required String campo,
    required bool registrar,
    required String motivo,
  }) async {
    final r = await supabase.rpc(
      'corregir_asistencia',
      params: {
        'p_inscripcion_ids': ids,
        'p_campo': campo,
        'p_registrar': registrar,
        'p_motivo': motivo,
      },
    );
    return r as int;
  }

  /// Permite al validador habilitar la salida antes de los 15 minutos
  /// previos a la hora de fin. No cambia el plazo de los alumnos.
  static Future<void> autorizarSalidaAnticipada(String eventoId) async {
    await supabase.rpc(
      'autorizar_salida_anticipada',
      params: {'p_evento_id': eventoId},
    );
  }
}
