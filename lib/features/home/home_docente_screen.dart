import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import 'home_provider.dart';

class HomeDocenteScreen extends ConsumerWidget {
  const HomeDocenteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricasAsync = ref.watch(metricasDocenteProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel docente'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => _confirmarLogout(context, ref),
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
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(metricasDocenteProvider.future),
        child: metricasAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _vistaError(context, ref),
          data: (metricas) => _vistaContenido(context, metricas),
        ),
      ),
    );
  }

  Widget _vistaError(BuildContext context, WidgetRef ref) {
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
                  const Text('No se pudieron cargar tus métricas'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(metricasDocenteProvider),
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

  Widget _vistaContenido(BuildContext context, MetricasDocente metricas) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Text(
          'Hola, ${metricas.nombreCompleto.split(' ').first} 👋',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text('Resumen de tus programas de extensión',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: _TarjetaMetricaDocente(
                icono: Icons.event_note_outlined,
                valor: '${metricas.eventosActivos}',
                etiqueta: 'Eventos activos',
                color: UniNorteColors.azulMarino,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TarjetaMetricaDocente(
                icono: Icons.groups_outlined,
                valor: '${metricas.totalInscriptos}',
                etiqueta: 'Total inscriptos',
                color: UniNorteColors.azulMarino,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _TarjetaMetricaDocente(
          icono: Icons.pending_actions_outlined,
          valor: '${metricas.pendientesValidacion}',
          etiqueta: 'Asistencias pendientes de validar',
          color: UniNorteColors.dorado,
          ancho: double.infinity,
        ),
        const SizedBox(height: 28),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Próximos eventos',
                style: Theme.of(context).textTheme.titleLarge),
            TextButton(
              onPressed: () => context.push(AppRoutes.listaEventos),
              child: const Text('Ver todos'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (metricas.proximosEventos.isEmpty)
          const _SinEventos()
        else
          ...metricas.proximosEventos.map(
            (evento) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TarjetaEventoDocente(evento: evento),
            ),
          ),
      ],
    );
  }

  void _confirmarLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro que querés salir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}

class _TarjetaMetricaDocente extends StatelessWidget {
  final IconData icono;
  final String valor;
  final String etiqueta;
  final Color color;
  final double? ancho;

  const _TarjetaMetricaDocente({
    required this.icono,
    required this.valor,
    required this.etiqueta,
    required this.color,
    this.ancho,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ancho,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(valor,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(
                      etiqueta,
                      style: Theme.of(context).textTheme.bodyMedium,
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

class _TarjetaEventoDocente extends StatelessWidget {
  final EventoResumen evento;
  const _TarjetaEventoDocente({required this.evento});

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd MMM yyyy', 'es');
    final cuposOcupados = evento.inscriptos;
    final porcentajeOcupacion = evento.cuposMaximos == 0
        ? 0.0
        : (cuposOcupados / evento.cuposMaximos).clamp(0, 1).toDouble();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(
          AppRoutes.gestionAsistencia.replaceFirst(':id', evento.id),
        ),
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
                  const Icon(Icons.chevron_right,
                      color: UniNorteColors.textoSecundario),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 14, color: UniNorteColors.textoSecundario),
                  const SizedBox(width: 6),
                  Text(
                    formatoFecha.format(evento.fecha),
                    style: Theme.of(context).textTheme.bodyMedium,
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
                        value: porcentajeOcupacion,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation(
                            UniNorteColors.dorado),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$cuposOcupados/${evento.cuposMaximos}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SinEventos extends StatelessWidget {
  const _SinEventos();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.event_busy_outlined,
                color: UniNorteColors.textoSecundario, size: 40),
            const SizedBox(height: 10),
            Text(
              'No tenés eventos próximos',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}