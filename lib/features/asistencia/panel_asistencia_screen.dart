import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import 'asistencia_provider.dart';

class PanelAsistenciaScreen extends ConsumerStatefulWidget {
  /// Nulo para el validador (evento tomado de su perfil).
  final String? eventoId;
  const PanelAsistenciaScreen({super.key, this.eventoId});

  @override
  ConsumerState<PanelAsistenciaScreen> createState() =>
      _PanelAsistenciaScreenState();
}

class _PanelAsistenciaScreenState extends ConsumerState<PanelAsistenciaScreen> {
  static const _duracionPinMin = 5;

  Timer? _timer;
  int _tick = 0;

  String? _eventoId;
  String? _sesionId;
  String? _token;
  String? _pin;
  DateTime? _pinExpira;
  ResumenAsistencia? _resumen;

  bool _iniciando = true;
  bool _activandoPin = false;
  bool _sesionTerminada = false;
  String? _mensaje; // error o motivo de cierre

  bool get _esValidador => widget.eventoId == null;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _iniciar() async {
    setState(() {
      _iniciando = true;
      _sesionTerminada = false;
      _mensaje = null;
    });

    try {
      final evento =
          await ref.read(eventoPanelProvider(widget.eventoId).future);
      final sesionId = await AsistenciaService.abrirSesion(evento.id);
      if (!mounted) return;

      _eventoId = evento.id;
      _sesionId = sesionId;
      _tick = 0;
      setState(() => _iniciando = false);

      await _refrescar();
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refrescar(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _iniciando = false;
        _sesionTerminada = true;
        _mensaje = _mensajeLegible(e);
      });
    }
  }

  /// Cada 5 s pide un token nuevo; cada 10 s actualiza el quórum.
  Future<void> _refrescar() async {
    final sesionId = _sesionId;
    if (sesionId == null || _sesionTerminada) return;

    try {
      final token = await AsistenciaService.obtenerTokenQr(sesionId);
      if (!mounted) return;
      setState(() {
        _token = token;
        _mensaje = null;
      });

      _tick++;
      if (_tick % 2 == 1) {
        final resumen = await AsistenciaService.resumen(_eventoId!);
        if (!mounted) return;
        setState(() => _resumen = resumen);
      }
    } on PostgrestException catch (e) {
      // Error del servidor (sesión cerrada, acceso vencido): se detiene.
      _timer?.cancel();
      if (!mounted) return;
      setState(() {
        _sesionTerminada = true;
        _token = null;
        _pin = null;
        _mensaje = _mensajeLegible(e);
      });
    } catch (_) {
      // Fallo de red transitorio: se reintenta en el próximo ciclo.
      if (!mounted) return;
      setState(() => _mensaje = 'Sin conexión. Reintentando…');
    }
  }

  Future<void> _activarPin() async {
    setState(() => _activandoPin = true);
    try {
      final pin =
          await AsistenciaService.activarPin(_sesionId!, _duracionPinMin);
      if (!mounted) return;
      setState(() {
        _pin = pin;
        _pinExpira = DateTime.now().add(const Duration(minutes: _duracionPinMin));
      });
    } catch (e) {
      _snack(_mensajeLegible(e));
    } finally {
      if (mounted) setState(() => _activandoPin = false);
    }
  }

  Future<void> _confirmarCierre() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión de asistencia'),
        content: const Text(
          'El QR y el PIN dejarán de funcionar de inmediato. '
          'Los alumnos ya registrados no se ven afectados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await AsistenciaService.cerrarSesion(_sesionId!);
      _timer?.cancel();
      if (!mounted) return;
      setState(() {
        _sesionTerminada = true;
        _token = null;
        _pin = null;
        _mensaje = 'La sesión de asistencia fue cerrada.';
      });
    } catch (e) {
      _snack(_mensajeLegible(e));
    }
  }

  String _mensajeLegible(Object e) {
    final texto = e.toString().toLowerCase();
    if (texto.contains('no está abierta')) {
      return 'La sesión de asistencia ya no está abierta.';
    }
    if (texto.contains('permiso')) {
      return 'Tu acceso a este evento venció o fue desactivado.';
    }
    if (texto.contains('no existe o no está activo')) {
      return 'El evento no existe o no está activo.';
    }
    if (texto.contains('evento asignado')) {
      return 'Tu cuenta no tiene un evento asignado.';
    }
    return 'No se pudo completar la operación. Intentá nuevamente.';
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
    final eventoAsync = ref.watch(eventoPanelProvider(widget.eventoId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistencia'),
        actions: [
          if (_esValidador)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar sesión',
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
        ],
      ),
      body: eventoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _vistaMensaje(_mensajeLegible(e), reintentar: false),
        data: (evento) => _contenido(evento),
      ),
    );
  }

  Widget _contenido(EventoPanel evento) {
    if (_iniciando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sesionTerminada) {
      return _vistaMensaje(
        _mensaje ?? 'La sesión terminó.',
        reintentar: true,
      );
    }

    final pinVigente = _pin != null &&
        _pinExpira != null &&
        _pinExpira!.isAfter(DateTime.now());

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(evento.nombre, style: Theme.of(context).textTheme.headlineMedium),
        if (evento.vigenteHasta != null) ...[
          const SizedBox(height: 4),
          Text(
            'Tu acceso vence el '
            '${DateFormat('dd/MM HH:mm').format(evento.vigenteHasta!)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 20),

        // ---------------- QR rotativo ----------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('Código QR de asistencia',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Se renueva cada 5 segundos',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                if (_token == null)
                  const SizedBox(
                    height: 260,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: QrImageView(data: _token!, size: 260),
                  ),
                const SizedBox(height: 12),
                if (_token != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(_token),
                      tween: Tween(begin: 1, end: 0),
                      duration: const Duration(seconds: 5),
                      builder: (context, valor, _) => LinearProgressIndicator(
                        value: valor,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation(
                            UniNorteColors.dorado),
                      ),
                    ),
                  ),
                if (_mensaje != null) ...[
                  const SizedBox(height: 10),
                  Text(_mensaje!,
                      style: const TextStyle(
                          color: UniNorteColors.error, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---------------- Quórum ----------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Asistencia registrada',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(
                  _resumen == null
                      ? '—'
                      : '${_resumen!.presentes} de ${_resumen!.inscriptos} inscriptos',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _resumen?.porcentaje ?? 0,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                        const AlwaysStoppedAnimation(UniNorteColors.exito),
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
                Text('PIN de respaldo',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Para alumnos que no pueden escanear el QR. '
                  'Vence a los $_duracionPinMin minutos.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (pinVigente) ...[
                  Center(
                    child: Text(
                      _pin!,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 12,
                        color: UniNorteColors.azulMarino,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Vence a las '
                      '${DateFormat('HH:mm').format(_pinExpira!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _activandoPin ? null : _activarPin,
                  icon: const Icon(Icons.pin_outlined),
                  label: Text(pinVigente ? 'Generar un PIN nuevo' : 'Activar PIN'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        OutlinedButton.icon(
          onPressed: _confirmarCierre,
          style: OutlinedButton.styleFrom(
            foregroundColor: UniNorteColors.error,
            side: const BorderSide(color: UniNorteColors.error),
          ),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Cerrar sesión de asistencia'),
        ),
      ],
    );
  }

  Widget _vistaMensaje(String texto, {required bool reintentar}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline,
                color: UniNorteColors.textoSecundario, size: 48),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
            if (reintentar) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _iniciar,
                child: const Text('Abrir sesión nuevamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}