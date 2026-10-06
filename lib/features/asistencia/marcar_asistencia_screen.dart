import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../eventos/eventos_provider.dart';
import '../home/home_provider.dart';
import 'asistencia_provider.dart';

class MarcarAsistenciaScreen extends ConsumerStatefulWidget {
  final String eventoId;
  const MarcarAsistenciaScreen({super.key, required this.eventoId});

  @override
  ConsumerState<MarcarAsistenciaScreen> createState() =>
      _MarcarAsistenciaScreenState();
}

class _MarcarAsistenciaScreenState
    extends ConsumerState<MarcarAsistenciaScreen> {
  final _tokenController = TextEditingController();
  final _pinController = TextEditingController();

  bool _enviando = false;
  bool _registrada = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _pegar() async {
    final datos = await Clipboard.getData(Clipboard.kTextPlain);
    if (datos?.text != null) {
      _tokenController.text = datos!.text!.trim();
    }
  }

  void _exito() {
    ref.invalidate(detalleEventoProvider(widget.eventoId));
    ref.invalidate(progresoEstudianteProvider);
    setState(() => _registrada = true);
  }

  Future<void> _marcarConQr() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _snack('Pegá el código del QR');
      return;
    }
    setState(() => _enviando = true);
    try {
      await AsistenciaService.marcarQr(token);
      _exito();
    } on PostgrestException catch (e) {
      _snack(_mensajeServidor(e.message));
    } catch (_) {
      _snack('No se pudo registrar. Revisá tu conexión.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _marcarConPin() async {
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      _snack('El PIN tiene 4 dígitos');
      return;
    }
    setState(() => _enviando = true);
    try {
      final resultado =
          await AsistenciaService.marcarPin(widget.eventoId, pin);
      switch (resultado) {
        case 'ok':
          _exito();
        case 'incorrecto':
          _snack('PIN incorrecto. Tenés 5 intentos en total.');
        case 'bloqueado':
          _snack('Superaste los intentos. Pedí un PIN nuevo al organizador.');
        case 'pin_no_activo':
          _snack('No hay un PIN activo. Pedíselo al organizador.');
        default:
          _snack('Respuesta inesperada del servidor.');
      }
    } on PostgrestException catch (e) {
      _snack(_mensajeServidor(e.message));
    } catch (_) {
      _snack('No se pudo registrar. Revisá tu conexión.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Los mensajes del servidor ya están en español y pensados para el
  /// usuario; solo se filtran los que no deberían mostrarse crudos.
  String _mensajeServidor(String mensaje) {
    const conocidos = [
      'No estás inscripto',
      'Tu asistencia ya fue registrada',
      'Código QR inválido',
      'El código QR expiró',
      'La sesión de asistencia no está abierta',
      'No hay una sesión de asistencia abierta',
      'Solo los alumnos',
    ];
    for (final c in conocidos) {
      if (mensaje.contains(c)) return mensaje;
    }
    return 'No se pudo registrar la asistencia. Intentá nuevamente.';
  }

  void _snack(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: UniNorteColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marcar asistencia')),
      body: SafeArea(
        child: _registrada ? _vistaExito() : _vistaFormulario(),
      ),
    );
  }

  Widget _vistaExito() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, color: UniNorteColors.exito, size: 72),
            const SizedBox(height: 16),
            Text('¡Asistencia registrada!',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Tus horas se acreditaron a tu progreso.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.pop(),
              child: const Text('Volver al evento'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaFormulario() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Código del QR',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Pegá el código que corresponde al QR proyectado. '
                  'Cambia cada 5 segundos, así que hacelo rápido.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _tokenController,
                  autocorrect: false,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Código del QR',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: 'Pegar',
                      onPressed: _pegar,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: _enviando ? null : _marcarConQr,
                  child: const Text('Registrar con QR'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('PIN de respaldo',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Si no podés usar el QR, pedile el PIN de 4 dígitos al '
                  'organizador.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 28, letterSpacing: 10),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '0000',
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _enviando ? null : _marcarConPin,
                  child: const Text('Registrar con PIN'),
                ),
              ],
            ),
          ),
        ),
        if (_enviando) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}