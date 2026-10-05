import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'eventos_provider.dart';

class DetalleEventoScreen extends ConsumerWidget {
  final String eventoId;
  const DetalleEventoScreen({super.key, required this.eventoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalleAsync = ref.watch(detalleEventoProvider(eventoId));
    final inscripcionState = ref.watch(inscripcionNotifierProvider);

    ref.listen<AsyncValue<void>>(inscripcionNotifierProvider, (previo, actual) {
      actual.whenOrNull(
        error: (err, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_mensajeErrorInscripcion(err)),
              backgroundColor: UniNorteColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del evento')),
      body: detalleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _vistaError(context, ref),
        data: (datos) => _vistaContenido(context, ref, datos, inscripcionState),
      ),
    );
  }

  Widget _vistaError(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: UniNorteColors.error, size: 48),
            const SizedBox(height: 12),
            const Text('No se pudo cargar el evento'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(detalleEventoProvider(eventoId)),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaContenido(
    BuildContext context,
    WidgetRef ref,
    DetalleEventoData datos,
    AsyncValue<void> inscripcionState,
  ) {
    final evento = datos.evento;
    final formatoFecha = DateFormat('EEEE dd MMMM yyyy', 'es');
    final cargandoInscripcion = inscripcionState.isLoading;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Chip(label: Text(evento.categoria)),
              const SizedBox(height: 10),
              Text(evento.nombre,
                  style: Theme.of(context).textTheme.headlineMedium),
              if (evento.expositor != null &&
                  evento.expositor!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Dictado por ${evento.expositor}',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 20),

              _FilaInfo(
                icono: Icons.calendar_today_outlined,
                titulo: 'Fecha',
                valor: _capitalizar(formatoFecha.format(evento.fecha)),
              ),
              _FilaInfo(
                icono: Icons.schedule_outlined,
                titulo: 'Horario',
                valor: evento.horaFin != null
                    ? '${evento.horaInicio} - ${evento.horaFin}'
                    : 'Desde las ${evento.horaInicio}',
              ),
              _FilaInfo(
                icono: Icons.location_on_outlined,
                titulo: 'Ubicación',
                valor: evento.ubicacion,
              ),
              _FilaInfo(
                icono: Icons.groups_outlined,
                titulo: 'Modalidad',
                valor: evento.modalidad,
              ),
              _FilaInfo(
                icono: Icons.timer_outlined,
                titulo: 'Horas otorgadas',
                valor: '${evento.horasOtorgadas} horas de extensión',
              ),
              _FilaInfo(
                icono: Icons.event_seat_outlined,
                titulo: 'Cupos',
                valor: evento.cuposAgotados
                    ? 'Sin cupos disponibles'
                    : '${evento.cuposDisponibles} de ${evento.cuposMaximos} disponibles',
                colorValor:
                    evento.cuposAgotados ? UniNorteColors.error : null,
              ),

              if (evento.descripcion != null &&
                  evento.descripcion!.trim().isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Descripción',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(evento.descripcion!,
                    style: Theme.of(context).textTheme.bodyLarge),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),

        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: _botonAccion(
              context,
              ref,
              datos,
              cargandoInscripcion,
            ),
          ),
        ),
      ],
    );
  }

  Widget _botonAccion(
    BuildContext context,
    WidgetRef ref,
    DetalleEventoData datos,
    bool cargando,
  ) {
    switch (datos.estadoInscripcion) {
      case EstadoInscripcion.asistenciaConfirmada:
        return _EstadoInscripcionBanner(
          icono: Icons.verified_outlined,
          texto: 'Asistencia confirmada por el docente',
          color: UniNorteColors.exito,
        );

      case EstadoInscripcion.inscriptoPendiente:
        return _EstadoInscripcionBanner(
          icono: Icons.hourglass_top_outlined,
          texto: 'Ya estás inscripto. Pendiente de validación de asistencia',
          color: UniNorteColors.dorado,
        );

      case EstadoInscripcion.noInscripto:
        if (datos.evento.cuposAgotados) {
          return const _EstadoInscripcionBanner(
            icono: Icons.block_outlined,
            texto: 'No hay cupos disponibles',
            color: UniNorteColors.error,
          );
        }
        return ElevatedButton(
          onPressed: cargando
              ? null
              : () => _confirmarInscripcion(context, ref, datos.evento.id),
          child: cargando
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: UniNorteColors.azulMarino,
                  ),
                )
              : const Text('Inscribirme'),
        );
    }
  }

  Future<void> _confirmarInscripcion(
    BuildContext context,
    WidgetRef ref,
    String eventoId,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar inscripción'),
        content: const Text(
          '¿Confirmás tu inscripción a este evento? Recordá que la '
          'asistencia debe ser validada presencialmente por el docente '
          'para que las horas se acrediten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final exito = await ref
        .read(inscripcionNotifierProvider.notifier)
        .inscribirse(eventoId);

    if (exito) {
      ref.invalidate(detalleEventoProvider(eventoId));
      ref.invalidate(catalogoEventosProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Inscripción confirmada!'),
            backgroundColor: UniNorteColors.exito,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _mensajeErrorInscripcion(Object error) {
    final texto = error.toString().toLowerCase();
    if (texto.contains('no hay cupos')) {
      return 'Se agotaron los cupos justo ahora. Probá con otro evento.';
    }
    if (texto.contains('duplicate') || texto.contains('unique')) {
      return 'Ya estabas inscripto a este evento.';
    }
    return 'No se pudo completar la inscripción. Intentá nuevamente.';
  }

  String _capitalizar(String texto) =>
      texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);
}

class _FilaInfo extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;
  final Color? colorValor;

  const _FilaInfo({
    required this.icono,
    required this.titulo,
    required this.valor,
    this.colorValor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: UniNorteColors.azulMarino.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icono, size: 18, color: UniNorteColors.azulMarino),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorValor ?? UniNorteColors.textoPrimario,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoInscripcionBanner extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;

  const _EstadoInscripcionBanner({
    required this.icono,
    required this.texto,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}