import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import 'historial_eventos_provider.dart';

enum _Filtro { todos, acreditados, enCurso, noAcreditados, cancelados }

class HistorialEventosScreen extends ConsumerStatefulWidget {
  const HistorialEventosScreen({super.key});

  @override
  ConsumerState<HistorialEventosScreen> createState() =>
      _HistorialEventosScreenState();
}

class _HistorialEventosScreenState
    extends ConsumerState<HistorialEventosScreen> {
  _Filtro _filtro = _Filtro.todos;

  List<EventoHistorial> _visibles(List<EventoHistorial> todos) {
    return todos.where((e) {
      return switch (_filtro) {
        _Filtro.todos => true,
        _Filtro.acreditados => e.situacion == SituacionHistorial.acreditado,
        _Filtro.enCurso => e.situacion == SituacionHistorial.enCurso,
        _Filtro.noAcreditados => e.situacion == SituacionHistorial.noAcreditado,
        _Filtro.cancelados => e.situacion == SituacionHistorial.cancelado,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(historialEventosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi historial')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: UniNorteColors.error, size: 48),
              const SizedBox(height: 12),
              const Text('No se pudo cargar tu historial'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(historialEventosProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        data: _contenido,
      ),
    );
  }

  Widget _contenido(List<EventoHistorial> todos) {
    final visibles = _visibles(todos);
    final horas = todos
        .where((e) => e.situacion == SituacionHistorial.acreditado)
        .fold<int>(0, (suma, e) => suma + e.horasOtorgadas);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$horas horas acreditadas',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text('${todos.length} evento(s) en tu historial',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in _Filtro.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        _Filtro.todos => 'Todos',
                        _Filtro.acreditados => 'Acreditados',
                        _Filtro.enCurso => 'En curso',
                        _Filtro.noAcreditados => 'No acreditados',
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
            onRefresh: () => ref.refresh(historialEventosProvider.future),
            child: visibles.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(child: Text('No hay eventos con este filtro')),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: visibles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) =>
                        _TarjetaHistorial(evento: visibles[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _TarjetaHistorial extends StatelessWidget {
  final EventoHistorial evento;
  const _TarjetaHistorial({required this.evento});

  @override
  Widget build(BuildContext context) {
    final situacion = evento.situacion;
    final (etiqueta, color) = switch (situacion) {
      SituacionHistorial.acreditado => (
          '+${evento.horasOtorgadas} h acreditadas',
          UniNorteColors.exito
        ),
      SituacionHistorial.enCurso => ('En curso', UniNorteColors.dorado),
      SituacionHistorial.noAcreditado => (
          'No acreditado',
          UniNorteColors.textoSecundario
        ),
      SituacionHistorial.cancelado => ('Cancelado', UniNorteColors.error),
    };

    final nota = switch (situacion) {
      SituacionHistorial.acreditado => null,
      SituacionHistorial.enCurso =>
        'Registrá tu entrada y tu salida para acreditar las horas.',
      SituacionHistorial.noAcreditado =>
        'No registraste entrada y salida, por eso no suma horas.',
      SituacionHistorial.cancelado =>
        'El evento fue cancelado: no acredita horas.',
    };

    final hhmm = DateFormat('HH:mm');
    final fecha = DateFormat('dd MMM yyyy', 'es').format(evento.fecha);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Solo los eventos vigentes son visibles para el alumno.
        onTap: situacion == SituacionHistorial.enCurso
            ? () => context.push(AppRoutes.detalleEventoPath(evento.id))
            : null,
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      etiqueta,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('$fecha · ${evento.horaInicio} - ${evento.horaFin}',
                  style: Theme.of(context).textTheme.bodyMedium),
              if (evento.ubicacion.isNotEmpty)
                Text(evento.ubicacion,
                    style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                'Entrada: ${evento.entradaEn == null ? '—' : hhmm.format(evento.entradaEn!)}'
                '  ·  Salida: ${evento.salidaEn == null ? '—' : hhmm.format(evento.salidaEn!)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (nota != null) ...[
                const SizedBox(height: 6),
                Text(nota, style: TextStyle(color: color, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}