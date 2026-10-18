import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import 'asistencia_provider.dart';

/// Panel del validador: habilita la entrada o la salida (pidiendo su
/// contraseña), muestra el QR rotativo y el PIN de respaldo.
class PanelAsistenciaScreen extends ConsumerStatefulWidget {
  const PanelAsistenciaScreen({super.key});

  @override
  ConsumerState<PanelAsistenciaScreen> createState() =>
      _PanelAsistenciaScreenState();
}

class _PanelAsistenciaScreenState extends ConsumerState<PanelAsistenciaScreen> {
  static const _duracionPinSeg = 20;
  static const _ventanaQrSeg = 60;

  Timer? _timer;
  int _segundos = 0;

  String? _eventoId;
  String? _sesionId;

  // Modo activo según el servidor ('entrada' | 'salida' | null).
  String? _modo;
  DateTime? _modoHasta;

  String? _token;
  int? _tokenVentana;
  bool _pidiendoToken = false;
  bool _sincronizando = false;

  String? _pin;
  DateTime? _pinExpira;

  ResumenAsistencia? _resumen;

  bool _iniciando = true;
  bool _activandoPin = false;
  bool _sesionTerminada = false;
  String? _mensaje; // error de conexión o motivo de cierre

  int get _ahoraEpoch => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  bool get _pinVigente =>
      _pin != null && _pinExpira != null && _pinExpira!.isAfter(DateTime.now());

  int get _segundosPin => _pinExpira == null
      ? 0
      : _pinExpira!.difference(DateTime.now()).inSeconds.clamp(0, 999).toInt();

  int get _segundosQr => _tokenVentana == null
      ? 0
      : ((_tokenVentana! + 1) * _ventanaQrSeg - _ahoraEpoch)
            .clamp(0, _ventanaQrSeg)
            .toInt();

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

  // ---------------------------------------------------------------------
  // Ciclo de vida de la sesión
  // ---------------------------------------------------------------------

  Future<void> _iniciar() async {
    setState(() {
      _iniciando = true;
      _sesionTerminada = false;
      _mensaje = null;
    });

    try {
      final evento = await ref.read(eventoPanelProvider(null).future);
      final sesionId = await AsistenciaService.abrirSesion(evento.id);
      if (!mounted) return;

      _eventoId = evento.id;
      _sesionId = sesionId;
      _segundos = 0;
      _limpiarModo();
      setState(() => _iniciando = false);

      await _sincronizar();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tic());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _iniciando = false;
        _sesionTerminada = true;
        _mensaje = _mensajeLegible(e);
      });
    }
  }

  void _limpiarModo() {
    _modo = null;
    _modoHasta = null;
    _token = null;
    _tokenVentana = null;
    _pin = null;
    _pinExpira = null;
  }

  void _terminarSesion(String mensaje) {
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _limpiarModo();
      _sesionTerminada = true;
      _mensaje = mensaje;
    });
  }

  /// Corre cada segundo: renueva el QR al cambiar la ventana, oculta el PIN
  /// al vencer y sincroniza con el servidor cada 10 s.
  void _tic() {
    if (!mounted || _sesionTerminada || _sesionId == null) return;
    _segundos++;

    // El plazo del modo activo terminó.
    if (_modo != null &&
        _modoHasta != null &&
        DateTime.now().isAfter(_modoHasta!)) {
      _limpiarModo();
      _mensaje = 'El plazo de registro terminó.';
    }

    // QR: pedir uno nuevo cuando vence la ventana del actual.
    if (_modo != null &&
        (_tokenVentana == null ||
            _ahoraEpoch >= (_tokenVentana! + 1) * _ventanaQrSeg)) {
      _pedirToken();
    }

    // PIN: se oculta al vencer.
    if (_pin != null && !_pinVigente) {
      _pin = null;
      _pinExpira = null;
    }

    if (_segundos % 10 == 0) _sincronizar();

    setState(() {});
  }

  /// Trae del servidor el modo activo y el quórum.
  Future<void> _sincronizar() async {
    final sesionId = _sesionId;
    final eventoId = _eventoId;
    if (sesionId == null || eventoId == null || _sincronizando) return;
    _sincronizando = true;

    try {
      final resultados = await Future.wait([
        AsistenciaService.estadoSesion(sesionId),
        AsistenciaService.resumen(eventoId),
      ]);
      if (!mounted) return;

      final estado = resultados[0] as EstadoSesion;
      final resumen = resultados[1] as ResumenAsistencia;

      if (!estado.abierta) {
        _terminarSesion('La sesión de asistencia ya no está abierta.');
        return;
      }

      setState(() {
        _resumen = resumen;
        if (estado.modo != _modo) {
          // Cambió el modo (o se cerró desde otro lado): se descartan
          // el QR y el PIN del modo anterior.
          _token = null;
          _tokenVentana = null;
          _pin = null;
          _pinExpira = null;
        }
        _modo = estado.modo;
        _modoHasta = estado.modoHasta;
        _mensaje = null;
      });
    } on PostgrestException catch (e) {
      _terminarSesion(_mensajeLegible(e));
    } catch (_) {
      if (mounted) setState(() => _mensaje = 'Sin conexión. Reintentando…');
    } finally {
      _sincronizando = false;
    }
  }

  Future<void> _pedirToken() async {
    final sesionId = _sesionId;
    if (sesionId == null || _pidiendoToken) return;
    _pidiendoToken = true;

    try {
      final token = await AsistenciaService.obtenerTokenQr(sesionId);
      if (!mounted) return;
      final partes = token.split(':');
      setState(() {
        _token = token;
        _tokenVentana = partes.length == 4 ? int.tryParse(partes[2]) : null;
        _mensaje = null;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final texto = e.message.toLowerCase();
      if (texto.contains('no está abierta') || texto.contains('permiso')) {
        _terminarSesion(_mensajeLegible(e));
      } else {
        // No hay modo activo o el plazo terminó: se vuelve a la elección.
        setState(() {
          _limpiarModo();
          _mensaje = 'El registro ya no está activo.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _mensaje = 'Sin conexión. Reintentando…');
    } finally {
      _pidiendoToken = false;
    }
  }

  // ---------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------

  Future<void> _habilitar(String modo) async {
    final sesionId = _sesionId;
    if (sesionId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoClave(
        sesionId: sesionId,
        modo: modo,
        reemplaza: _modo != null && _modo != modo,
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _token = null;
      _tokenVentana = null;
      _pin = null;
      _pinExpira = null;
      _mensaje = null;
    });
    await _sincronizar();
    _pedirToken();
  }

  Future<void> _activarPin() async {
    final sesionId = _sesionId;
    if (sesionId == null) return;

    setState(() => _activandoPin = true);
    try {
      final pin = await AsistenciaService.activarPin(sesionId);
      if (!mounted) return;
      setState(() {
        _pin = pin.codigo;
        // Se cuenta desde acá con los segundos que informa el servidor:
        // no depende del reloj del dispositivo. Si otro validador ya lo
        // mostró, le quedan menos de 20 s.
        _pinExpira = DateTime.now().add(
          Duration(
            seconds: pin.segundosRestantes.clamp(0, _duracionPinSeg).toInt(),
          ),
        );
      });
    } catch (e) {
      _snack(_mensajeLegible(e));
    } finally {
      if (mounted) setState(() => _activandoPin = false);
    }
  }

  Future<void> _cerrarRegistro() async {
    final nombre = _modo == 'salida' ? 'salida' : 'entrada';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cerrar el registro de $nombre'),
        content: const Text(
          'El QR y el PIN dejarán de funcionar de inmediato. '
          'Los alumnos ya registrados no se ven afectados. '
          'Para volver a habilitarlo vas a necesitar tu contraseña.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cerrar registro'),
          ),
        ],
      ),
    );
    if (confirmar != true || _sesionId == null) return;

    try {
      await AsistenciaService.cerrarModo(_sesionId!);
      if (!mounted) return;
      setState(() {
        _limpiarModo();
        _mensaje = null;
      });
      _sincronizar();
    } catch (e) {
      _snack(_mensajeLegible(e));
    }
  }

  Future<void> _confirmarCierreSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finalizar la sesión de asistencia'),
        content: const Text(
          'Se cierra el registro de entrada y de salida para TODOS los '
          'validadores del evento. El QR y el PIN dejarán de funcionar de '
          'inmediato. Los alumnos ya registrados no se ven afectados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Finalizar sesión'),
          ),
        ],
      ),
    );
    if (confirmar != true || _sesionId == null) return;

    try {
      await AsistenciaService.cerrarSesion(_sesionId!);
      _terminarSesion('La sesión de asistencia fue finalizada.');
    } catch (e) {
      _snack(_mensajeLegible(e));
    }
  }

  // ---------------------------------------------------------------------
  // Mensajes
  // ---------------------------------------------------------------------

  String _mensajeLegible(Object e) {
    final texto = (e is PostgrestException ? e.message : e.toString())
        .toLowerCase();
    if (texto.contains('no está abierta')) {
      return 'La sesión de asistencia ya no está abierta.';
    }
    if (texto.contains('permiso')) {
      return 'Tu acceso a este evento venció o fue desactivado.';
    }
    if (texto.contains('no está vigente') || texto.contains('ya no está')) {
      return 'El evento ya no está vigente.';
    }
    if (texto.contains('no hay un registro')) {
      return 'Primero habilitá la entrada o la salida.';
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

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final eventoAsync = ref.watch(eventoPanelProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistencia'),
        actions: [
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
      return _vistaMensaje(_mensaje ?? 'La sesión terminó.', reintentar: true);
    }

    final hhmm = DateFormat('HH:mm');

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

        // ---------------- Registro: entrada / salida ----------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Registro de asistencia',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  _modo == null
                      ? 'Habilitá la entrada o la salida. Se te pedirá tu '
                            'contraseña.'
                      : 'Registro de $_modo habilitado'
                            '${_modoHasta == null ? '' : ' hasta las ${hhmm.format(_modoHasta!)}'}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _botonModo(
                        modo: 'entrada',
                        icono: Icons.login,
                        etiqueta: 'Habilitar entrada',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _botonModo(
                        modo: 'salida',
                        icono: Icons.logout,
                        etiqueta: 'Habilitar salida',
                      ),
                    ),
                  ],
                ),
                if (_modo != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _cerrarRegistro,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: UniNorteColors.error,
                      side: const BorderSide(color: UniNorteColors.error),
                    ),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text('Cerrar registro de $_modo'),
                  ),
                ],
                if (_mensaje != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _mensaje!,
                    style: const TextStyle(
                      color: UniNorteColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ---------------- QR + PIN (solo con un modo activo) ----------------
        if (_modo != null) ...[
          const SizedBox(height: 16),
          _tarjetaQr(),
          const SizedBox(height: 16),
          _tarjetaPin(),
        ],
        const SizedBox(height: 16),

        // ---------------- Quórum ----------------
        _tarjetaResumen(),
        const SizedBox(height: 24),

        OutlinedButton.icon(
          onPressed: _confirmarCierreSesion,
          style: OutlinedButton.styleFrom(
            foregroundColor: UniNorteColors.error,
            side: const BorderSide(color: UniNorteColors.error),
          ),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Finalizar sesión de asistencia'),
        ),
      ],
    );
  }

  Widget _botonModo({
    required String modo,
    required IconData icono,
    required String etiqueta,
  }) {
    final activo = _modo == modo;
    return FilledButton.icon(
      onPressed: activo ? null : () => _habilitar(modo),
      icon: Icon(icono),
      label: Text(activo ? 'Activa' : etiqueta, textAlign: TextAlign.center),
    );
  }

  Widget _tarjetaQr() {
    final nombre = _modo == 'salida' ? 'salida' : 'entrada';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              'Código QR de $nombre',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Se renueva cada minuto',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
            if (_token != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _segundosQr / _ventanaQrSeg,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(
                    UniNorteColors.dorado,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cambia en $_segundosQr s',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tarjetaPin() {
    final vigente = _pinVigente;
    return Card(
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
              'Para alumnos que no pueden escanear el QR. '
              'Aparece solo cuando lo pedís y dura $_duracionPinSeg segundos. '
              'Si otro validador ya lo mostró, vas a ver el mismo PIN.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (vigente) ...[
              Center(
                child: Text(
                  _pin!,
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 14,
                    color: UniNorteColors.azulMarino,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _segundosPin / _duracionPinSeg,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(
                    UniNorteColors.dorado,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Vence en $_segundosPin s',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Mientras el PIN está vigente no se puede pedir otro: el
            // servidor devolvería el mismo (es compartido entre validadores).
            if (!vigente)
              OutlinedButton.icon(
                onPressed: _activandoPin ? null : _activarPin,
                icon: const Icon(Icons.pin_outlined),
                label: const Text('Mostrar PIN'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaResumen() {
    final r = _resumen;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Asistencia registrada',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _filaResumen(
              'Con entrada',
              r == null ? '—' : '${r.conEntrada} de ${r.inscriptos}',
              r?.porcentajeEntrada ?? 0,
              UniNorteColors.dorado,
            ),
            const SizedBox(height: 14),
            _filaResumen(
              'Presentes (entrada y salida)',
              r == null ? '—' : '${r.presentes} de ${r.inscriptos}',
              r?.porcentajePresentes ?? 0,
              UniNorteColors.exito,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaResumen(
    String titulo,
    String valor,
    double fraccion,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraccion,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
          ),
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
            const Icon(
              Icons.info_outline,
              color: UniNorteColors.textoSecundario,
              size: 48,
            ),
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

/// Pide la contraseña del validador y llama a la Edge Function
/// `activar-modo`. Se cierra con `true` si el modo quedó habilitado.
class _DialogoClave extends StatefulWidget {
  final String sesionId;
  final String modo;
  final bool reemplaza;

  const _DialogoClave({
    required this.sesionId,
    required this.modo,
    required this.reemplaza,
  });

  @override
  State<_DialogoClave> createState() => _DialogoClaveState();
}

class _DialogoClaveState extends State<_DialogoClave> {
  final _clave = TextEditingController();
  bool _ver = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  String _mensajeFuncion(Object e) {
    if (e is FunctionException) {
      final d = e.details;
      if (d is Map && d['error'] is String) return d['error'] as String;
      if (e.status == 401) return 'Contraseña incorrecta';
    }
    return 'No se pudo habilitar. Intentá nuevamente.';
  }

  Future<void> _confirmar() async {
    if (_clave.text.isEmpty) {
      setState(() => _error = 'Ingresá tu contraseña');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await AsistenciaService.activarModo(
        sesionId: widget.sesionId,
        modo: widget.modo,
        password: _clave.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = _mensajeFuncion(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.modo == 'salida' ? 'salida' : 'entrada';
    return AlertDialog(
      title: Text('Habilitar $nombre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.reemplaza
                ? 'Se desactivará el registro actual y se habilitará la '
                      '$nombre. Confirmá con tu contraseña.'
                : 'Confirmá con tu contraseña para habilitar la $nombre.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _clave,
            autofocus: true,
            obscureText: !_ver,
            enabled: !_enviando,
            onSubmitted: (_) => _confirmar(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _ver = !_ver),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _enviando ? null : _confirmar,
          child: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Habilitar'),
        ),
      ],
    );
  }
}