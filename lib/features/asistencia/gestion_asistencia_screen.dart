import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../home/home_provider.dart';
import 'gestion_asistencia_provider.dart';

enum _Filtro { todos, presentes, ausentes }

class GestionAsistenciaScreen extends ConsumerStatefulWidget {
  final String eventoId;
  const GestionAsistenciaScreen({super.key, required this.eventoId});

  @override
  ConsumerState<GestionAsistenciaScreen> createState() =>
      _GestionAsistenciaScreenState();
}

class _GestionAsistenciaScreenState
    extends ConsumerState<GestionAsistenciaScreen> {
  final Set<String> _seleccion = {};
  String _busqueda = '';
  _Filtro _filtro = _Filtro.todos;
  bool _procesando = false;

  List<InscriptoAsistencia> _visibles(List<InscriptoAsistencia> todos) {
    final q = _busqueda.trim().toLowerCase();
    return todos.where((i) {
      final coincideFiltro = switch (_filtro) {
        _Filtro.todos => true,
        _Filtro.presentes => i.presente,
        _Filtro.ausentes => !i.presente,
      };
      final coincideTexto =
          q.isEmpty || i.nombre.toLowerCase().contains(q) || i.ci.contains(q);
      return coincideFiltro && coincideTexto;
    }).toList();
  }

  Future<void> _aplicar(List<String> ids, {required bool confirmada}) async {
    if (ids.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);

    final accion = confirmada ? 'validar' : 'revocar';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${accion[0].toUpperCase()}${accion.substring(1)} asistencia'),
        content: Text(
          confirmada
              ? 'Se marcará como presente a ${ids.length} alumno(s). '
                  'Queda registrado tu usuario y la hora.'
              : 'Se revocará la asistencia de ${ids.length} alumno(s). '
                  'Dejarán de sumar horas y su certificado quedará anulado.',
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

    
    setState(() => _procesando = true);
    try {
      final filas = await CorreccionService.corregir(ids, confirmada: confirmada);
      ref.invalidate(gestionAsistenciaProvider(widget.eventoId));
      ref.invalidate(metricasAdminProvider);
      if (!mounted) return;
      setState(_seleccion.clear);
      messenger.showSnackBar(SnackBar(
        content: Text('Asistencia actualizada ($filas)'),
        backgroundColor: UniNorteColors.exito,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo actualizar la asistencia. Intentá nuevamente.'),
        backgroundColor: UniNorteColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(gestionAsistenciaProvider(widget.eventoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Corregir asistencia')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: UniNorteColors.error, size: 48),
              const SizedBox(height: 12),
              const Text('No se pudieron cargar los inscriptos'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.invalidate(gestionAsistenciaProvider(widget.eventoId)),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        data: _contenido,
      ),
      bottomNavigationBar: _seleccion.isEmpty ? null : _barraLote(),
    );
  }

  Widget _contenido(GestionAsistenciaData datos) {
    final visibles = _visibles(datos.inscriptos);
    final todosSeleccionados = visibles.isNotEmpty &&
        visibles.every((i) => _seleccion.contains(i.inscripcionId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(datos.eventoNombre,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text('${datos.presentes} de ${datos.inscriptos.length} presentes',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar por nombre o C.I.',
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
                        _Filtro.presentes => 'Presentes',
                        _Filtro.ausentes => 'Ausentes',
                      }),
                      selected: _filtro == f,
                      selectedColor: UniNorteColors.dorado,
                      backgroundColor: Colors.white,
                      onSelected: (_) => setState(() => _filtro = f),
                    ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: visibles.isEmpty
                      ? null
                      : () => setState(() {
                            final ids = visibles.map((i) => i.inscripcionId);
                            if (todosSeleccionados) {
                              _seleccion.removeAll(ids);
                            } else {
                              _seleccion.addAll(ids);
                            }
                          }),
                  child: Text(todosSeleccionados
                      ? 'Quitar selección de los visibles'
                      : 'Seleccionar todos los visibles'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.refresh(gestionAsistenciaProvider(widget.eventoId).future),
            child: visibles.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(child: Text('No hay inscriptos con estos filtros')),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: visibles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _fila(visibles[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _fila(InscriptoAsistencia i) {
    final seleccionado = _seleccion.contains(i.inscripcionId);
    final metodo = switch (i.metodo) {
      'qr' => 'QR',
      'pin' => 'PIN',
      'manual' => 'Manual',
      _ => null,
    };

    final detalle = i.presente
        ? [
            'C.I. ${i.ci}',
            ?metodo,
            if (i.fechaMarcaje != null)
              DateFormat('dd/MM HH:mm').format(i.fechaMarcaje!),
          ].join(' · ')
        : 'C.I. ${i.ci} · Sin asistencia';

    return Card(
      child: ListTile(
        leading: Checkbox(
          value: seleccionado,
          onChanged: (v) => setState(() {
            if (v == true) {
              _seleccion.add(i.inscripcionId);
            } else {
              _seleccion.remove(i.inscripcionId);
            }
          }),
        ),
        title: Text(i.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(detalle),
        trailing: i.presente
            ? IconButton(
                tooltip: 'Revocar asistencia',
                icon: const Icon(Icons.cancel_outlined, color: UniNorteColors.error),
                onPressed: _procesando
                    ? null
                    : () => _aplicar([i.inscripcionId], confirmada: false),
              )
            : IconButton(
                tooltip: 'Validar asistencia',
                icon: const Icon(Icons.check_circle_outline,
                    color: UniNorteColors.exito),
                onPressed: _procesando
                    ? null
                    : () => _aplicar([i.inscripcionId], confirmada: true),
              ),
      ),
    );
  }

  Widget _barraLote() {
    final ids = _seleccion.toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _procesando ? null : () => _aplicar(ids, confirmada: false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: UniNorteColors.error,
                  side: const BorderSide(color: UniNorteColors.error),
                ),
                child: Text('Revocar (${ids.length})'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed:
                    _procesando ? null : () => _aplicar(ids, confirmada: true),
                child: Text('Validar (${ids.length})'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}