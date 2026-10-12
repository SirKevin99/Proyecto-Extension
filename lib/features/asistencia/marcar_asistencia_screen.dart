import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../eventos/eventos_provider.dart';
import '../home/home_provider.dart';
import 'asistencia_provider.dart';

/// El alumno registra su entrada o su salida escaneando el QR proyectado
/// (o con el PIN de respaldo). Qué registro corresponde lo decide el
/// servidor según el modo que habilitó el validador.
class MarcarAsistenciaScreen extends ConsumerStatefulWidget {
  final String eventoId;
  const MarcarAsistenciaScreen({super.key, required this.eventoId});

  @override
  ConsumerState<MarcarAsistenciaScreen> createState() =>
      _MarcarAsistenciaScreenState();
}

class _MarcarAsistenciaScreenState
    extends ConsumerState<MarcarAsistenciaScreen> {
  final _pinController = TextEditingController();

  MobileScannerController? _scanner;
  bool _escaneando = false;
  bool _enviando = false;

  /// 'entrada' | 'salida' cuando se acaba de registrar algo.
  String? _ultimoRegistro;

  @override
  void dispose() {
    _pinController.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Cámara
  // ---------------------------------------------------------------------

  void _iniciarEscaneo() {
    _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
    setState(() => _escaneando = true);
  }

  void _detenerEscaneo() {
    final scanner = _scanner;
    _scanner = null;
    if (mounted) setState(() => _escaneando = false);
    // Se libera después de quitar el widget del árbol.
    if (scanner != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => scanner.dispose());
    }
  }

  void _alDetectar(BarcodeCapture captura) {
    if (_enviando) return;
    final token = captura.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (token == null || token.isEmpty) return;

    _detenerEscaneo();
    _marcarConQr(token.trim());
  }

  // ---------------------------------------------------------------------
  // Registro
  // ---------------------------------------------------------------------

  /// Qué se acaba de registrar, según el estado previo del alumno.
  String _modoEsperado() {
    final previo = ref.read(miMarcajeProvider(widget.eventoId)).valueOrNull;
    return previo?.entradaEn == null ? 'entrada' : 'salida';
  }

  void _exito(String modo) {
    ref.invalidate(miMarcajeProvider(widget.eventoId));
    ref.invalidate(detalleEventoProvider(widget.eventoId));
    ref.invalidate(progresoEstudianteProvider);
    if (mounted) setState(() => _ultimoRegistro = modo);
  }

  Future<void> _marcarConQr(String token) async {
    final partes = token.split(':');
    final modoQr = partes.length == 4 ? partes[1] : null;

    setState(() => _enviando = true);
    try {
      await AsistenciaService.marcarQr(token);
      _exito(modoQr == 'salida' ? 'salida' : 'entrada');
    } on PostgrestException catch (e) {
      _snack(_mensajeServidor(e.message));
    } catch (_) {
      _snack('No se pudo registrar. Revisá tu conexión.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _marcarConPin() async {
    if (_enviando) return;
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      _snack('El PIN tiene 4 dígitos');
      return;
    }

    final modo = _modoEsperado();
    setState(() => _enviando = true);
    try {
      final resultado = await AsistenciaService.marcarPin(widget.eventoId, pin);
      switch (resultado) {
        case 'ok':
          _pinController.clear();
          _exito(modo);
        case 'incorrecto':
          _pinController.clear();
          _snack('PIN incorrecto. Tenés 5 intentos en total.');
        case 'bloqueado':
          _snack('Superaste los intentos. Pedí un PIN nuevo al organizador.');
        case 'pin_no_activo':
          _pinController.clear();
          _snack('El PIN venció o no hay uno activo. Pedí uno nuevo.');
        case 'registro_cerrado':
          _snack('El registro de entrada o salida no está habilitado ahora.');
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
      'Tu entrada ya fue registrada',
      'Tu salida ya fue registrada',
      'Primero tenés que registrar tu entrada',
      'Código QR inválido',
      'El código QR expiró',
      'Ese código QR corresponde a otro registro',
      'El registro de entrada o salida no está habilitado',
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

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final marcaje = ref.watch(miMarcajeProvider(widget.eventoId)).valueOrNull;

    Widget cuerpo;
    if (_ultimoRegistro != null) {
      cuerpo = _vistaExito(_ultimoRegistro!);
    } else if (marcaje != null && marcaje.completo) {
      cuerpo = _vistaCompleta(marcaje);
    } else {
      cuerpo = _vistaFormulario(marcaje);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Marcar asistencia')),
      body: SafeArea(child: cuerpo),
    );
  }

  Widget _vistaExito(String modo) {
    final esSalida = modo == 'salida';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, color: UniNorteColors.exito, size: 72),
            const SizedBox(height: 16),
            Text(
              esSalida ? '¡Asistencia completa!' : '¡Entrada registrada!',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              esSalida
                  ? 'Registraste tu entrada y tu salida. Tus horas se '
                        'acreditaron a tu progreso.'
                  : 'Recordá registrar también tu salida al final del '
                        'evento para que se acrediten tus horas.',
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

  Widget _vistaCompleta(MiMarcaje marcaje) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, color: UniNorteColors.exito, size: 72),
            const SizedBox(height: 16),
            Text(
              'Tu asistencia está completa',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _estadoMarcaje(marcaje),
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

  Widget _estadoMarcaje(MiMarcaje? marcaje) {
    final hhmm = DateFormat('HH:mm');
    Widget fila(String titulo, DateTime? momento) {
      final hecho = momento != null;
      return Row(
        children: [
          Icon(
            hecho ? Icons.check_circle : Icons.radio_button_unchecked,
            color: hecho
                ? UniNorteColors.exito
                : UniNorteColors.textoSecundario,
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            momento == null
                ? 'Pendiente'
                : 'Registrada a las ${hhmm.format(momento)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }

    return Column(
      children: [
        fila('Entrada', marcaje?.entradaEn),
        const SizedBox(height: 10),
        fila('Salida', marcaje?.salidaEn),
      ],
    );
  }

  Widget _vistaFormulario(MiMarcaje? marcaje) {
    final sinEntrada = marcaje?.entradaEn == null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ---------------- Estado ----------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu asistencia',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _estadoMarcaje(marcaje),
                const SizedBox(height: 12),
                Text(
                  sinEntrada
                      ? 'Escaneá el QR cuando el organizador habilite la '
                            'entrada.'
                      : 'Escaneá el QR cuando el organizador habilite la '
                            'salida.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---------------- QR con cámara ----------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Escanear QR',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Apuntá la cámara al QR proyectado. Cambia cada minuto.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                if (_escaneando && _scanner != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 320,
                      child: MobileScanner(
                        controller: _scanner!,
                        onDetect: _alDetectar,
                        errorBuilder: (context, error) => _errorCamara(),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                if (_escaneando)
                  OutlinedButton.icon(
                    onPressed: _detenerEscaneo,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar escaneo'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _enviando ? null : _iniciarEscaneo,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(
                      sinEntrada
                          ? 'Escanear para registrar entrada'
                          : 'Escanear para registrar salida',
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---------------- PIN de respaldo ----------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'PIN de respaldo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Si no podés escanear, pedile el PIN al organizador. '
                  'Dura solo 20 segundos: tenelo listo para ingresarlo.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  enabled: !_enviando,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 28, letterSpacing: 10),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '0000',
                  ),
                  onChanged: (valor) {
                    if (valor.length == 4) _marcarConPin();
                  },
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

  Widget _errorCamara() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: const Text(
        'No se pudo usar la cámara. Revisá el permiso del navegador o del '
        'dispositivo, o usá el PIN de respaldo.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white),
      ),
    );
  }
}
