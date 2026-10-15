import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../home/home_provider.dart';
import 'gestion_asistencia_provider.dart';

enum _Filtro { todos, completos, soloEntrada, sinAsistencia }

/// Acciones posibles sobre un alumno, según su estado.
enum _AccionFila {
  registrarEntrada,
  registrarSalida,
  registrarAmbos,
  revocarSalida,
  revocarEntrada,
}

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
        _Filtro.completos => i.completo,
        _Filtro.soloEntrada => i.tieneEntrada && !i.completo,
        _Filtro.sinAsistencia => !i.tieneEntrada,
      };
      final coincideTexto =
          q.isEmpty || i.nombre.toLowerCase().contains(q) || i.ci.contains(q);
      return coincideFiltro && coincideTexto;
    }).toList();
  }

  // ---------------------------------------------------------------------
  // Correcciones
  // ---------------------------------------------------------------------

  String _descripcion(String campo, bool registrar, int n) {
    final alumnos = '$n alumno(s)';
    if (registrar) {
      final que = switch (campo) {
        'entrada' => 'la entrada',
        'salida' => 'la salida',
        _ => 'la entrada (si falta) y la salida',
      };
      return 'Se registrará $que de $alumnos con la hora actual. Queda '
          'guardado tu usuario, la hora y el motivo.';
    }
    final que = switch (campo) {
      'entrada' => 'la entrada y también la salida',
      'salida' => 'la salida',
      _ => 'la entrada y la salida',
    };
    return 'Se revocará $que de $alumnos. Dejarán de sumar horas y su '
        'certificado quedará anulado. Queda guardado tu usuario, la hora y '
        'el motivo.';
  }

  Future<void> _aplicar(
    List<String> ids, {
    required String campo,
    required bool registrar,
  }) async {
    if (ids.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);

    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoMotivo(
        titulo: registrar ? 'Registrar asistencia' : 'Revocar asistencia',
        descripcion: _descripcion(campo, registrar, ids.length),
      ),
    );
    if (motivo == null) return;

    setState(() => _procesando = true);
    try {
      final filas = await CorreccionService.corregir(
        ids,
        campo: campo,
        registrar: registrar,
        motivo: motivo,
      );
      ref.invalidate(gestionAsistenciaProvider(widget.eventoId));
      ref.invalidate(metricasAdminProvider);
      if (!mounted) return;
      setState(_seleccion.clear);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            filas == 0
                ? 'No hubo cambios que aplicar'
                : 'Asistencia actualizada ($filas)',
          ),
          backgroundColor: UniNorteColors.exito,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on PostgrestException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: UniNorteColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo actualizar la asistencia. Intentá nuevamente.',
          ),
          backgroundColor: UniNorteColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _accionFila(InscriptoAsistencia i, _AccionFila accion) {
    final (campo, registrar) = switch (accion) {
      _AccionFila.registrarEntrada => ('entrada', true),
      _AccionFila.registrarSalida => ('salida', true),
      _AccionFila.registrarAmbos => ('ambos', true),
      _AccionFila.revocarSalida => ('salida', false),
      _AccionFila.revocarEntrada => ('entrada', false),
    };
    _aplicar([i.inscripcionId], campo: campo, registrar: registrar);
  }

  // ---------------------------------------------------------------------
  // Salida anticipada
  // ---------------------------------------------------------------------

  Future<void> _autorizarSalidaAnticipada() async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Autorizar salida anticipada'),
        content: const Text(
          'El validador podrá habilitar la salida antes de los 15 minutos '
          'previos a la hora de fin. El plazo para que los alumnos marquen '
          'no cambia: sigue venciendo 15 minutos después de la hora de fin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Autorizar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesando = true);
    try {
      await CorreccionService.autorizarSalidaAnticipada(widget.eventoId);
      ref.invalidate(gestionAsistenciaProvider(widget.eventoId));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Salida anticipada autorizada'),
          backgroundColor: UniNorteColors.exito,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on PostgrestException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: UniNorteColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo autorizar. Intentá nuevamente.'),
          backgroundColor: UniNorteColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(gestionAsistenciaProvider(widget.eventoId));
    // Un evento cancelado conserva las asistencias solo como historial.
    final soloLectura = async.valueOrNull?.esCancelado ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Corregir asistencia')),
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
      bottomNavigationBar: (_seleccion.isEmpty || soloLectura)
          ? null
          : _barraLote(),
    );
  }

  Widget _contenido(GestionAsistenciaData datos) {
    final visibles = _visibles(datos.inscriptos);
    final soloLectura = datos.esCancelado;
    final todosSeleccionados =
        visibles.isNotEmpty &&
        visibles.every((i) => _seleccion.contains(i.inscripcionId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                datos.eventoNombre,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                '${datos.completos} completos · ${datos.soloEntrada} solo '
                'entrada · ${datos.sinAsistencia} sin asistencia '
                '(de ${datos.inscriptos.length})',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (soloLectura) ...[
                const SizedBox(height: 10),
                const _Aviso(
                  icono: Icons.cancel_outlined,
                  color: UniNorteColors.error,
                  texto:
                      'Evento cancelado. Las asistencias se conservan como '
                      'historial y no acreditan horas ni certificados.',
                ),
              ],
              if (datos.salidaAnticipadaEn != null) ...[
                const SizedBox(height: 10),
                _Aviso(
                  icono: Icons.verified_outlined,
                  color: UniNorteColors.exito,
                  texto:
                      'Salida anticipada autorizada a las '
                      '${DateFormat('HH:mm').format(datos.salidaAnticipadaEn!)}.',
                ),
              ],
              if (datos.puedeAutorizarSalidaAnticipada) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _procesando ? null : _autorizarSalidaAnticipada,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Autorizar salida anticipada'),
                  ),
                ),
              ],
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
                        _Filtro.completos => 'Completos',
                        _Filtro.soloEntrada => 'Solo entrada',
                        _Filtro.sinAsistencia => 'Sin asistencia',
                      }),
                      selected: _filtro == f,
                      selectedColor: UniNorteColors.dorado,
                      backgroundColor: Colors.white,
                      onSelected: (_) => setState(() => _filtro = f),
                    ),
                ],
              ),
              if (!soloLectura)
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
                    child: Text(
                      todosSeleccionados
                          ? 'Quitar selección de los visibles'
                          : 'Seleccionar todos los visibles',
                    ),
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
                      Center(
                        child: Text('No hay inscriptos con estos filtros'),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: visibles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _fila(visibles[i], soloLectura),
                  ),
          ),
        ),
      ],
    );
  }

  String _linea(String titulo, DateTime? momento, String? metodo) {
    if (momento == null) return '$titulo: —';
    final etiqueta = switch (metodo) {
      'qr' => 'QR',
      'pin' => 'PIN',
      'manual' => 'Manual',
      _ => null,
    };
    final hora = DateFormat('dd/MM HH:mm').format(momento);
    return etiqueta == null ? '$titulo: $hora' : '$titulo: $hora · $etiqueta';
  }

  Widget _fila(InscriptoAsistencia i, bool soloLectura) {
    final seleccionado = _seleccion.contains(i.inscripcionId);

    final acciones = <_AccionFila, String>{
      if (!i.tieneEntrada) ...{
        _AccionFila.registrarEntrada: 'Registrar entrada',
        _AccionFila.registrarAmbos: 'Registrar entrada y salida',
      } else if (!i.completo) ...{
        _AccionFila.registrarSalida: 'Registrar salida',
        _AccionFila.revocarEntrada: 'Revocar entrada (anula también la salida)',
      } else ...{
        _AccionFila.revocarSalida: 'Revocar salida',
        _AccionFila.revocarEntrada: 'Revocar entrada (anula también la salida)',
      },
    };

    return Card(
      child: ListTile(
        leading: soloLectura
            ? null
            : Checkbox(
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i.migrado ? 'C.I. ${i.ci} · Migrado' : 'C.I. ${i.ci}'),
            Text(_linea('Entrada', i.entradaEn, i.metodoEntrada)),
            Text(_linea('Salida', i.salidaEn, i.metodoSalida)),
          ],
        ),
        isThreeLine: true,
        trailing: soloLectura
            ? null
            : PopupMenuButton<_AccionFila>(
                tooltip: 'Corregir asistencia',
                enabled: !_procesando,
                onSelected: (a) => _accionFila(i, a),
                itemBuilder: (_) => [
                  for (final e in acciones.entries)
                    PopupMenuItem(value: e.key, child: Text(e.value)),
                ],
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
                onPressed: _procesando
                    ? null
                    : () => _aplicar(ids, campo: 'ambos', registrar: false),
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
                onPressed: _procesando
                    ? null
                    : () => _aplicar(ids, campo: 'ambos', registrar: true),
                child: Text('Completar (${ids.length})'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String texto;

  const _Aviso({required this.icono, required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Pide el motivo (obligatorio, mínimo 5 caracteres) antes de corregir.
/// Se cierra con el texto del motivo, o `null` si se cancela.
class _DialogoMotivo extends StatefulWidget {
  final String titulo;
  final String descripcion;

  const _DialogoMotivo({required this.titulo, required this.descripcion});

  @override
  State<_DialogoMotivo> createState() => _DialogoMotivoState();
}

class _DialogoMotivoState extends State<_DialogoMotivo> {
  final _motivo = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _motivo.text.trim();
    if (texto.length < 5) {
      setState(() => _error = 'Indicá el motivo (mínimo 5 caracteres)');
      return;
    }
    Navigator.of(context).pop(texto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.descripcion),
          const SizedBox(height: 16),
          TextField(
            controller: _motivo,
            autofocus: true,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Motivo de la corrección',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _confirmar, child: const Text('Confirmar')),
      ],
    );
  }
}
