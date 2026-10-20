import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/carreras_provider.dart';
import '../home/home_provider.dart';
import 'admin_eventos_provider.dart';
import 'eventos_provider.dart';

/// Carga el evento y sus carreras, y abre el formulario en modo edición.
/// Con [esPasado], corrige un evento cargado como pasado (solo superadmin,
/// fase 8).
class EditarEventoScreen extends ConsumerWidget {
  final String eventoId;
  final bool esPasado;
  const EditarEventoScreen({
    super.key,
    required this.eventoId,
    this.esPasado = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventoAsync = ref.watch(eventoPorIdProvider(eventoId));
    final carrerasAsync = ref.watch(carrerasDeEventoProvider(eventoId));
    final cargando = eventoAsync.isLoading || carrerasAsync.isLoading;
    final titulo = esPasado ? 'Corregir evento pasado' : 'Editar evento';

    if (!cargando && eventoAsync.hasValue && carrerasAsync.hasValue) {
      final evento = eventoAsync.requireValue;
      if (esPasado && !evento.cargaHistorica) {
        return Scaffold(
          appBar: AppBar(title: Text(titulo)),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Solo se pueden corregir los eventos cargados como pasados.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
      return CrearEventoScreen(
        evento: evento,
        carrerasIniciales: carrerasAsync.requireValue,
        esPasado: esPasado,
      );
    }

    if (!cargando && (eventoAsync.hasError || carrerasAsync.hasError)) {
      return Scaffold(
        appBar: AppBar(title: Text(titulo)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No se pudo cargar el evento'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  ref.invalidate(eventoPorIdProvider(eventoId));
                  ref.invalidate(carrerasDeEventoProvider(eventoId));
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Formulario de evento. Con [evento] nulo crea; con valor, edita.
/// Con [esPasado] (solo superadmin, fase 8) carga o corrige un evento que
/// ya ocurrió: fecha anterior a hoy, motivo obligatorio y resumen antes de
/// guardar; el evento queda finalizado.
class CrearEventoScreen extends ConsumerStatefulWidget {
  final Evento? evento;

  /// Ids de las carreras habilitadas al abrir la edición.
  final Set<int> carrerasIniciales;

  final bool esPasado;

  const CrearEventoScreen({
    super.key,
    this.evento,
    this.carrerasIniciales = const {},
    this.esPasado = false,
  });

  @override
  ConsumerState<CrearEventoScreen> createState() => _CrearEventoScreenState();
}

class _CrearEventoScreenState extends ConsumerState<CrearEventoScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _expositorController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _horasController = TextEditingController();
  final _cuposController = TextEditingController();
  final _toleranciaController = TextEditingController(text: '15');
  final _motivoController = TextEditingController();

  String? _categoria;
  String _modalidad = modalidadesEvento.first;
  DateTime? _fecha;
  TimeOfDay? _horaInicio;
  TimeOfDay? _horaFin;
  bool _cupoIlimitado = false;
  final Set<int> _carrerasSel = {};

  bool _intentoEnviar = false;

  bool get _editando => widget.evento != null;
  bool get _pasado => widget.esPasado;

  static DateTime get _hoy {
    final ahora = DateTime.now();
    return DateTime(ahora.year, ahora.month, ahora.day);
  }

  @override
  void initState() {
    super.initState();
    _carrerasSel.addAll(widget.carrerasIniciales);
    final e = widget.evento;
    if (e == null) return;
    _nombreController.text = e.nombre;
    _descripcionController.text = e.descripcion ?? '';
    _expositorController.text = e.expositor ?? '';
    _ubicacionController.text = e.ubicacion;
    _horasController.text = '${e.horasOtorgadas}';
    _categoria = e.categoria;
    _modalidad = e.modalidad;
    _fecha = e.fecha;
    _horaInicio = _parseHora(e.horaInicio);
    _horaFin = _parseHora(e.horaFin);
    _cupoIlimitado = e.cuposIlimitados;
    if (!e.cuposIlimitados) _cuposController.text = '${e.cuposMaximos}';
    _toleranciaController.text = '${e.toleranciaEntradaMin}';
  }

  TimeOfDay _parseHora(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _expositorController.dispose();
    _ubicacionController.dispose();
    _horasController.dispose();
    _cuposController.dispose();
    _toleranciaController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  String _fmtFechaDb(DateTime f) =>
      '${f.year.toString().padLeft(4, '0')}-'
      '${f.month.toString().padLeft(2, '0')}-'
      '${f.day.toString().padLeft(2, '0')}';

  String _fmtHoraDb(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:'
      '${h.minute.toString().padLeft(2, '0')}:00';

  String _fmtHoraUi(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:'
      '${h.minute.toString().padLeft(2, '0')}';

  int _minutos(TimeOfDay h) => h.hour * 60 + h.minute;

  Future<void> _elegirFecha() async {
    if (_pasado) {
      // Evento pasado: sin tope de antigüedad, hasta ayer.
      final ayer = _hoy.subtract(const Duration(days: 1));
      final inicial =
          (_fecha != null && _fecha!.isBefore(_hoy)) ? _fecha! : ayer;
      final elegida = await showDatePicker(
        context: context,
        initialDate: inicial,
        firstDate: DateTime(1950),
        lastDate: ayer,
      );
      if (elegida != null) setState(() => _fecha = elegida);
      return;
    }

    final hoy = DateTime.now();
    final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
    // Al editar, la fecha actual puede ser anterior a hoy: el picker
    // exige que initialDate >= firstDate.
    final primera = (_fecha != null && _fecha!.isBefore(hoySinHora))
        ? _fecha!
        : hoySinHora;
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha ?? hoySinHora,
      firstDate: primera,
      lastDate: DateTime(hoy.year + 2),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _elegirHora({required bool esInicio}) async {
    final actual = esInicio ? _horaInicio : _horaFin;
    final elegida = await showTimePicker(
      context: context,
      initialTime: actual ?? const TimeOfDay(hour: 18, minute: 0),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (elegida == null) return;
    setState(() {
      if (esInicio) {
        _horaInicio = elegida;
      } else {
        _horaFin = elegida;
      }
    });
  }

  String? get _errorHoraFin {
    if (_horaFin == null) return _intentoEnviar ? 'Obligatoria' : null;
    if (_horaInicio != null && _minutos(_horaFin!) <= _minutos(_horaInicio!)) {
      return 'Debe ser posterior al inicio';
    }
    return null;
  }

  String? get _errorFecha {
    if (_fecha == null) return _intentoEnviar ? 'Elegí la fecha' : null;
    if (_pasado && !_fecha!.isBefore(_hoy)) {
      return 'La fecha debe ser anterior a hoy';
    }
    return null;
  }

  bool get _selectoresValidos =>
      _categoria != null &&
      _errorFecha == null &&
      _fecha != null &&
      _horaInicio != null &&
      _horaFin != null &&
      _errorHoraFin == null &&
      _carrerasSel.isNotEmpty;

  String? _vacioSiNulo(String texto) {
    final t = texto.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    setState(() => _intentoEnviar = true);

    final formOk = _formKey.currentState!.validate();
    if (!formOk || !_selectoresValidos) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final notifier = ref.read(crearEventoNotifierProvider.notifier);

    final cupos = _cupoIlimitado ? null : int.parse(_cuposController.text.trim());
    final tolerancia = int.parse(_toleranciaController.text.trim());
    final carreras = Set<int>.of(_carrerasSel);

    if (_pasado) {
      await _guardarPasado(
        cupos: cupos,
        tolerancia: tolerancia,
        carreras: carreras,
      );
      return;
    }

    final exito = _editando
        ? await notifier.editar(
            eventoId: widget.evento!.id,
            nombre: _nombreController.text.trim(),
            descripcion: _vacioSiNulo(_descripcionController.text),
            categoria: _categoria!,
            expositor: _vacioSiNulo(_expositorController.text),
            fecha: _fmtFechaDb(_fecha!),
            horaInicio: _fmtHoraDb(_horaInicio!),
            horaFin: _fmtHoraDb(_horaFin!),
            ubicacion: _ubicacionController.text.trim(),
            modalidad: _modalidad,
            horasOtorgadas: int.parse(_horasController.text.trim()),
            cuposMaximos: cupos,
            toleranciaEntradaMin: tolerancia,
            carreraIds: carreras,
          )
        : await notifier.crear(
            nombre: _nombreController.text.trim(),
            descripcion: _vacioSiNulo(_descripcionController.text),
            categoria: _categoria!,
            expositor: _vacioSiNulo(_expositorController.text),
            fecha: _fmtFechaDb(_fecha!),
            horaInicio: _fmtHoraDb(_horaInicio!),
            horaFin: _fmtHoraDb(_horaFin!),
            ubicacion: _ubicacionController.text.trim(),
            modalidad: _modalidad,
            horasOtorgadas: int.parse(_horasController.text.trim()),
            cuposMaximos: cupos,
            toleranciaEntradaMin: tolerancia,
            carreraIds: carreras,
          );

    if (!exito) return; // el ref.listen de build muestra el error

    ref.invalidate(metricasAdminProvider);
    ref.invalidate(catalogoEventosProvider);
    ref.invalidate(adminEventosProvider);
    if (_editando) {
      ref.invalidate(eventoPorIdProvider(widget.evento!.id));
      ref.invalidate(detalleEventoProvider(widget.evento!.id));
      ref.invalidate(carrerasDeEventoProvider(widget.evento!.id));
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(_editando
            ? 'Evento actualizado correctamente'
            : 'Evento creado correctamente'),
        backgroundColor: UniNorteColors.exito,
        behavior: SnackBarBehavior.floating,
      ),
    );
    router.pop();
  }

  /// Evento pasado (fase 8): resumen de confirmación y guardado con motivo.
  Future<void> _guardarPasado({
    required int? cupos,
    required int tolerancia,
    required Set<int> carreras,
  }) async {
    final confirmado = await _confirmarResumen(cupos, carreras);
    if (confirmado != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final notifier = ref.read(crearEventoNotifierProvider.notifier);
    final motivo = _motivoController.text.trim();

    final String mensaje;
    if (_editando) {
      final ajustadas = await notifier.editarPasado(
        eventoId: widget.evento!.id,
        nombre: _nombreController.text.trim(),
        descripcion: _vacioSiNulo(_descripcionController.text),
        categoria: _categoria!,
        expositor: _vacioSiNulo(_expositorController.text),
        fecha: _fmtFechaDb(_fecha!),
        horaInicio: _fmtHoraDb(_horaInicio!),
        horaFin: _fmtHoraDb(_horaFin!),
        ubicacion: _ubicacionController.text.trim(),
        modalidad: _modalidad,
        horasOtorgadas: int.parse(_horasController.text.trim()),
        cuposMaximos: cupos,
        toleranciaEntradaMin: tolerancia,
        carreraIds: carreras,
        motivo: motivo,
      );
      if (ajustadas == null) return; // el ref.listen de build muestra el error
      mensaje = ajustadas > 0
          ? 'Evento corregido. Se ajustó la entrada y la salida de '
              '$ajustadas ${ajustadas == 1 ? 'asistente' : 'asistentes'} '
              'al nuevo horario'
          : 'Evento corregido correctamente';
    } else {
      final id = await notifier.crearPasado(
        nombre: _nombreController.text.trim(),
        descripcion: _vacioSiNulo(_descripcionController.text),
        categoria: _categoria!,
        expositor: _vacioSiNulo(_expositorController.text),
        fecha: _fmtFechaDb(_fecha!),
        horaInicio: _fmtHoraDb(_horaInicio!),
        horaFin: _fmtHoraDb(_horaFin!),
        ubicacion: _ubicacionController.text.trim(),
        modalidad: _modalidad,
        horasOtorgadas: int.parse(_horasController.text.trim()),
        cuposMaximos: cupos,
        toleranciaEntradaMin: tolerancia,
        carreraIds: carreras,
        motivo: motivo,
      );
      if (id == null) return;
      mensaje = 'Evento pasado cargado como finalizado';
    }

    if (!mounted) return;
    ref.invalidate(adminEventosProvider);
    if (_editando) {
      ref.invalidate(eventoPorIdProvider(widget.evento!.id));
      ref.invalidate(carrerasDeEventoProvider(widget.evento!.id));
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: UniNorteColors.exito,
        behavior: SnackBarBehavior.floating,
      ),
    );
    router.pop();
  }

  Future<bool?> _confirmarResumen(int? cupos, Set<int> carreras) {
    final activas = ref.read(carrerasProvider).valueOrNull ?? const <Carrera>[];
    final nombres = activas
        .where((c) => carreras.contains(c.id))
        .map((c) => c.nombre)
        .toList();
    final otras = carreras.length - nombres.length;
    final textoCarreras = [
      if (nombres.length == activas.length && activas.isNotEmpty)
        'Todas las carreras'
      else
        ...nombres,
      if (otras > 0)
        '$otras ${otras == 1 ? 'carrera desactivada' : 'carreras desactivadas'}',
    ].join(', ');
    final fecha =
        DateFormat("EEEE d 'de' MMMM 'de' yyyy", 'es').format(_fecha!);

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            _editando ? 'Confirmar corrección' : 'Confirmar evento pasado'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editando
                    ? 'Revisá los datos. El evento sigue finalizado y la '
                        'corrección queda registrada en la auditoría.'
                    : 'Revisá los datos. El evento se creará como finalizado '
                        'y la carga queda registrada en la auditoría.',
              ),
              const SizedBox(height: 12),
              _FilaResumen('Evento', _nombreController.text.trim()),
              _FilaResumen('Fecha', fecha),
              _FilaResumen(
                'Horario',
                '${_fmtHoraUi(_horaInicio!)} a ${_fmtHoraUi(_horaFin!)}',
              ),
              _FilaResumen('Ubicación', _ubicacionController.text.trim()),
              _FilaResumen('Horas otorgadas', _horasController.text.trim()),
              _FilaResumen('Cupo', cupos == null ? 'Sin límite' : '$cupos'),
              _FilaResumen('Carreras', textoCarreras),
              _FilaResumen('Motivo', _motivoController.text.trim()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  String _mensajeError(Object error) {
    // Los mensajes de las RPC ya vienen listos para el usuario.
    if (error is PostgrestException && error.code == 'P0001') {
      return error.message;
    }
    final texto = error.toString().toLowerCase();
    if (texto.contains('42501') || texto.contains('row-level security')) {
      return 'No tenés permiso para esta acción.';
    }
    return _editando
        ? 'No se pudo guardar el evento. Intentá nuevamente.'
        : 'No se pudo crear el evento. Intentá nuevamente.';
  }

  /// Selección de carreras habilitadas, con opción "Todas las carreras".
  Widget _seccionCarreras() {
    final carrerasAsync = ref.watch(carrerasProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Etiqueta('Carreras habilitadas'),
        carrerasAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          error: (_, _) => Row(
            children: [
              const Expanded(
                child: _TextoError('No se pudo cargar la lista de carreras'),
              ),
              TextButton.icon(
                onPressed: () => ref.invalidate(carrerasProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
          data: (carreras) {
            final ids = carreras.map((c) => c.id).toSet();
            final marcadas = ids.where(_carrerasSel.contains).length;
            final todas = ids.isNotEmpty && marcadas == ids.length;
            final bool? valorTodas =
                todas ? true : (marcadas == 0 ? false : null);
            // Carreras que el evento ya tenía y hoy están desactivadas: no
            // figuran en la lista, pero se conservan al guardar.
            final otras = _carrerasSel.difference(ids).length;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  CheckboxListTile(
                    dense: true,
                    tristate: true,
                    value: valorTodas,
                    activeColor: UniNorteColors.azulMarino,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Todas las carreras',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('$marcadas de ${ids.length} seleccionadas'),
                    onChanged: (_) => setState(() {
                      if (todas) {
                        _carrerasSel.removeAll(ids);
                      } else {
                        _carrerasSel.addAll(ids);
                      }
                    }),
                  ),
                  const Divider(height: 1),
                  for (final c in carreras)
                    CheckboxListTile(
                      dense: true,
                      value: _carrerasSel.contains(c.id),
                      activeColor: UniNorteColors.azulMarino,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(c.nombre),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _carrerasSel.add(c.id);
                        } else {
                          _carrerasSel.remove(c.id);
                        }
                      }),
                    ),
                  if (_pasado && otras > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Text(
                        'El evento también está habilitado para $otras '
                        '${otras == 1 ? 'carrera desactivada, que se conserva' : 'carreras desactivadas, que se conservan'}.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (_intentoEnviar && _carrerasSel.isEmpty)
          const _TextoError('Seleccioná al menos una carrera'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final guardando = ref.watch(crearEventoNotifierProvider).isLoading;

    ref.listen<AsyncValue<void>>(crearEventoNotifierProvider, (previo, actual) {
      actual.whenOrNull(
        error: (err, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_mensajeError(err)),
              backgroundColor: UniNorteColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    });

    final formatoFecha = DateFormat('EEEE dd MMMM yyyy', 'es');

    final titulo = _pasado
        ? (_editando ? 'Corregir evento pasado' : 'Cargar evento pasado')
        : (_editando ? 'Editar evento' : 'Nuevo evento');

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_pasado) ...[
                _AvisoPasado(editando: _editando),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nombreController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre del evento',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Ingresá el nombre del evento'
                    : null,
              ),
              const SizedBox(height: 16),

              const _Etiqueta('Categoría'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: categoriasEvento
                    .map(
                      (cat) => ChoiceChip(
                        label: Text(cat),
                        selected: _categoria == cat,
                        selectedColor: UniNorteColors.dorado,
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.grey.shade300),
                        onSelected: (_) => setState(() => _categoria = cat),
                      ),
                    )
                    .toList(),
              ),
              if (_intentoEnviar && _categoria == null)
                const _TextoError('Elegí una categoría'),
              const SizedBox(height: 16),

              TextFormField(
                controller: _expositorController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Expositor (opcional)',
                  prefixIcon: Icon(Icons.record_voice_over_outlined),
                ),
              ),
              const SizedBox(height: 16),

              _CampoSelector(
                icono: Icons.calendar_today_outlined,
                etiqueta: 'Fecha',
                valor: _fecha == null ? null : formatoFecha.format(_fecha!),
                error: _errorFecha,
                onTap: _elegirFecha,
              ),
              const SizedBox(height: 16),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _CampoSelector(
                      icono: Icons.schedule_outlined,
                      etiqueta: 'Hora de inicio',
                      valor: _horaInicio == null
                          ? null
                          : _fmtHoraUi(_horaInicio!),
                      error: _intentoEnviar && _horaInicio == null
                          ? 'Obligatoria'
                          : null,
                      onTap: () => _elegirHora(esInicio: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CampoSelector(
                      icono: Icons.schedule_outlined,
                      etiqueta: 'Hora de fin',
                      valor: _horaFin == null ? null : _fmtHoraUi(_horaFin!),
                      error: _errorHoraFin,
                      onTap: () => _elegirHora(esInicio: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _toleranciaController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Tolerancia de entrada (minutos)',
                  helperText: _pasado
                      ? 'Dato del evento; en un evento pasado no se usa para '
                          'registrar asistencia'
                      : 'Tiempo después del inicio en que aún se puede marcar la entrada',
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.hourglass_bottom_outlined),
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n < 0 || n > 120) return 'Entre 0 y 120';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _ubicacionController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Ubicación',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ingresá la ubicación'
                    : null,
              ),
              const SizedBox(height: 16),

              const _Etiqueta('Modalidad'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: modalidadesEvento
                    .map(
                      (m) => ChoiceChip(
                        label: Text(m),
                        selected: _modalidad == m,
                        selectedColor: UniNorteColors.dorado,
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.grey.shade300),
                        onSelected: (_) => setState(() => _modalidad = m),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),

              _seccionCarreras(),
              const SizedBox(height: 16),

              TextFormField(
                controller: _horasController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Horas otorgadas',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n < 1 || n > 120) return 'Entre 1 y 120';
                  return null;
                },
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cupo ilimitado'),
                value: _cupoIlimitado,
                activeThumbColor: UniNorteColors.azulMarino,
                onChanged: (v) => setState(() => _cupoIlimitado = v),
              ),
              if (!_cupoIlimitado)
                TextFormField(
                  controller: _cuposController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cupos',
                    prefixIcon: Icon(Icons.event_seat_outlined),
                  ),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n < 1 || n > 5000) {
                      return 'Entre 1 y 5000';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descripcionController,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),

              if (_pasado) ...[
                TextFormField(
                  controller: _motivoController,
                  maxLines: 3,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _editando
                        ? 'Motivo de la corrección'
                        : 'Motivo de la carga',
                    helperText: 'Queda registrado en la auditoría',
                    alignLabelWithHint: true,
                    prefixIcon: const Icon(Icons.edit_note_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().length < 10)
                      ? 'Indicá el motivo (mínimo 10 caracteres)'
                      : null,
                ),
                const SizedBox(height: 16),
              ],

              ElevatedButton(
                onPressed: guardando ? null : _guardar,
                child: guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: UniNorteColors.azulMarino,
                        ),
                      )
                    : Text(_pasado
                        ? (_editando
                            ? 'Guardar corrección'
                            : 'Cargar evento pasado')
                        : (_editando ? 'Guardar cambios' : 'Crear evento')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Explicación al cargar o corregir un evento pasado (fase 8).
class _AvisoPasado extends StatelessWidget {
  final bool editando;
  const _AvisoPasado({required this.editando});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UniNorteColors.azulMarino.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_edu_outlined,
              color: UniNorteColors.azulMarino, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              editando
                  ? 'Corregís un evento cargado como pasado. Si cambiás la '
                      'fecha o el horario, la entrada y la salida de sus '
                      'asistentes pasan al nuevo inicio y al nuevo fin.'
                  : 'Cargás un evento que ya ocurrió y no estaba en el '
                      'sistema. Queda finalizado; la fecha debe ser anterior '
                      'a hoy.',
              style: const TextStyle(color: UniNorteColors.textoPrimario),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila del resumen de confirmación de un evento pasado.
class _FilaResumen extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _FilaResumen(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$etiqueta: ',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: UniNorteColors.textoPrimario,
              ),
            ),
            TextSpan(
              text: valor.isEmpty ? '—' : valor,
              style: const TextStyle(color: UniNorteColors.textoSecundario),
            ),
          ],
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  const _Etiqueta(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(texto, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _TextoError extends StatelessWidget {
  final String texto;
  const _TextoError(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        texto,
        style: const TextStyle(color: UniNorteColors.error, fontSize: 12),
      ),
    );
  }
}

/// Campo de solo lectura que abre un picker al tocarlo.
class _CampoSelector extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String? valor;
  final String? error;
  final VoidCallback onTap;

  const _CampoSelector({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    required this.onTap,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: Icon(icono),
          errorText: error,
        ),
        child: Text(
          valor ?? 'Seleccionar',
          style: TextStyle(
            color: valor == null
                ? UniNorteColors.textoSecundario
                : UniNorteColors.textoPrimario,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}