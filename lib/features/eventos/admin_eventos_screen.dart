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

    return Scaffold(
      appBar: AppBar(title: const Text('Todos los eventos')),
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
              const Icon(Icons.error_outline,
                  color: UniNorteColors.error, size: 48),
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

enum _Accion { finalizar, cancelar }

class _TarjetaEventoAdmin extends ConsumerWidget {
  final EventoAdmin evento;
  const _TarjetaEventoAdmin({required this.evento});

  Future<void> _confirmarYEjecutar(
      BuildContext context, WidgetRef ref, _Accion accion) async {
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
                ? FilledButton.styleFrom(
                    backgroundColor: UniNorteColors.error)
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(esCancelar
              ? 'Evento cancelado'
              : 'Evento finalizado'),
        ));
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
    final ocupacion = evento.cuposMaximos == 0
        ? 0.0
        : (evento.inscriptos / evento.cuposMaximos).clamp(0, 1).toDouble();

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
                if (evento.vigente)
                  PopupMenuButton<_Accion>(
                    tooltip: 'Más acciones',
                    padding: EdgeInsets.zero,
                    onSelected: (a) => _confirmarYEjecutar(context, ref, a),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _Accion.finalizar,
                        child: Text('Finalizar evento'),
                      ),
                      PopupMenuItem(
                        value: _Accion.cancelar,
                        child: Text('Cancelar evento'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: UniNorteColors.textoSecundario),
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
                const Icon(Icons.location_on_outlined,
                    size: 14, color: UniNorteColors.textoSecundario),
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
                      valueColor:
                          const AlwaysStoppedAnimation(UniNorteColors.dorado),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${evento.inscriptos}/${evento.cuposMaximos}',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context
                        .push(AppRoutes.gestionAsistenciaPath(evento.id)),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Corregir'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: evento.vigente
                        ? () => context
                            .push(AppRoutes.sesionAsistenciaPath(evento.id))
                        : null,
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: const Text('Sesión'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
      EstadoEvento.finalizado => (
          'Finalizado',
          UniNorteColors.textoSecundario
        ),
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
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}