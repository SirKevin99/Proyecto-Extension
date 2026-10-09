import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../eventos/admin_eventos_provider.dart';
import 'admin_usuarios_provider.dart';

class AltaValidadorScreen extends ConsumerStatefulWidget {
  const AltaValidadorScreen({super.key});

  @override
  ConsumerState<AltaValidadorScreen> createState() =>
      _AltaValidadorScreenState();
}

class _AltaValidadorScreenState extends ConsumerState<AltaValidadorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();

  String? _eventoId;
  bool _intentoEnviar = false;
  bool _guardando = false;
  ValidadorCreado? _creado;

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    setState(() => _intentoEnviar = true);
    if (!_formKey.currentState!.validate() || _eventoId == null) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _guardando = true);

    try {
      final creado = await AdminUsuariosService.crearValidador(
        nombreCompleto: _nombreController.text.trim(),
        eventoId: _eventoId!,
      );
      if (!mounted) return;
      setState(() => _creado = creado);
    } on AltaException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.mensaje),
        backgroundColor: UniNorteColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _otroValidador() {
    _nombreController.clear();
    setState(() {
      _creado = null;
      _eventoId = null;
      _intentoEnviar = false;
    });
  }

  Future<void> _copiar(String texto, String que) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: texto));
    messenger.showSnackBar(SnackBar(
      content: Text('$que copiado'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alta de validador')),
      body: SafeArea(
        child: _creado == null ? _formulario() : _credenciales(_creado!),
      ),
    );
  }

  Widget _formulario() {
    final eventosAsync = ref.watch(adminEventosProvider);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'El validador es un acceso temporal para marcar la asistencia '
            'de un solo evento. Vence 1 hora después de que termina.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _nombreController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre de la persona designada',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v == null || v.trim().length < 3)
                ? 'Ingresá el nombre'
                : null,
          ),
          const SizedBox(height: 20),
          Text('Evento asignado',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          eventosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Column(
              children: [
                const Text('No se pudieron cargar los eventos'),
                OutlinedButton(
                  onPressed: () => ref.invalidate(adminEventosProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
            data: (todos) {
              final elegibles =
                  todos.where((e) => e.activo && !e.yaOcurrio).toList()
                    ..sort((a, b) => a.fecha.compareTo(b.fecha));

              if (elegibles.isEmpty) {
                return const Text(
                  'No hay eventos activos próximos. Creá uno primero.',
                );
              }
              final fmt = DateFormat('dd MMM yyyy', 'es');
              return RadioGroup<String>(
                groupValue: _eventoId,
                onChanged: (v) => setState(() => _eventoId = v),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in elegibles)
                      Card(
                        child: RadioListTile<String>(
                          value: e.id,
                          title: Text(e.nombre),
                          subtitle:
                              Text('${fmt.format(e.fecha)} · ${e.horaInicio}'),
                        ),
                      ),
                    if (_intentoEnviar && _eventoId == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: Text('Elegí un evento',
                            style: TextStyle(
                                color: UniNorteColors.error, fontSize: 12)),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: UniNorteColors.azulMarino,
                    ),
                  )
                : const Text('Crear validador'),
          ),
        ],
      ),
    );
  }

  Widget _credenciales(ValidadorCreado v) {
    final vence = DateFormat('dd/MM/yyyy HH:mm').format(v.vigenteHasta);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.verified_user, color: UniNorteColors.exito, size: 56),
        const SizedBox(height: 12),
        Text('Validador creado',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: UniNorteColors.dorado.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Anotá o copiá estos datos ahora. La clave se muestra una sola '
            'vez y no se puede recuperar.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        _Dato(
          etiqueta: 'Código de acceso',
          valor: v.codigo,
          onCopiar: () => _copiar(v.codigo, 'Código'),
        ),
        const SizedBox(height: 10),
        _Dato(
          etiqueta: 'Clave',
          valor: v.password,
          onCopiar: () => _copiar(v.password, 'Clave'),
        ),
        const SizedBox(height: 10),
        Text('Vence el $vence',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _otroValidador,
          child: const Text('Crear otro validador'),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final VoidCallback onCopiar;

  const _Dato({
    required this.etiqueta,
    required this.valor,
    required this.onCopiar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiqueta, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  SelectableText(
                    valor,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copiar',
              icon: const Icon(Icons.copy_outlined),
              onPressed: onCopiar,
            ),
          ],
        ),
      ),
    );
  }
}