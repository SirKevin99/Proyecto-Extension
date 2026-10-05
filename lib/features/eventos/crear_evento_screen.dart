import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../home/home_provider.dart';
import 'eventos_provider.dart';

class CrearEventoScreen extends ConsumerStatefulWidget {
  const CrearEventoScreen({super.key});

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

  String? _categoria;
  String _modalidad = modalidadesEvento.first;
  DateTime? _fecha;
  TimeOfDay? _horaInicio;
  TimeOfDay? _horaFin;

  /// Se activa al primer intento de guardar, para mostrar los errores
  /// de los campos que no son TextFormField (categoría, fecha, horas).
  bool _intentoEnviar = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _expositorController.dispose();
    _ubicacionController.dispose();
    _horasController.dispose();
    _cuposController.dispose();
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
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha ?? hoy,
      firstDate: DateTime(hoy.year, hoy.month, hoy.day),
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
    if (_horaInicio != null &&
        _horaFin != null &&
        _minutos(_horaFin!) <= _minutos(_horaInicio!)) {
      return 'La hora de fin debe ser posterior al inicio';
    }
    return null;
  }

  bool get _selectoresValidos =>
      _categoria != null &&
      _fecha != null &&
      _horaInicio != null &&
      _errorHoraFin == null;

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

    final exito = await ref.read(crearEventoNotifierProvider.notifier).crear(
          nombre: _nombreController.text.trim(),
          descripcion: _vacioSiNulo(_descripcionController.text),
          categoria: _categoria!,
          expositor: _vacioSiNulo(_expositorController.text),
          fecha: _fmtFechaDb(_fecha!),
          horaInicio: _fmtHoraDb(_horaInicio!),
          horaFin: _horaFin == null ? null : _fmtHoraDb(_horaFin!),
          ubicacion: _ubicacionController.text.trim(),
          modalidad: _modalidad,
          horasOtorgadas: int.parse(_horasController.text.trim()),
          cuposMaximos: int.parse(_cuposController.text.trim()),
        );

    if (!exito) return; // el ref.listen de build muestra el error

    ref.invalidate(metricasAdminProvider);
    ref.invalidate(catalogoEventosProvider);

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Evento creado correctamente'),
        backgroundColor: UniNorteColors.exito,
        behavior: SnackBarBehavior.floating,
      ),
    );
    router.pop();
  }

  String _mensajeError(Object error) {
    final texto = error.toString().toLowerCase();
    if (texto.contains('42501') || texto.contains('row-level security')) {
      return 'No tenés permiso para crear eventos.';
    }
    return 'No se pudo crear el evento. Intentá nuevamente.';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo evento')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
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
                valor: _fecha == null
                    ? null
                    : formatoFecha.format(_fecha!),
                error: _intentoEnviar && _fecha == null
                    ? 'Elegí la fecha'
                    : null,
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
                      etiqueta: 'Hora de fin (opc.)',
                      valor: _horaFin == null ? null : _fmtHoraUi(_horaFin!),
                      error: _errorHoraFin,
                      onTap: () => _elegirHora(esInicio: false),
                    ),
                  ),
                ],
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

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _horasController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Horas otorgadas',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n < 1 || n > 120) {
                          return 'Entre 1 y 120';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
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
                  ),
                ],
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
                    : const Text('Crear evento'),
              ),
            ],
          ),
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