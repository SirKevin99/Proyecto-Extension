import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import 'admin_eventos_provider.dart';

enum _Filtro { todos, vigentes, finalizados, cancelados }

class AdminEventosScreen extends ConsumerStatefulWidget {
  const AdminEventosScreen({super.key});

  @override
  ConsumerState<AdminEventosScreen> createState() => _AdminEventosScreenState();
}

class _AdminEventosScreenState extends ConsumerState<AdminEventosScreen> {
  String _busqueda = '';
  _Filtro _filtro = _Filtro.todos;

  List<EventoAdmin> _visibles(List<EventoAdmin> todos) {
    final q = _busqueda.trim().toLowerCase();
    return todos.where((e) {
      final coincideFiltro = switch (_filtro) {
        _Filtro.todos => true,
        _Filtro.vigentes => e.estado == EstadoEvento.vigente,
        _Filtro.finalizados => e.estado == EstadoEvento.finalizado,
        _Filtro.cancelados => e.estado == EstadoEvento.cancelado,
      };
      final coincideTexto = q.isEmpty || e.nombre.toLowerCase().contains(q);
      return coincideFiltro && coincideTexto;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminEventosProvider);

    final esSuperadmin =
        SessionSnapshot.instance.rol == RolUsuario.superadmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos los eventos'),
        actions: [
          if (esSuperadmin)
            IconButton(
              icon: const Icon(Icons.history_edu_outlined),
              tooltip: 'Cargar evento pasado',
              onPressed: () => context.push(AppRoutes.cargarEventoPasado),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.crearEvento),
        backgroundColor: UniNorteColors.dorado,
        foregroundColor: UniNorteColors.azulMarino,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo evento'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: UniNorteColors.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text('No se pudieron cargar los eventos'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(adminEventosProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        data: _contenido,
      ),
    );
  }

  Widget _contenido(List<EventoAdmin> todos) {
    final visibles = _visibles(todos);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar evento...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _busqueda = v),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in _Filtro.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        _Filtro.todos => 'Todos',
                        _Filtro.vigentes => 'Vigentes',
                        _Filtro.finalizados => 'Finalizados',
                        _Filtro.cancelados => 'Cancelados',
                      }),
                      selected: _filtro == f,
                      selectedColor: UniNorteColors.dorado,
                      backgroundColor: Colors.white,
                      onSelected: (_) => setState(() => _filtro = f),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(adminEventosProvider.future),
            child: visibles.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(child: Text('No hay eventos con estos filtros')),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: visibles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) =>
                        _TarjetaEventoAdmin(evento: visibles[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

enum _Accion { editar, finalizar, cancelar, corregirPasado, reactivar }

class _TarjetaEventoAdmin extends ConsumerWidget {
  final EventoAdmin evento;
  const _TarjetaEventoAdmin({required this.evento});

  /// Acciones disponibles según el estado del evento y el rol.
  /// Fase 8 (solo superadmin): corregir eventos cargados como pasados y
  /// reactivar cancelados con fecha pasada.
  List<(_Accion, String)> _acciones() {
    final esSuperadmin =
        SessionSnapshot.instance.rol == RolUsuario.superadmin;
    return [
      if (evento.vigente) ...[
        (_Accion.editar, 'Editar evento'),
        (_Accion.finalizar, 'Finalizar evento'),
        (_Accion.cancelar, 'Cancelar evento'),
      ],
      if (esSuperadmin &&
          evento.estado == EstadoEvento.finalizado &&
          evento.cargaHistorica)
        (_Accion.corregirPasado, 'Corregir evento pasado'),
      if (esSuperadmin &&
          evento.estado == EstadoEvento.cancelado &&
          evento.fechaPasada)
        (_Accion.reactivar, 'Reactivar como finalizado'),
    ];
  }

  void _ejecutar(BuildContext context, WidgetRef ref, _Accion a) {
    switch (a) {
      case _Accion.editar:
        context.push(AppRoutes.editarEventoPath(evento.id));
      case _Accion.corregirPasado:
        context.push(AppRoutes.editarEventoPasadoPath(evento.id));
      case _Accion.reactivar:
        _reactivar(context, ref);
      case _Accion.finalizar:
      case _Accion.cancelar:
        _confirmarYEjecutar(context, ref, a);
    }
  }

  Future<void> _reactivar(BuildContext context, WidgetRef ref) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoReactivar(nombre: evento.nombre),
    );
    if (motivo == null) return;

    try {
      final completos = await reactivarEventoCancelado(evento.id, motivo);
      ref.invalidate(adminEventosProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              completos == 0
                  ? 'Evento reactivado como finalizado. Ningún asistente '
                      'tenía entrada y salida registradas.'
                  : 'Evento reactivado como finalizado. $completos '
                      '${completos == 1 ? 'asistente suma' : 'asistentes suman'} '
                      'horas y certificado.',
            ),
          ),
        );
      }
    } catch (e) {
      final mensaje = e is PostgrestException
          ? e.message
          : 'No se pudo reactivar el evento';
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensaje)));
      }
    }
  }

  Future<void> _confirmarYEjecutar(
    BuildContext context,
    WidgetRef ref,
    _Accion accion,
  ) async {
    final esCancelar = accion == _Accion.cancelar;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esCancelar ? 'Cancelar evento' : 'Finalizar evento'),
        content: Text(
          esCancelar
              ? '"${evento.nombre}" se marcará como cancelado. Se cerrará la '
                    'sesión de asistencia, se deshabilitará su validador y no '
                    'se acreditarán horas. Esta acción no se puede deshacer.'
              : '"${evento.nombre}" se marcará como finalizado. Se cerrará la '
                    'sesión de asistencia y se deshabilitará su validador. '
                    'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: esCancelar
                ? FilledButton.styleFrom(backgroundColor: UniNorteColors.error)
                : null,
            child: Text(esCancelar ? 'Cancelar evento' : 'Finalizar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      if (esCancelar) {
        await cancelarEvento(evento.id);
      } else {
        await finalizarEvento(evento.id);
      }
      ref.invalidate(adminEventosProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              esCancelar ? 'Evento cancelado' : 'Evento finalizado',
            ),
          ),
        );
      }
    } catch (e) {
      final mensaje = e is PostgrestException
          ? e.message
          : 'No se pudo cambiar el estado del evento';
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensaje)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatoFecha = DateFormat('dd MMM yyyy', 'es');
    final max = evento.cuposMaximos;
    final ocupacion = (max == null || max == 0)
        ? 0.0
        : (evento.inscriptos / max).clamp(0, 1).toDouble();
    final acciones = _acciones();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    evento.nombre,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _EtiquetaEstado(evento.estado),
                if (acciones.isNotEmpty)
                  PopupMenuButton<_Accion>(
                    tooltip: 'Más acciones',
                    padding: EdgeInsets.zero,
                    onSelected: (a) => _ejecutar(context, ref, a),
                    itemBuilder: (_) => [
                      for (final (accion, texto) in acciones)
                        PopupMenuItem(value: accion, child: Text(texto)),
                    ],
                  ),
              ],
            ),
            if (evento.cargaHistorica) ...[
              const SizedBox(height: 6),
              const _EtiquetaPasado(),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: UniNorteColors.textoSecundario,
                ),
                const SizedBox(width: 6),
                Text(
                  '${formatoFecha.format(evento.fecha)} · ${evento.horaInicio}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: UniNorteColors.textoSecundario,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    evento.ubicacion,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ocupacion,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(
                        UniNorteColors.dorado,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${evento.inscriptos}/${evento.cuposMaximos ?? '∞'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            if (evento.estado == EstadoEvento.cancelado) ...[
              const SizedBox(height: 8),
              Text(
                'Cancelado: las asistencias se conservan como historial y '
                'no acreditan horas.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: UniNorteColors.error),
              ),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.push(AppRoutes.gestionAsistenciaPath(evento.id)),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Asistencia'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marca de los eventos cargados como pasados (fase 8).
class _EtiquetaPasado extends StatelessWidget {
  const _EtiquetaPasado();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: UniNorteColors.dorado.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_edu_outlined,
              size: 14, color: UniNorteColors.azulMarino),
          SizedBox(width: 4),
          Text(
            'Cargado como evento pasado',
            style: TextStyle(
              color: UniNorteColors.azulMarino,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pide el motivo para reactivar un evento cancelado (fase 8).
/// Devuelve el motivo, o null si se cancela.
class _DialogoReactivar extends StatefulWidget {
  final String nombre;
  const _DialogoReactivar({required this.nombre});

  @override
  State<_DialogoReactivar> createState() => _DialogoReactivarState();
}

class _DialogoReactivarState extends State<_DialogoReactivar> {
  final _formKey = GlobalKey<FormState>();
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reactivar evento'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${widget.nombre}" pasará de cancelado a finalizado. Los '
              'asistentes con entrada y salida registradas sumarán sus horas '
              'y recibirán el certificado.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _motivo,
              autofocus: true,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                helperText: 'Queda registrado en la auditoría',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 10)
                  ? 'Indicá el motivo (mínimo 10 caracteres)'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _motivo.text.trim());
            }
          },
          child: const Text('Reactivar'),
        ),
      ],
    );
  }
}

class _EtiquetaEstado extends StatelessWidget {
  final EstadoEvento estado;
  const _EtiquetaEstado(this.estado);

  @override
  Widget build(BuildContext context) {
    final (texto, color) = switch (estado) {
      EstadoEvento.vigente => ('Vigente', Colors.green.shade700),
      EstadoEvento.finalizado => ('Finalizado', UniNorteColors.textoSecundario),
      EstadoEvento.cancelado => ('Cancelado', UniNorteColors.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}