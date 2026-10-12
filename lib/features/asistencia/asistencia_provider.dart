import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';

class EventoPanel {
  final String id;
  final String nombre;
  final DateTime? vigenteHasta; // solo para validadores

  const EventoPanel({
    required this.id,
    required this.nombre,
    this.vigenteHasta,
  });
}

class ResumenAsistencia {
  final int inscriptos;

  /// Alumnos con la entrada registrada.
  final int conEntrada;

  /// Alumnos con asistencia completa (entrada y salida).
  final int presentes;

  const ResumenAsistencia({
    required this.inscriptos,
    this.conEntrada = 0,
    required this.presentes,
  });

  double get porcentajePresentes =>
      inscriptos == 0 ? 0 : (presentes / inscriptos).clamp(0, 1).toDouble();

  double get porcentajeEntrada =>
      inscriptos == 0 ? 0 : (conEntrada / inscriptos).clamp(0, 1).toDouble();
}

/// Estado de la sesión de asistencia tal como lo ve el servidor.
class EstadoSesion {
  final bool abierta;

  /// 'entrada' | 'salida' | null (ningún registro activo).
  final String? modo;
  final DateTime? modoHasta;

  const EstadoSesion({required this.abierta, this.modo, this.modoHasta});
}

/// PIN de respaldo recién generado.
class PinGenerado {
  final String codigo;
  final DateTime venceEn;

  const PinGenerado({required this.codigo, required this.venceEn});
}

/// Marcajes del alumno autenticado en un evento.
class MiMarcaje {
  final DateTime? entradaEn;
  final DateTime? salidaEn;

  const MiMarcaje({this.entradaEn, this.salidaEn});

  bool get completo => entradaEn != null && salidaEn != null;
}

/// Entrada y salida registradas por el alumno en [eventoId].
/// Lee su propia inscripción (RLS), sin pasar por la sesión del validador.
final miMarcajeProvider = FutureProvider.autoDispose.family<MiMarcaje, String>((
  ref,
  eventoId,
) async {
  final fila = await supabase
      .from('inscripciones')
      .select('entrada_en, salida_en')
      .eq('evento_id', eventoId)
      .eq('usuario_id', supabase.auth.currentUser!.id)
      .maybeSingle();

  DateTime? leer(String campo) {
    final valor = fila?[campo] as String?;
    return valor == null ? null : DateTime.parse(valor).toLocal();
  }

  return MiMarcaje(entradaEn: leer('entrada_en'), salidaEn: leer('salida_en'));
});

/// Evento que gestiona el panel. Con [eventoId] nulo (validador) se
/// resuelve desde su propio perfil; con valor se usa ese evento.
final eventoPanelProvider = FutureProvider.autoDispose
    .family<EventoPanel, String?>((ref, eventoId) async {
      String id;
      DateTime? vigenteHasta;

      if (eventoId != null) {
        id = eventoId;
      } else {
        final perfil = await supabase
            .from('usuarios')
            .select('evento_asignado_id, vigente_hasta')
            .eq('id', supabase.auth.currentUser!.id)
            .single();

        final asignado = perfil['evento_asignado_id'] as String?;
        if (asignado == null) {
          throw StateError('Tu cuenta no tiene un evento asignado');
        }
        id = asignado;
        final vigente = perfil['vigente_hasta'] as String?;
        vigenteHasta = vigente == null
            ? null
            : DateTime.parse(vigente).toLocal();
      }

      final evento = await supabase
          .from('eventos')
          .select('nombre')
          .eq('id', id)
          .single();

      return EventoPanel(
        id: id,
        nombre: evento['nombre'] as String,
        vigenteHasta: vigenteHasta,
      );
    });

/// Acceso a las RPC de asistencia. Toda la lógica de seguridad vive en
/// la base de datos; acá solo se invocan.
class AsistenciaService {
  AsistenciaService._();

  // --- Validador ---

  static Future<String> abrirSesion(String eventoId) async {
    final r = await supabase.rpc(
      'abrir_sesion_asistencia',
      params: {'p_evento_id': eventoId},
    );
    return r as String;
  }

  /// Lee el modo activo de la sesión (requiere 10b_estado_sesion_asistencia.sql).
  static Future<EstadoSesion> estadoSesion(String sesionId) async {
    final data = await supabase.rpc(
      'estado_sesion_asistencia',
      params: {'p_sesion_id': sesionId},
    );
    final filas = data as List;
    if (filas.isEmpty) return const EstadoSesion(abierta: false);
    final f = filas.first as Map<String, dynamic>;
    final hasta = f['modo_vence_en'] as String?;
    return EstadoSesion(
      abierta: f['esta_abierta'] as bool,
      modo: f['modo_activo'] as String?,
      modoHasta: hasta == null ? null : DateTime.parse(hasta).toLocal(),
    );
  }

  /// Habilita la entrada o la salida. Pasa por la Edge Function
  /// `activar-modo`, que verifica la contraseña del validador en el
  /// servidor. Lanza [FunctionException] si algo falla.
  static Future<void> activarModo({
    required String sesionId,
    required String modo,
    required String password,
  }) async {
    await supabase.functions.invoke(
      'activar-modo',
      body: {'sesion_id': sesionId, 'modo': modo, 'password': password},
    );
  }

  /// Token del QR (cambia cada 60 s): `sesion:modo:ventana:firma`.
  static Future<String> obtenerTokenQr(String sesionId) async {
    final r = await supabase.rpc(
      'obtener_token_qr',
      params: {'p_sesion_id': sesionId},
    );
    return r as String;
  }

  /// PIN de 4 dígitos que vive 20 s. Se genera solo a pedido.
  static Future<PinGenerado> activarPin(String sesionId) async {
    final data = await supabase.rpc(
      'activar_pin',
      params: {'p_sesion_id': sesionId},
    );
    final filas = data as List;
    final f = filas.first as Map<String, dynamic>;
    return PinGenerado(
      codigo: f['pin_codigo'] as String,
      venceEn: DateTime.parse(f['vence_en'] as String).toLocal(),
    );
  }

  /// Cierre parcial: apaga la entrada o la salida activa y deja la
  /// sesión abierta.
  static Future<void> cerrarModo(String sesionId) async {
    await supabase.rpc(
      'cerrar_modo_asistencia',
      params: {'p_sesion_id': sesionId},
    );
  }

  static Future<void> cerrarSesion(String sesionId) async {
    await supabase.rpc(
      'cerrar_sesion_asistencia',
      params: {'p_sesion_id': sesionId},
    );
  }

  static Future<ResumenAsistencia> resumen(String eventoId) async {
    final data = await supabase.rpc(
      'resumen_asistencia',
      params: {'p_evento_id': eventoId},
    );
    final filas = data as List;
    if (filas.isEmpty) {
      return const ResumenAsistencia(inscriptos: 0, presentes: 0);
    }
    final fila = filas.first as Map<String, dynamic>;
    return ResumenAsistencia(
      inscriptos: fila['inscriptos'] as int,
      conEntrada: fila['con_entrada'] as int,
      presentes: fila['presentes'] as int,
    );
  }

  // --- Alumno (se reescribe en 4D) ---

  static Future<void> marcarQr(String token) async {
    await supabase.rpc('marcar_asistencia_qr', params: {'p_token': token});
  }

  /// Retorna: 'ok' | 'incorrecto' | 'bloqueado' | 'pin_no_activo' |
  /// 'registro_cerrado'
  static Future<String> marcarPin(String eventoId, String pin) async {
    final r = await supabase.rpc(
      'marcar_asistencia_pin',
      params: {'p_evento_id': eventoId, 'p_pin': pin},
    );
    return r as String;
  }
}
