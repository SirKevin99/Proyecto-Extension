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
  final int presentes;

  const ResumenAsistencia({required this.inscriptos, required this.presentes});

  double get porcentaje =>
      inscriptos == 0 ? 0 : (presentes / inscriptos).clamp(0, 1).toDouble();
}

/// Evento que gestiona el panel. Con [eventoId] nulo (validador) se
/// resuelve desde su propio perfil; con valor (admin) se usa ese evento.
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
    vigenteHasta = vigente == null ? null : DateTime.parse(vigente).toLocal();
  }

  final evento =
      await supabase.from('eventos').select('nombre').eq('id', id).single();

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

  // --- Validador / admin ---

  static Future<String> abrirSesion(String eventoId) async {
    final r = await supabase
        .rpc('abrir_sesion_asistencia', params: {'p_evento_id': eventoId});
    return r as String;
  }

  static Future<String> obtenerTokenQr(String sesionId) async {
    final r =
        await supabase.rpc('obtener_token_qr', params: {'p_sesion_id': sesionId});
    return r as String;
  }

  static Future<String> activarPin(String sesionId, int minutos) async {
    final r = await supabase.rpc('activar_pin',
        params: {'p_sesion_id': sesionId, 'p_minutos': minutos});
    return r as String;
  }

  static Future<void> cerrarSesion(String sesionId) async {
    await supabase
        .rpc('cerrar_sesion_asistencia', params: {'p_sesion_id': sesionId});
  }

  static Future<ResumenAsistencia> resumen(String eventoId) async {
    final data = await supabase
        .rpc('resumen_asistencia', params: {'p_evento_id': eventoId});
    final filas = data as List;
    if (filas.isEmpty) {
      return const ResumenAsistencia(inscriptos: 0, presentes: 0);
    }
    final fila = filas.first as Map<String, dynamic>;
    return ResumenAsistencia(
      inscriptos: fila['inscriptos'] as int,
      presentes: fila['presentes'] as int,
    );
  }

  // --- Alumno (se usan en el archivo 6) ---

  static Future<void> marcarQr(String token) async {
    await supabase.rpc('marcar_asistencia_qr', params: {'p_token': token});
  }

  /// Retorna: 'ok' | 'incorrecto' | 'bloqueado' | 'pin_no_activo'
  static Future<String> marcarPin(String eventoId, String pin) async {
    final r = await supabase.rpc('marcar_asistencia_pin',
        params: {'p_evento_id': eventoId, 'p_pin': pin});
    return r as String;
  }
}