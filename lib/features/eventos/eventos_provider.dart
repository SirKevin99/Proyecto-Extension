import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
/// Categorías disponibles. Las usan el filtro del catálogo (alumno)
/// y el formulario de creación (admin).
const List<String> categoriasEvento = [
  'Académico',
  'Cultural',
  'Deportivo',
  'Social',
  'Salud',
  'Tecnología',
];

const List<String> modalidadesEvento = [
  'Presencial Obligatorio',
  'Presencial Optativo',
  'Virtual',
];
// ---------------------------------------------------------------
// Modelo de dominio: Evento
// ---------------------------------------------------------------

class Evento {
  final String id;
  final String nombre;
  final String? descripcion;
  final String categoria;
  final String? expositor;
  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final String ubicacion;
  final String modalidad;
  final int horasOtorgadas;
  final int? cuposMaximos; // null = ilimitado
  final int? cuposDisponibles; // null = ilimitado
  final int toleranciaEntradaMin;
  final String creadoPor;
  final bool activo;

  const Evento({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.categoria,
    this.expositor,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.ubicacion,
    required this.modalidad,
    required this.horasOtorgadas,
    required this.cuposMaximos,
    required this.cuposDisponibles,
    required this.toleranciaEntradaMin,
    required this.creadoPor,
    required this.activo,
  });

  bool get cuposIlimitados => cuposMaximos == null;

  bool get cuposAgotados =>
      !cuposIlimitados && (cuposDisponibles ?? 0) <= 0;

  factory Evento.fromMap(Map<String, dynamic> map) {
    return Evento(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      descripcion: map['descripcion'] as String?,
      categoria: map['categoria'] as String,
      expositor: map['expositor'] as String?,
      fecha: DateTime.parse(map['fecha'] as String),
      horaInicio: (map['hora_inicio'] as String).substring(0, 5),
      horaFin: (map['hora_fin'] as String).substring(0, 5),
      ubicacion: map['ubicacion'] as String,
      modalidad: map['modalidad'] as String? ?? 'Presencial Obligatorio',
      horasOtorgadas: map['horas_otorgadas'] as int,
      cuposMaximos: map['cupos_maximos'] as int?,
      cuposDisponibles: map['cupos_disponibles'] as int?,
      toleranciaEntradaMin: map['tolerancia_entrada_min'] as int? ?? 15,
      creadoPor: map['creado_por'] as String,
      activo: map['activo'] as bool? ?? true,
    );
  }
}

// ---------------------------------------------------------------
// Estado de inscripción del alumno para un evento puntual
// ---------------------------------------------------------------

enum EstadoInscripcion { noInscripto, inscriptoPendiente, asistenciaConfirmada }

// ---------------------------------------------------------------
// Filtros del catálogo
// ---------------------------------------------------------------

class FiltrosEventos {
  final String? categoria;
  final String busqueda;

  const FiltrosEventos({this.categoria, this.busqueda = ''});

  FiltrosEventos copyWith({String? categoria, String? busqueda}) {
    return FiltrosEventos(
      categoria: categoria,
      busqueda: busqueda ?? this.busqueda,
    );
  }
}

final filtrosEventosProvider =
    StateProvider.autoDispose<FiltrosEventos>((ref) => const FiltrosEventos());

// ---------------------------------------------------------------
// Catálogo de eventos activos (para alumno)
// RLS ya filtra por carrera: el alumno solo recibe los eventos
// habilitados para su carrera o en los que ya está inscripto.
// ---------------------------------------------------------------

final catalogoEventosProvider =
    FutureProvider.autoDispose<List<Evento>>((ref) async {
  final data = await supabase
      .from('eventos')
      .select()
      .eq('activo', true)
      .order('fecha');

  return (data as List)
      .map((e) => Evento.fromMap(e as Map<String, dynamic>))
      .toList();
});

/// Catálogo filtrado en el cliente por categoría y texto de búsqueda.
final catalogoFiltradoProvider = Provider.autoDispose<AsyncValue<List<Evento>>>(
  (ref) {
    final catalogoAsync = ref.watch(catalogoEventosProvider);
    final filtros = ref.watch(filtrosEventosProvider);

    return catalogoAsync.whenData((eventos) {
      return eventos.where((e) {
        final coincideCategoria =
            filtros.categoria == null || e.categoria == filtros.categoria;
        final coincideBusqueda = filtros.busqueda.trim().isEmpty ||
            e.nombre.toLowerCase().contains(filtros.busqueda.toLowerCase());
        return coincideCategoria && coincideBusqueda;
      }).toList();
    });
  },
);

// ---------------------------------------------------------------
// Detalle de un evento + estado de inscripción del usuario actual
// ---------------------------------------------------------------

class DetalleEventoData {
  final Evento evento;
  final EstadoInscripcion estadoInscripcion;

  const DetalleEventoData({
    required this.evento,
    required this.estadoInscripcion,
  });
}

final detalleEventoProvider = FutureProvider.autoDispose
    .family<DetalleEventoData, String>((ref, eventoId) async {
  final userId = supabase.auth.currentUser!.id;

  final eventoMap =
      await supabase.from('eventos').select().eq('id', eventoId).single();

  final inscripcion = await supabase
      .from('inscripciones')
      .select('asistencia_confirmada')
      .eq('evento_id', eventoId)
      .eq('usuario_id', userId)
      .maybeSingle();

  EstadoInscripcion estado;
  if (inscripcion == null) {
    estado = EstadoInscripcion.noInscripto;
  } else if (inscripcion['asistencia_confirmada'] as bool? ?? false) {
    estado = EstadoInscripcion.asistenciaConfirmada;
  } else {
    estado = EstadoInscripcion.inscriptoPendiente;
  }

  return DetalleEventoData(
    evento: Evento.fromMap(eventoMap),
    estadoInscripcion: estado,
  );
});

// ---------------------------------------------------------------
// Acciones: inscribirse a un evento
// ---------------------------------------------------------------

class InscripcionNotifier extends StateNotifier<AsyncValue<void>> {
  InscripcionNotifier() : super(const AsyncValue.data(null));

  /// Inscribe al usuario actual a un evento.
  ///
  /// El decremento de `cupos_disponibles` se hace vía función RPC
  /// (`inscribirse_a_evento`) para garantizar atomicidad: dos alumnos
  /// inscribiéndose al último cupo simultáneamente NO deben poder
  /// generar overbooking. La RPC también valida que el evento esté
  /// habilitado para la carrera del alumno.
  Future<bool> inscribirse(String eventoId) async {
    state = const AsyncValue.loading();
    try {
      await supabase.rpc('inscribirse_a_evento', params: {
        'p_evento_id': eventoId,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final inscripcionNotifierProvider =
    StateNotifierProvider.autoDispose<InscripcionNotifier, AsyncValue<void>>(
  (ref) => InscripcionNotifier(),
);

// ---------------------------------------------------------------
// Admin: crear y editar evento
// ---------------------------------------------------------------

/// Un evento puntual (usado por la pantalla de edición).
final eventoPorIdProvider =
    FutureProvider.autoDispose.family<Evento, String>((ref, id) async {
  final fila = await supabase.from('eventos').select().eq('id', id).single();
  return Evento.fromMap(fila);
});

/// Ids de las carreras habilitadas para un evento (solo admin, por RLS).
final carrerasDeEventoProvider =
    FutureProvider.autoDispose.family<Set<int>, String>((ref, eventoId) async {
  final filas = await supabase
      .from('evento_carreras')
      .select('carrera_id')
      .eq('evento_id', eventoId);

  return (filas as List)
      .map((f) => ((f as Map<String, dynamic>)['carrera_id'] as num).toInt())
      .toSet();
});

class CrearEventoNotifier extends StateNotifier<AsyncValue<void>> {
  CrearEventoNotifier() : super(const AsyncValue.data(null));

  /// Crea el evento y sus carreras en una sola transacción
  /// (RPC `crear_evento`). `cuposMaximos` nulo = cupo ilimitado.
  /// [carreraIds] debe tener al menos una carrera (lo valida el servidor).
  Future<bool> crear({
    required String nombre,
    String? descripcion,
    required String categoria,
    String? expositor,
    required String fecha, // yyyy-MM-dd
    required String horaInicio, // HH:mm:ss
    required String horaFin,
    required String ubicacion,
    required String modalidad,
    required int horasOtorgadas,
    int? cuposMaximos,
    required int toleranciaEntradaMin,
    required Set<int> carreraIds,
  }) async {
    state = const AsyncValue.loading();
    try {
      await supabase.rpc('crear_evento', params: {
        'p_nombre': nombre,
        'p_descripcion': descripcion,
        'p_categoria': categoria,
        'p_expositor': expositor,
        'p_fecha': fecha,
        'p_hora_inicio': horaInicio,
        'p_hora_fin': horaFin,
        'p_ubicacion': ubicacion,
        'p_modalidad': modalidad,
        'p_horas_otorgadas': horasOtorgadas,
        'p_cupos_maximos': cuposMaximos,
        'p_tolerancia_min': toleranciaEntradaMin,
        'p_carrera_ids': carreraIds.toList(),
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// La edición la valida y ejecuta el servidor (RPC `editar_evento`).
  /// Después se reemplazan las carreras (RPC `definir_carreras_evento`);
  /// las inscripciones existentes no se modifican.
  Future<bool> editar({
    required String eventoId,
    required String nombre,
    String? descripcion,
    required String categoria,
    String? expositor,
    required String fecha,
    required String horaInicio,
    required String horaFin,
    required String ubicacion,
    required String modalidad,
    required int horasOtorgadas,
    int? cuposMaximos,
    required int toleranciaEntradaMin,
    required Set<int> carreraIds,
  }) async {
    state = const AsyncValue.loading();
    try {
      await supabase.rpc('editar_evento', params: {
        'p_evento_id': eventoId,
        'p_nombre': nombre,
        'p_descripcion': descripcion,
        'p_categoria': categoria,
        'p_expositor': expositor,
        'p_fecha': fecha,
        'p_hora_inicio': horaInicio,
        'p_hora_fin': horaFin,
        'p_ubicacion': ubicacion,
        'p_modalidad': modalidad,
        'p_horas_otorgadas': horasOtorgadas,
        'p_cupos_maximos': cuposMaximos,
        'p_tolerancia_min': toleranciaEntradaMin,
      });
      await supabase.rpc('definir_carreras_evento', params: {
        'p_evento_id': eventoId,
        'p_carrera_ids': carreraIds.toList(),
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final crearEventoNotifierProvider =
    StateNotifierProvider.autoDispose<CrearEventoNotifier, AsyncValue<void>>(
  (ref) => CrearEventoNotifier(),
);