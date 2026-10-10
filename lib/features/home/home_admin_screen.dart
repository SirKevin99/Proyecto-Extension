import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import 'home_provider.dart';

class HomeAdminScreen extends ConsumerWidget {
  const HomeAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricasAsync = ref.watch(metricasAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de administración'),
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
        onRefresh: () => ref.refresh(metricasAdminProvider.future),
        child: metricasAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _vistaError(ref),
          data: (metricas) => _vistaContenido(context, metricas),
        ),
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
                  const Text('No se pudieron cargar las métricas'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(metricasAdminProvider),
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

  Widget _vistaContenido(BuildContext context, MetricasAdmin m) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Text(
          'Hola, ${m.nombreCompleto.split(' ').first} 👋',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text('Resumen general de extensión',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),

        _AccesoDestacado(
          vigentes: m.eventosVigentes,
          onTap: () => context.push(AppRoutes.adminEventos),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _TarjetaMetrica(
                icono: Icons.groups_outlined,
                valor: '${m.totalInscriptos}',
                etiqueta: 'Inscripciones',
                color: UniNorteColors.azulMarino,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TarjetaMetrica(
                icono: Icons.verified_user_outlined,
                valor: '${m.validadoresActivos}',
                etiqueta: 'Validadores activos',
                color: UniNorteColors.exito,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        Text('Accesos de gestión',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _AccesoRapido(
          icono: Icons.person_add_alt_1_outlined,
          titulo: 'Alta de usuario',
          subtitulo: 'Registrar un alumno o administrador',
          onTap: () => context.push(AppRoutes.altaUsuario),
        ),
        const SizedBox(height: 10),
        _AccesoRapido(
          icono: Icons.qr_code_scanner_outlined,
          titulo: 'Alta de validador',
          subtitulo: 'Acceso temporal para marcar asistencia',
          onTap: () => context.push(AppRoutes.altaValidador),
        ),
        const SizedBox(height: 10),
        _AccesoRapido(
          icono: Icons.event_note_outlined,
          titulo: 'Todos los eventos',
          subtitulo: 'Vigentes, finalizados y cancelados',
          onTap: () => context.push(AppRoutes.adminEventos),
        ),
        const SizedBox(height: 28),

        Text('Eventos vigentes',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (m.eventosVigentesLista.isEmpty)
          const _SinEventos(texto: 'No hay eventos vigentes')
        else
          ...m.eventosVigentesLista.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TarjetaEvento(evento: e),
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

class _AccesoDestacado extends StatelessWidget {
  final int vigentes;
  final VoidCallback onTap;

  const _AccesoDestacado({required this.vigentes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: UniNorteColors.azulMarino,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: UniNorteColors.dorado,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.event_available,
                    color: UniNorteColors.azulMarino, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$vigentes',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      vigentes == 1 ? 'Evento vigente' : 'Eventos vigentes',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaMetrica extends StatelessWidget {
  final IconData icono;
  final String valor;
  final String etiqueta;
  final Color color;

  const _TarjetaMetrica({
    required this.icono,
    required this.valor,
    required this.etiqueta,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccesoRapido extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _AccesoRapido({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: UniNorteColors.dorado.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: UniNorteColors.azulMarino),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: Theme.of(context).textTheme.titleLarge),
                    Text(subtitulo,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: UniNorteColors.textoSecundario),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaEvento extends StatelessWidget {
  final EventoResumen evento;

  const _TarjetaEvento({required this.evento});

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd MMM yyyy', 'es');
    final ocupacion = evento.cuposMaximos == 0
        ? 0.0
        : (evento.inscriptos / evento.cuposMaximos).clamp(0, 1).toDouble();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            context.push(AppRoutes.gestionAsistenciaPath(evento.id)),
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
                    '${formatoFecha.format(evento.fecha)} · ${evento.horaInicio}',
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
                        value: ocupacion,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation(
                            UniNorteColors.dorado),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${evento.inscriptos}/${evento.cuposMaximos}',
                      style: Theme.of(context).textTheme.bodyMedium),
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
  final String texto;
  const _SinEventos({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.event_available_outlined,
                color: UniNorteColors.textoSecundario, size: 40),
            const SizedBox(height: 10),
            Text(texto,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}