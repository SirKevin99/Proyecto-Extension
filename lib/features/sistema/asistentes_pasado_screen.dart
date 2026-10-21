import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../shared/carreras_provider.dart';
import '../eventos/admin_eventos_provider.dart';
import 'asistentes_pasado_provider.dart';
import 'carga_alumnos_csv.dart';
import 'carga_alumnos_provider.dart';

/// Carga de asistentes de un evento cargado como pasado (fase 8, paso 8.3,
/// solo superadmin). Pestañas: elegir de la lista o archivo CSV.
class AsistentesPasadoScreen extends ConsumerWidget {
  final String eventoId;
  const AsistentesPasadoScreen({super.key, required this.eventoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumenAsync = ref.watch(resumenEventoPasadoProvider(eventoId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cargar asistentes'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: UniNorteColors.dorado,
            tabs: [
              Tab(icon: Icon(Icons.checklist_outlined), text: 'Elegir de la lista'),
              Tab(icon: Icon(Icons.upload_file_outlined), text: 'Archivo CSV'),
            ],
          ),
        ),
        body: SafeArea(
          child: resumenAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _MensajeCentrado(
              texto: e is AsistentesException
                  ? e.mensaje
                  : 'No se pudo cargar el evento',
              onReintentar: () =>
                  ref.invalidate(resumenEventoPasadoProvider(eventoId)),
            ),
            data: (r) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Encabezado(resumen: r),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _TabLista(resumen: r),
                          _TabCsv(resumen: r),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Encabezado con los datos del evento
// ---------------------------------------------------------------

class _Encabezado extends StatelessWidget {
  final ResumenEventoPasado resumen;
  const _Encabezado({required this.resumen});

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final estilo = Theme.of(context).textTheme.bodyMedium;
    final fecha = DateFormat("EEEE d 'de' MMMM 'de' yyyy", 'es').format(r.fecha);
    final cupo = r.sinLimite
        ? 'Sin límite de cupo'
        : 'Cupo: ${r.cuposDisponibles} de ${r.cuposMaximos} lugares disponibles';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.nombre,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('$fecha · ${r.horaInicio} a ${r.horaFin} · '
                  '${r.horasOtorgadas} h', style: estilo),
              Text('Carreras: ${r.carreras.join(', ')}', style: estilo),
              Text('$cupo · Asistentes cargados: ${r.asistentesCompletos}',
                  style: estilo),
              const SizedBox(height: 6),
              Text(
                'Cada asistente queda con entrada a las ${r.horaInicio} y '
                'salida a las ${r.horaFin}, suma ${r.horasOtorgadas} h y '
                'recibe el certificado.',
                style: const TextStyle(
                    color: UniNorteColors.textoPrimario, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Comunes: motivo, resultados, mensajes
// ---------------------------------------------------------------

/// Pide el motivo de la carga (obligatorio, 10+ caracteres).
Future<String?> _pedirMotivo(BuildContext context, String descripcion) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogoMotivo(descripcion: descripcion),
  );
}

class _DialogoMotivo extends StatefulWidget {
  final String descripcion;
  const _DialogoMotivo({required this.descripcion});

  @override
  State<_DialogoMotivo> createState() => _DialogoMotivoState();
}

class _DialogoMotivoState extends State<_DialogoMotivo> {
  final _formKey = GlobalKey<FormState>();
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirmar carga de asistentes'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.descripcion),
              const SizedBox(height: 16),
              TextFormField(
                controller: _motivo,
                autofocus: true,
                maxLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motivo de la carga',
                  helperText: 'Queda registrado en la auditoría',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().length < 10)
                    ? 'Indicá el motivo (mínimo 10 caracteres)'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _motivo.text.trim());
            }
          },
          child: const Text('Cargar'),
        ),
      ],
    );
  }
}

/// Aviso de cupo insuficiente (antes de enviar nada).
Future<void> _avisarCupo(
  BuildContext context,
  ResumenEventoPasado r,
  int aCargar,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supera el cupo'),
      content: Text(
        'El evento tiene ${r.cuposDisponibles} '
        '${r.cuposDisponibles == 1 ? 'lugar disponible' : 'lugares disponibles'} '
        'y se quieren cargar $aCargar asistentes. Ampliá el cupo con '
        '"Corregir evento pasado" o cargá menos alumnos.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}

String _plural(int n, String uno, String varios) => n == 1 ? uno : varios;

class _MensajeCentrado extends StatelessWidget {
  final String texto;
  final VoidCallback? onReintentar;
  const _MensajeCentrado({required this.texto, this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(texto,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            if (onReintentar != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onReintentar,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Recuadro extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String texto;

  const _Recuadro({
    required this.icono,
    required this.color,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color color;
  const _Etiqueta({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TarjetaResumen extends StatelessWidget {
  final int valor;
  final String etiqueta;
  final Color color;

  const _TarjetaResumen({
    required this.valor,
    required this.etiqueta,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Text(
                '$valor',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(etiqueta,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Pestaña 1: elegir de la lista
// ---------------------------------------------------------------

class _TabLista extends ConsumerStatefulWidget {
  final ResumenEventoPasado resumen;
  const _TabLista({required this.resumen});

  @override
  ConsumerState<_TabLista> createState() => _TabListaState();
}

class _TabListaState extends ConsumerState<_TabLista>
    with AutomaticKeepAliveClientMixin {
  final _busqueda = TextEditingController();
  Timer? _espera;

  bool _cargando = true;
  String? _error;
  List<AlumnoElegible> _alumnos = const [];
  final Map<String, AlumnoElegible> _seleccion = {};
  bool _procesando = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  void _alEscribir(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), _buscar);
  }

  Future<void> _buscar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await AsistentesPasadoService.buscar(
          widget.resumen.eventoId, _busqueda.text);
      if (!mounted) return;
      setState(() {
        _alumnos = r;
        _cargando = false;
      });
    } on AsistentesException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    }
  }

  Future<void> _cargar() async {
    final r = widget.resumen;
    final elegidos = _seleccion.values.toList();
    if (elegidos.length > maxAsistentesPorCarga) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Se pueden cargar hasta $maxAsistentesPorCarga '
            'asistentes por vez'),
      ));
      return;
    }
    // Los que ya están inscriptos se completan y no ocupan un lugar nuevo.
    final nuevos = elegidos.where((a) => !a.inscripto).length;
    if (r.cuposDisponibles != null && nuevos > r.cuposDisponibles!) {
      await _avisarCupo(context, r, nuevos);
      return;
    }

    final motivo = await _pedirMotivo(
      context,
      'Se ${_plural(elegidos.length, 'cargará 1 alumno', 'cargarán ${elegidos.length} alumnos')} '
      'como ${_plural(elegidos.length, 'asistente', 'asistentes')} de '
      '"${r.nombre}", con entrada a las ${r.horaInicio} y salida a las '
      '${r.horaFin}.',
    );
    if (motivo == null || !mounted) return;

    setState(() => _procesando = true);
    try {
      final resultados = await AsistentesPasadoService.cargar(
        r.eventoId,
        elegidos.map((a) => a.id).toList(),
        motivo,
      );
      if (!mounted) return;
      final nombres = {for (final a in elegidos) a.id: a.nombre};
      setState(_seleccion.clear);
      ref.invalidate(resumenEventoPasadoProvider(r.eventoId));
      ref.invalidate(adminEventosProvider);
      await _mostrarResultados(resultados, nombres);
      if (mounted) _buscar();
    } on AsistentesException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.mensaje),
        backgroundColor: UniNorteColors.error,
      ));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _mostrarResultados(
    List<ResultadoAsistente> resultados,
    Map<String, String> nombres,
  ) {
    final cargados = resultados.where((x) => x.cargado).length;
    final yaEstaban = resultados.where((x) => x.resultado == 'ya_estaba').length;
    final rechazados =
        resultados.where((x) => x.resultado == 'rechazado').toList();

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carga terminada'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cargados: $cargados · Ya estaban: $yaEstaban · '
                  'Rechazados: ${rechazados.length}'),
              for (final x in rechazados) ...[
                const SizedBox(height: 8),
                Text(
                  '${nombres[x.usuarioId] ?? x.usuarioId}: ${x.detalle ?? ''}',
                  style: const TextStyle(color: UniNorteColors.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final estilo = Theme.of(context).textTheme.bodyMedium;
    final visiblesIds = _alumnos.map((a) => a.id).toSet();
    final todosVisibles = _alumnos.isNotEmpty &&
        visiblesIds.every(_seleccion.containsKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _busqueda,
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre o C.I.',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _alEscribir,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _cargando
                    ? 'Buscando…'
                    : '${_alumnos.length} '
                        '${_plural(_alumnos.length, 'alumno', 'alumnos')}'
                        '${_alumnos.length == limiteBusquedaAlumnos ? ' (se muestran los primeros $limiteBusquedaAlumnos: refiná la búsqueda)' : ''}',
                style: estilo,
              ),
              TextButton(
                onPressed: _alumnos.isEmpty
                    ? null
                    : () => setState(() {
                          if (todosVisibles) {
                            _seleccion.removeWhere(
                                (id, _) => visiblesIds.contains(id));
                          } else {
                            for (final a in _alumnos) {
                              _seleccion[a.id] = a;
                            }
                          }
                        }),
                child: Text(todosVisibles
                    ? 'Quitar selección de los visibles'
                    : 'Seleccionar todos los visibles'),
              ),
            ],
          ),
        ),
        Expanded(child: _lista(estilo)),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: ElevatedButton.icon(
              onPressed: (_seleccion.isEmpty || _procesando) ? null : _cargar,
              icon: _procesando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.how_to_reg_outlined),
              label: Text('Cargar asistentes (${_seleccion.length})'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _lista(TextStyle? estilo) {
    if (_cargando && _alumnos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MensajeCentrado(texto: _error!, onReintentar: _buscar);
    }
    if (_alumnos.isEmpty) {
      return const _MensajeCentrado(
        texto: 'No hay alumnos para cargar con esta búsqueda. Solo aparecen '
            'alumnos activos de las carreras habilitadas que todavía no '
            'tienen la asistencia registrada.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _alumnos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final a = _alumnos[i];
        return Card(
          child: CheckboxListTile(
            value: _seleccion.containsKey(a.id),
            activeColor: UniNorteColors.azulMarino,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() {
              if (v == true) {
                _seleccion[a.id] = a;
              } else {
                _seleccion.remove(a.id);
              }
            }),
            title: Text(a.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              'C.I. ${a.ci} · ${a.carrera}'
              '${a.inscripto ? '\nInscripto sin asistencia: se completa' : ''}',
              style: estilo,
            ),
            isThreeLine: a.inscripto,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------
// Pestaña 2: archivo CSV
// ---------------------------------------------------------------

enum _Etapa { inicio, previa, enviando, terminado }

enum _Filtro { todas, seAgregan, noRegistrados, errores }

class _TabCsv extends ConsumerStatefulWidget {
  final ResumenEventoPasado resumen;
  const _TabCsv({required this.resumen});

  @override
  ConsumerState<_TabCsv> createState() => _TabCsvState();
}

class _TabCsvState extends ConsumerState<_TabCsv>
    with AutomaticKeepAliveClientMixin {
  _Etapa _etapa = _Etapa.inicio;

  // Lectura
  bool _leyendo = false;
  String? _errorArchivo;
  String _nombreArchivo = '';
  List<FilaAsistente> _filas = const [];
  _Filtro _filtro = _Filtro.todas;
  bool _registrarNuevos = false;

  // Envío
  String _motivo = '';
  bool _enAlta = false; // true: creando/reactivando cuentas
  String? _cargaId;
  List<List<FilaAsistente>> _tandas = const [];
  int _tandaActual = 0;
  final Map<int, ResultadoFila> _resultadosAlta = {};
  String? _errorEnvio;

  @override
  bool get wantKeepAlive => true;

  Iterable<FilaAsistente> _con(EstadoFilaAsistente e) =>
      _filas.where((f) => f.estado == e);

  int get _reactivar =>
      _con(EstadoFilaAsistente.desactivado).where((f) => f.reactivar).length;

  int get _nuevosARegistrar =>
      _registrarNuevos ? _con(EstadoFilaAsistente.noRegistrado).length : 0;

  int get _aCargar =>
      _con(EstadoFilaAsistente.seAgrega).length + _reactivar + _nuevosARegistrar;

  // ---------------------------------------------------------------
  // Archivos
  // ---------------------------------------------------------------

  void _aviso(String texto, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: esError ? UniNorteColors.error : null,
    ));
  }

  Future<void> _guardarArchivo(String nombre, Uint8List bytes) async {
    try {
      final destino = await FilePicker.saveFile(
        fileName: nombre,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (!mounted) return;
      if (kIsWeb) {
        _aviso('Descarga iniciada: $nombre');
      } else if (destino != null) {
        _aviso('Archivo guardado: $nombre');
      }
    } catch (_) {
      if (!mounted) return;
      _aviso('No se pudo guardar el archivo', esError: true);
    }
  }

  Future<void> _descargarCarreras() async {
    final List<Carrera> oficiales;
    try {
      oficiales = await ref.read(carrerasProvider.future);
    } catch (_) {
      if (!mounted) return;
      _aviso('No se pudo cargar la lista de carreras', esError: true);
      return;
    }
    // Para los alumnos nuevos: carreras del evento que siguen activas.
    final activas = oficiales.map((c) => c.nombre).toSet();
    await _guardarArchivo(
      'carreras_del_evento.csv',
      generarCarrerasCsv(
          widget.resumen.carreras.where(activas.contains).toList()),
    );
  }

  Future<void> _elegirArchivo() async {
    FilePickerResult? seleccion;
    try {
      seleccion = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorArchivo = 'No se pudo abrir el selector de archivos');
      return;
    }
    if (seleccion == null || seleccion.files.isEmpty || !mounted) return;
    final archivo = seleccion.files.first;
    final nombre = archivo.name;
    if (!nombre.toLowerCase().endsWith('.csv')) {
      setState(() => _errorArchivo =
          'Elegí un archivo .csv (el elegido es "$nombre").');
      return;
    }

    setState(() {
      _leyendo = true;
      _errorArchivo = null;
    });
    try {
      final bytes = archivo.bytes;
      if (bytes == null) {
        throw const ArchivoInvalidoException(
            'No se pudo leer el contenido del archivo');
      }
      final filasCsv = leerFilasCsv(bytes);
      final oficiales = await ref.read(carrerasProvider.future);
      final existentes = await CargaAlumnosService.verificar(filasCsv);
      final previa = clasificarFilasAsistentes(
        filas: filasCsv,
        carrerasOficiales: oficiales.map((c) => c.nombre).toSet(),
        carrerasEvento: widget.resumen.carreras.toSet(),
        existentes: existentes,
      );
      if (!mounted) return;
      setState(() {
        _nombreArchivo = nombre;
        _filas = previa;
        _filtro = _Filtro.todas;
        _registrarNuevos = false;
        _etapa = _Etapa.previa;
      });
    } on ArchivoInvalidoException catch (e) {
      _mostrarErrorArchivo(e.mensaje);
    } on CargaAlumnosException catch (e) {
      _mostrarErrorArchivo(e.mensaje);
    } catch (_) {
      _mostrarErrorArchivo('No se pudo leer el archivo');
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  void _mostrarErrorArchivo(String mensaje) {
    if (!mounted) return;
    setState(() => _errorArchivo = mensaje);
  }

  // ---------------------------------------------------------------
  // Envío
  // ---------------------------------------------------------------

  Future<void> _confirmar() async {
    final r = widget.resumen;
    final aCargar = _aCargar;
    if (aCargar == 0) {
      _aviso('No hay alumnos para cargar con estas opciones');
      return;
    }
    // Control previo solo si se van a crear o reactivar cuentas, para no
    // crearlas en vano. Es aproximado (cuenta también a quienes ya estaban
    // cargados); sin cuentas nuevas, el cupo lo controla el servidor.
    final necesitaAlta = _nuevosARegistrar > 0 || _reactivar > 0;
    if (necesitaAlta &&
        r.cuposDisponibles != null &&
        aCargar > r.cuposDisponibles!) {
      await _avisarCupo(context, r, aCargar);
      return;
    }

    final registrados = _con(EstadoFilaAsistente.seAgrega).length;
    final partes = <String>[
      '$registrados ${_plural(registrados, 'alumno registrado', 'alumnos registrados')}',
      if (_reactivar > 0)
        '$_reactivar con la cuenta reactivada',
      if (_nuevosARegistrar > 0)
        '$_nuevosARegistrar ${_plural(_nuevosARegistrar, 'alumno nuevo', 'alumnos nuevos')} '
            '(clave inicial: C.I. + "$sufijoClaveInicial")',
    ];
    final motivo = await _pedirMotivo(
      context,
      'Se cargarán como asistentes de "${r.nombre}": ${partes.join(', ')}. '
      'Entrada a las ${r.horaInicio} y salida a las ${r.horaFin}.',
    );
    if (motivo == null || !mounted) return;

    setState(() {
      _motivo = motivo;
      _errorEnvio = null;
      _resultadosAlta.clear();
      _cargaId = null;
      _tandaActual = 0;
      _tandas = [
        for (var i = 0; i < _filas.length; i += filasPorTanda)
          _filas.sublist(i, min(i + filasPorTanda, _filas.length)),
      ];
      _enAlta = necesitaAlta;
      _etapa = _Etapa.enviando;
    });

    if (necesitaAlta) {
      await _enviarAlta();
    } else {
      await _cargarAsistentes();
    }
  }

  /// Crea las cuentas nuevas y reactiva las elegidas (Edge Function de la
  /// fase 6, por tandas). Reintentar no repite las filas ya procesadas.
  Future<void> _enviarAlta() async {
    setState(() => _errorEnvio = null);
    while (_tandaActual < _tandas.length) {
      final tanda = _tandas[_tandaActual];
      try {
        final respuesta = await CargaAlumnosService.enviarTanda(
          cargaId: _cargaId,
          nombreArchivo:
              'Asistentes de "${widget.resumen.nombre}" · $_nombreArchivo',
          totalFilas: _filas.length,
          ultima: _tandaActual == _tandas.length - 1,
          filas: tanda
              .map((f) => f.aPayload(registrarNuevos: _registrarNuevos))
              .toList(),
        );
        if (!mounted) return;
        setState(() {
          _cargaId = respuesta.cargaId;
          for (final x in respuesta.resultados) {
            _resultadosAlta[x.fila] = x;
          }
          _tandaActual++;
        });
      } on CargaAlumnosException catch (e) {
        if (!mounted) return;
        setState(() => _errorEnvio = e.mensaje);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _enAlta = false);
    await _cargarAsistentes();
  }

  /// Agrega como asistentes a los alumnos que corresponde.
  Future<void> _cargarAsistentes() async {
    setState(() => _errorEnvio = null);
    final porUsuario = <String, FilaAsistente>{};

    for (final f in _filas) {
      f.resultado = null;
      f.detalle = null;
      final alta = _resultadosAlta[f.datos.numero];
      switch (f.estado) {
        case EstadoFilaAsistente.error:
          f.resultado = 'Con error';
          f.detalle = f.error;
        case EstadoFilaAsistente.seAgrega:
          porUsuario[f.existente!.id] = f;
        case EstadoFilaAsistente.desactivado:
          if (!f.reactivar) {
            f.resultado = 'Omitido';
            f.detalle = 'Cuenta desactivada (no se reactivó)';
          } else if (alta?.reactivado == true) {
            porUsuario[f.existente!.id] = f;
          } else {
            f.resultado = 'No se cargó';
            f.detalle = alta?.error ?? 'No se pudo reactivar la cuenta';
          }
        case EstadoFilaAsistente.noRegistrado:
          if (!_registrarNuevos) {
            f.resultado = 'Omitido';
            f.detalle = 'No está registrado (no se registró)';
          } else if (alta?.resultado == 'creado' && alta?.usuarioId != null) {
            porUsuario[alta!.usuarioId!] = f;
          } else {
            f.resultado = 'No se cargó';
            f.detalle = alta?.error ?? 'No se pudo crear la cuenta';
          }
      }
    }

    if (porUsuario.isEmpty) {
      setState(() => _etapa = _Etapa.terminado);
      return;
    }

    try {
      final resultados = await AsistentesPasadoService.cargar(
        widget.resumen.eventoId,
        porUsuario.keys.toList(),
        _motivo,
      );
      if (!mounted) return;
      for (final x in resultados) {
        final f = porUsuario[x.usuarioId];
        if (f == null) continue;
        f.resultado = x.legible;
        f.detalle = x.detalle ??
            (f.estado == EstadoFilaAsistente.noRegistrado
                ? 'Alumno registrado (clave inicial: C.I. + "$sufijoClaveInicial")'
                : (f.estado == EstadoFilaAsistente.desactivado
                    ? 'Cuenta reactivada'
                    : null));
      }
      ref.invalidate(resumenEventoPasadoProvider(widget.resumen.eventoId));
      ref.invalidate(adminEventosProvider);
      setState(() => _etapa = _Etapa.terminado);
    } on AsistentesException catch (e) {
      if (!mounted) return;
      setState(() => _errorEnvio = e.mensaje);
    }
  }

  void _reintentar() {
    if (_enAlta) {
      _enviarAlta();
    } else {
      _cargarAsistentes();
    }
  }

  Future<void> _descargarInforme() {
    String previa(FilaAsistente f) => switch (f.estado) {
          EstadoFilaAsistente.seAgrega => 'Registrado',
          EstadoFilaAsistente.desactivado => 'Cuenta desactivada',
          EstadoFilaAsistente.noRegistrado => 'No registrado',
          EstadoFilaAsistente.error => 'Con error',
        };

    final filas = <List<String>>[
      [
        'fila',
        'linea',
        'ci',
        'nombre_completo',
        'correo',
        'carrera',
        'horas_requeridas',
        'vista_previa',
        'resultado',
        'detalle',
      ],
      for (final f in _filas)
        [
          '${f.datos.numero}',
          '${f.datos.linea}',
          f.datos.ci,
          f.datos.nombre,
          f.datos.correo,
          f.datos.carrera,
          f.datos.horas,
          previa(f),
          f.resultado ?? 'Sin procesar',
          f.detalle ?? '',
        ],
    ];
    final fecha = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return _guardarArchivo(
      'informe_asistentes_$fecha.csv',
      generarCsv(filas, proteger: true),
    );
  }

  void _nuevaCarga() {
    setState(() {
      _etapa = _Etapa.inicio;
      _errorArchivo = null;
      _nombreArchivo = '';
      _filas = const [];
      _filtro = _Filtro.todas;
      _registrarNuevos = false;
      _motivo = '';
      _enAlta = false;
      _cargaId = null;
      _tandas = const [];
      _tandaActual = 0;
      _resultadosAlta.clear();
      _errorEnvio = null;
    });
  }

  // ---------------------------------------------------------------
  // Vistas
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Mantiene cargada la lista oficial mientras se usa la pestaña.
    ref.watch(carrerasProvider);

    return PopScope(
      canPop: _etapa != _Etapa.enviando,
      child: switch (_etapa) {
        _Etapa.inicio => _vistaInicio(context),
        _Etapa.previa => _vistaPrevia(context),
        _Etapa.enviando => _vistaEnviando(context),
        _Etapa.terminado => _vistaTerminado(context),
      },
    );
  }

  Widget _vistaInicio(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodyMedium;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '1. Descargá la plantilla (la misma de la carga masiva) y la lista '
          'de carreras del evento.\n'
          '2. Completá una fila por asistente. Los alumnos registrados se '
          'reconocen por la C.I. y sus datos no cambian. Para los que no '
          'están registrados, completá todos los datos: se podrán dar de '
          'alta.\n'
          '3. Guardá el archivo como CSV con separador ";" (máximo '
          '$maxFilasArchivo filas).\n'
          '4. Elegí el archivo y revisá la vista previa antes de cargar.',
          style: estilo,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () => _guardarArchivo(
                  'plantilla_asistentes.csv', generarPlantillaCsv()),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Descargar plantilla'),
            ),
            OutlinedButton.icon(
              onPressed: _descargarCarreras,
              icon: const Icon(Icons.list_alt_outlined),
              label: const Text('Descargar carreras del evento'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _leyendo ? null : _elegirArchivo,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Elegir archivo CSV'),
        ),
        if (_leyendo) ...[
          const SizedBox(height: 16),
          const Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Leyendo y verificando el archivo…')),
            ],
          ),
        ],
        if (_errorArchivo != null) ...[
          const SizedBox(height: 16),
          _Recuadro(
            icono: Icons.error_outline,
            color: UniNorteColors.error,
            texto: _errorArchivo!,
          ),
        ],
      ],
    );
  }

  Widget _vistaPrevia(BuildContext context) {
    final seAgregan = _filas
        .where((f) =>
            f.estado == EstadoFilaAsistente.seAgrega ||
            f.estado == EstadoFilaAsistente.desactivado)
        .toList();
    final noRegistrados = _con(EstadoFilaAsistente.noRegistrado).toList();
    final errores = _con(EstadoFilaAsistente.error).toList();
    final desactivados = _con(EstadoFilaAsistente.desactivado).toList();
    final todasReactivadas =
        desactivados.isNotEmpty && desactivados.every((f) => f.reactivar);

    final visibles = switch (_filtro) {
      _Filtro.todas => _filas,
      _Filtro.seAgregan => seAgregan,
      _Filtro.noRegistrados => noRegistrados,
      _Filtro.errores => errores,
    };

    ChoiceChip chip(String texto, _Filtro f) => ChoiceChip(
          label: Text(texto),
          selected: _filtro == f,
          selectedColor: UniNorteColors.dorado,
          backgroundColor: Colors.white,
          onSelected: (_) => setState(() => _filtro = f),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Text('$_nombreArchivo · ${_filas.length} filas',
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  chip('Todas (${_filas.length})', _Filtro.todas),
                  chip('Registrados (${seAgregan.length})', _Filtro.seAgregan),
                  chip('No registrados (${noRegistrados.length})',
                      _Filtro.noRegistrados),
                  chip('Con error (${errores.length})', _Filtro.errores),
                ],
              ),
              if (noRegistrados.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: UniNorteColors.azulMarino.withValues(alpha: 0.05),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_plural(noRegistrados.length, 'Este alumno no está registrado', 'Estos ${noRegistrados.length} alumnos no están registrados')}. '
                          '¿Desea registrarlos?',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: UniNorteColors.textoPrimario,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Se crean con los datos del archivo y la clave '
                          'inicial C.I. + "$sufijoClaveInicial", y quedan '
                          'como asistentes. Si no los registrás, se omiten.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Sí, registrarlos y cargarlos'),
                          value: _registrarNuevos,
                          activeThumbColor: UniNorteColors.azulMarino,
                          onChanged: (v) => setState(() => _registrarNuevos = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (desactivados.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: Text(
                        'Reactivar las cuentas desactivadas (${desactivados.length})'),
                    selected: todasReactivadas,
                    selectedColor: UniNorteColors.dorado,
                    onSelected: (v) => setState(() {
                      for (final f in desactivados) {
                        f.reactivar = v;
                      }
                    }),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (visibles.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No hay filas con este filtro',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium),
                )
              else
                for (final f in visibles) ...[
                  _TarjetaFila(
                    fila: f,
                    registrarNuevos: _registrarNuevos,
                    onReactivar: (v) => setState(() => f.reactivar = v),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _nuevaCarga,
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _aCargar == 0 ? null : _confirmar,
                    icon: const Icon(Icons.how_to_reg_outlined),
                    label: Text('Cargar asistentes ($_aCargar)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _vistaEnviando(BuildContext context) {
    final total = _tandas.length;
    final texto = _errorEnvio != null
        ? (_enAlta
            ? 'La creación de cuentas se detuvo en la tanda '
                '${_tandaActual + 1} de $total'
            : 'No se pudieron cargar los asistentes')
        : (_enAlta
            ? 'Registrando alumnos: tanda ${min(_tandaActual + 1, total)} de $total…'
            : 'Cargando asistentes…');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(texto,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (_errorEnvio == null) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text('No cierres esta pantalla hasta que termine.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          if (_errorEnvio != null) ...[
            const SizedBox(height: 20),
            _Recuadro(
              icono: Icons.error_outline,
              color: UniNorteColors.error,
              texto: _errorEnvio!,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _reintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            const SizedBox(height: 8),
            Text(
              _enAlta
                  ? 'Las filas que ya se procesaron no se repiten.'
                  : 'Las cuentas nuevas o reactivadas ya quedaron listas; '
                      'al reintentar no se duplican.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!_enAlta) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _etapa = _Etapa.terminado),
                child: const Text('Terminar sin cargar asistentes'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _vistaTerminado(BuildContext context) {
    const cargados = {'Agregado', 'Asistencia completada'};
    final nCargados =
        _filas.where((f) => cargados.contains(f.resultado)).length;
    final nYaEstaban =
        _filas.where((f) => f.resultado == 'Ya estaba cargado').length;
    final noCargados = _filas
        .where((f) =>
            !cargados.contains(f.resultado) &&
            f.resultado != 'Ya estaba cargado')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.check_circle_outline,
            color: UniNorteColors.exito, size: 56),
        const SizedBox(height: 8),
        Text('Carga terminada',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            _TarjetaResumen(
                valor: nCargados,
                etiqueta: 'Cargados',
                color: UniNorteColors.exito),
            _TarjetaResumen(
                valor: nYaEstaban,
                etiqueta: 'Ya estaban',
                color: UniNorteColors.azulMarino),
            _TarjetaResumen(
                valor: noCargados.length,
                etiqueta: 'No cargados',
                color: UniNorteColors.error),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _descargarInforme,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Descargar informe'),
            ),
            OutlinedButton.icon(
              onPressed: _nuevaCarga,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Nueva carga'),
            ),
          ],
        ),
        if (noCargados.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Filas no cargadas',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final f in noCargados)
            Card(
              child: ListTile(
                title: Text(
                  'Fila ${f.datos.numero} · C.I. ${f.datos.ci} · '
                  '${f.datos.nombre}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${f.resultado ?? 'Sin procesar'}'
                  '${f.detalle == null ? '' : ': ${f.detalle}'}',
                  style: const TextStyle(color: UniNorteColors.error),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _TarjetaFila extends StatelessWidget {
  final FilaAsistente fila;
  final bool registrarNuevos;
  final ValueChanged<bool> onReactivar;

  const _TarjetaFila({
    required this.fila,
    required this.registrarNuevos,
    required this.onReactivar,
  });

  @override
  Widget build(BuildContext context) {
    final d = fila.datos;
    final u = fila.existente;
    final estilo = Theme.of(context).textTheme.bodyMedium;

    final (etiqueta, color) = switch (fila.estado) {
      EstadoFilaAsistente.seAgrega => ('Se agrega', UniNorteColors.exito),
      EstadoFilaAsistente.desactivado => (
          fila.reactivar ? 'Se reactiva y se agrega' : 'Cuenta desactivada',
          UniNorteColors.azulMarino,
        ),
      EstadoFilaAsistente.noRegistrado => (
          registrarNuevos ? 'Se registra y se agrega' : 'No registrado',
          UniNorteColors.azulMarino,
        ),
      EstadoFilaAsistente.error => ('Con error', UniNorteColors.error),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    d.nombre.isEmpty ? '(sin nombre)' : d.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: UniNorteColors.textoPrimario,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _Etiqueta(texto: etiqueta, color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text('Fila ${d.numero} (línea ${d.linea} del archivo)',
                style: estilo),
            Text('C.I. ${d.ci} · ${d.correo}', style: estilo),
            Text('${d.carrera} · ${d.horas} h', style: estilo),
            if (u != null)
              Text(
                'Registrado: ${u.nombreCompleto} · ${u.carrera}'
                '${u.activo ? '' : ' · Desactivado'} (sus datos no cambian)',
                style: estilo,
              ),
            if (fila.error != null) ...[
              const SizedBox(height: 8),
              _Recuadro(
                icono: Icons.error_outline,
                color: UniNorteColors.error,
                texto: fila.error!,
              ),
            ],
            if (fila.estado == EstadoFilaAsistente.desactivado) ...[
              const SizedBox(height: 8),
              FilterChip(
                label: const Text('Reactivar cuenta'),
                selected: fila.reactivar,
                selectedColor: UniNorteColors.dorado,
                onSelected: onReactivar,
              ),
            ],
          ],
        ),
      ),
    );
  }
}