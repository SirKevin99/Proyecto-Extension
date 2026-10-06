import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import 'eventos_provider.dart';



class ListaEventosScreen extends ConsumerWidget {
  const ListaEventosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogoAsync = ref.watch(catalogoFiltradoProvider);
    final filtros = ref.watch(filtrosEventosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eventos de extensión'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar evento...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filtros.busqueda.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => ref
                            .read(filtrosEventosProvider.notifier)
                            .update((f) => f.copyWith(busqueda: '')),
                      )
                    : null,
              ),
              onChanged: (valor) => ref
                  .read(filtrosEventosProvider.notifier)
                  .update((f) => f.copyWith(busqueda: valor)),
            ),
          ),

          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _ChipCategoria(
                  label: 'Todas',
                  seleccionado: filtros.categoria == null,
                  onTap: () => ref
                      .read(filtrosEventosProvider.notifier)
                      .update((f) => FiltrosEventos(
                          categoria: null, busqueda: f.busqueda)),
                ),
                ...categoriasEvento.map(
                  (cat) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _ChipCategoria(
                      label: cat,
                      seleccionado: filtros.categoria == cat,
                      onTap: () => ref
                          .read(filtrosEventosProvider.notifier)
                          .update((f) => FiltrosEventos(
                              categoria: f.categoria == cat ? null : cat,
                              busqueda: f.busqueda)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(catalogoEventosProvider.future),
              child: catalogoAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, _) => _vistaError(ref),
                data: (eventos) => eventos.isEmpty
                    ? _vistaVacia()
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: eventos.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _TarjetaEvento(evento: eventos[index]),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaError(WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: UniNorteColors.error, size: 48),
                  const SizedBox(height: 12),
                  const Text('No se pudieron cargar los eventos'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(catalogoEventosProvider),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _vistaVacia() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_busy_outlined,
                      color: UniNorteColors.textoSecundario, size: 48),
                  SizedBox(height: 12),
                  Text('No hay eventos disponibles con estos filtros'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipCategoria extends StatelessWidget {
  final String label;
  final bool seleccionado;
  final VoidCallback onTap;

  const _ChipCategoria({
    required this.label,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: seleccionado,
      onSelected: (_) => onTap(),
      selectedColor: UniNorteColors.dorado,
      labelStyle: TextStyle(
        color: seleccionado ? UniNorteColors.azulMarino : UniNorteColors.textoPrimario,
        fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.grey.shade300),
    );
  }
}

class _TarjetaEvento extends StatelessWidget {
  final Evento evento;
  const _TarjetaEvento({required this.evento});

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd MMM', 'es');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(
          AppRoutes.detalleEvento.replaceFirst(':id', evento.id),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: UniNorteColors.azulMarino,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  formatoFecha.format(evento.fecha).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Chip(
                      label: Text(evento.categoria),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      evento.nombre,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14, color: UniNorteColors.textoSecundario),
                        const SizedBox(width: 4),
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _BadgeInfo(
                          icono: Icons.schedule,
                          texto: '${evento.horasOtorgadas}h',
                        ),
                        const SizedBox(width: 8),
                        _BadgeInfo(
                          icono: Icons.people_outline,
                          texto: evento.cuposAgotados
                              ? 'Sin cupos'
                              : '${evento.cuposDisponibles} cupos',
                          color: evento.cuposAgotados
                              ? UniNorteColors.error
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeInfo extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color? color;

  const _BadgeInfo({required this.icono, required this.texto, this.color});

  @override
  Widget build(BuildContext context) {
    final colorFinal = color ?? UniNorteColors.textoSecundario;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 14, color: colorFinal),
        const SizedBox(width: 4),
        Text(
          texto,
          style: TextStyle(color: colorFinal, fontSize: 12),
        ),
      ],
    );
  }
}