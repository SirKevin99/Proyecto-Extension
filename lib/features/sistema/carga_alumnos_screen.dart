import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../shared/carreras_provider.dart';
import 'carga_alumnos_csv.dart';
import 'carga_alumnos_provider.dart';

enum _Etapa { inicio, previa, enviando, terminado }

enum _FiltroPrevia { todas, nuevas, existentes, errores }

/// Carga masiva de alumnos por CSV (fase 6, solo superadmin).
class CargaAlumnosScreen extends ConsumerStatefulWidget {
  const CargaAlumnosScreen({super.key});

  @override
  ConsumerState<CargaAlumnosScreen> createState() => _CargaAlumnosScreenState();
}

class _CargaAlumnosScreenState extends ConsumerState<CargaAlumnosScreen> {
  _Etapa _etapa = _Etapa.inicio;

  // Lectura del archivo
  bool _leyendo = false;
  String? _errorArchivo;
  String _nombreArchivo = '';
  List<FilaPrevia> _filas = const [];
  _FiltroPrevia _filtro = _FiltroPrevia.todas;

  // Envío por tandas
  String? _cargaId;
  List<List<FilaPrevia>> _tandas = const [];
  int _tandaActual = 0;
  String? _errorEnvio;
  final Map<int, ResultadoFila> _resultados = {};

  Iterable<FilaPrevia> _conEstado(EstadoFila e) =>
      _filas.where((f) => f.estado == e);

  Iterable<FilaPrevia> get _desactivados => _conEstado(EstadoFila.existente)
      .where((f) => f.existenteDesactivado);

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

  Future<void> _descargarPlantilla() =>
      _guardarArchivo('plantilla_carga_alumnos.csv', generarPlantillaCsv());

  Future<void> _descargarCarreras() async {
    final List<Carrera> carreras;
    try {
      carreras = await ref.read(carrerasProvider.future);
    } catch (_) {
      if (!mounted) return;
      _aviso('No se pudo cargar la lista de carreras', esError: true);
      return;
    }
    await _guardarArchivo(
      'carreras_oficiales.csv',
      generarCarrerasCsv(carreras.map((c) => c.nombre).toList()),
    );
  }

  Future<void> _elegirArchivo() async {
    FilePickerResult? seleccion;
    try {
      seleccion = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true, // en web no hay ruta: se leen los bytes
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorArchivo = 'No se pudo abrir el selector de archivos');
      return;
    }
    if (seleccion == null || seleccion.files.isEmpty || !mounted) return;
    final archivo = seleccion.files.first;
    final nombre = archivo.name;

    setState(() {
      _leyendo = true;
      _errorArchivo = null;
    });
    try {
      final bytes = archivo.bytes;
      if (bytes == null) {
        throw const ArchivoInvalidoException(
          'No se pudo leer el contenido del archivo',
        );
      }
      final filasCsv = leerFilasCsv(bytes);
      final carreras = await ref.read(carrerasProvider.future);
      final existentes = await CargaAlumnosService.verificar(filasCsv);
      final previa = clasificarFilas(
        filas: filasCsv,
        carreras: carreras.map((c) => c.nombre).toSet(),
        existentes: existentes,
      );
      if (!mounted) return;
      setState(() {
        _nombreArchivo = nombre;
        _filas = previa;
        _filtro = _FiltroPrevia.todas;
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
  // Decisiones de la vista previa
  // ---------------------------------------------------------------

  void _accionParaTodas(AccionExistente accion) {
    setState(() {
      for (final f in _conEstado(EstadoFila.existente)) {
        if (accion == AccionExistente.actualizar && !f.puedeActualizar) continue;
        f.accion = accion;
      }
    });
  }

  void _reactivarTodas(bool valor) {
    setState(() {
      for (final f in _desactivados) {
        f.reactivar = valor;
      }
    });
  }

  // ---------------------------------------------------------------
  // Envío
  // ---------------------------------------------------------------

  Future<void> _confirmar() async {
    final existentes = _conEstado(EstadoFila.existente).toList();
    final nuevos = _conEstado(EstadoFila.nuevo).length;
    final errores = _conEstado(EstadoFila.error).length;
    final actualizar = existentes
        .where((f) => f.accion == AccionExistente.actualizar && f.puedeActualizar)
        .length;
    final reactivar =
        existentes.where((f) => f.reactivar && f.existenteDesactivado).length;
    final omitir = existentes.length - actualizar;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar carga'),
        content: Text(
          'Se crearán $nuevos alumnos nuevos, se actualizarán $actualizar, '
          'se reactivarán $reactivar y se omitirán $omitir ya registrados. '
          '$errores filas con error quedarán registradas como rechazadas.\n\n'
          'La clave inicial de cada alumno nuevo será su C.I. seguida de '
          '"$sufijoClaveInicial".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    final tandas = <List<FilaPrevia>>[
      for (var i = 0; i < _filas.length; i += filasPorTanda)
        _filas.sublist(i, min(i + filasPorTanda, _filas.length)),
    ];
    setState(() {
      _tandas = tandas;
      _tandaActual = 0;
      _cargaId = null;
      _resultados.clear();
      _etapa = _Etapa.enviando;
    });
    await _enviarPendientes();
  }

  /// Envía las tandas que faltan. Reintentar reenvía la tanda que falló;
  /// el servidor no repite las filas que ya procesó.
  Future<void> _enviarPendientes() async {
    setState(() => _errorEnvio = null);
    while (_tandaActual < _tandas.length) {
      final tanda = _tandas[_tandaActual];
      try {
        final respuesta = await CargaAlumnosService.enviarTanda(
          cargaId: _cargaId,
          nombreArchivo: _nombreArchivo,
          totalFilas: _filas.length,
          ultima: _tandaActual == _tandas.length - 1,
          filas: tanda.map((f) => f.aPayload()).toList(),
        );
        if (!mounted) return;
        setState(() {
          _cargaId = respuesta.cargaId;
          for (final r in respuesta.resultados) {
            _resultados[r.fila] = r;
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
    setState(() => _etapa = _Etapa.terminado);
  }

  Future<void> _descargarInforme() {
    String accion(FilaPrevia f) => switch (f.aPayload()['accion']) {
          'crear' => 'Crear',
          'actualizar' => 'Actualizar',
          _ => 'Omitir',
        };
    String previa(FilaPrevia f) => switch (f.estado) {
          EstadoFila.nuevo => 'Nuevo',
          EstadoFila.existente => 'Ya existe',
          EstadoFila.error => 'Con error',
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
        'accion',
        'resultado',
        'reactivado',
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
          accion(f),
          _resultados[f.datos.numero]?.resultadoLegible ?? 'Sin procesar',
          (_resultados[f.datos.numero]?.reactivado ?? false) ? 'Sí' : 'No',
          _resultados[f.datos.numero]?.error ?? f.aviso ?? '',
        ],
    ];

    final fecha = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return _guardarArchivo(
      'informe_carga_alumnos_$fecha.csv',
      generarCsv(filas, proteger: true),
    );
  }

  void _nuevaCarga() {
    setState(() {
      _etapa = _Etapa.inicio;
      _errorArchivo = null;
      _nombreArchivo = '';
      _filas = const [];
      _filtro = _FiltroPrevia.todas;
      _cargaId = null;
      _tandas = const [];
      _tandaActual = 0;
      _errorEnvio = null;
      _resultados.clear();
    });
  }

  // ---------------------------------------------------------------
  // Vistas
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Mantiene cargada la lista oficial mientras se usa la pantalla.
    ref.watch(carrerasProvider);

    return PopScope(
      canPop: _etapa != _Etapa.enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Carga masiva de alumnos')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: switch (_etapa) {
                _Etapa.inicio => _vistaInicio(context),
                _Etapa.previa => _vistaPrevia(context),
                _Etapa.enviando => _vistaEnviando(context),
                _Etapa.terminado => _vistaTerminado(context),
              },
            ),
          ),
        ),
        bottomNavigationBar:
            _etapa == _Etapa.previa ? _barraConfirmar() : null,
      ),
    );
  }

  Widget _vistaInicio(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodyMedium;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Cargar alumnos desde un archivo CSV',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Paso(
                  numero: 1,
                  texto: 'Descargá la plantilla y la lista de carreras oficiales.',
                  estilo: estilo,
                ),
                _Paso(
                  numero: 2,
                  texto: 'Completá una fila por alumno: nombre completo, C.I. '
                      '(solo números), correo @uninorte.edu.py, carrera '
                      '(copiada tal cual de la lista oficial) y horas '
                      'requeridas (de 1 a 500).',
                  estilo: estilo,
                ),
                _Paso(
                  numero: 3,
                  texto: 'Guardá el archivo como CSV con separador ";" '
                      '(máximo $maxFilasArchivo filas).',
                  estilo: estilo,
                ),
                _Paso(
                  numero: 4,
                  texto: 'Elegí el archivo y revisá la vista previa antes '
                      'de confirmar.',
                  estilo: estilo,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _Recuadro(
          icono: Icons.key_outlined,
          color: UniNorteColors.azulMarino,
          texto: 'La clave inicial de cada alumno nuevo es su C.I. seguida '
              'de "$sufijoClaveInicial" (por ejemplo, 5826869$sufijoClaveInicial).',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _descargarPlantilla,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Descargar plantilla'),
            ),
            OutlinedButton.icon(
              onPressed: _descargarCarreras,
              icon: const Icon(Icons.list_alt_outlined),
              label: const Text('Descargar carreras oficiales'),
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
    final existentes = _conEstado(EstadoFila.existente).length;
    final desactivados = _desactivados.toList();
    final todasReactivadas =
        desactivados.isNotEmpty && desactivados.every((f) => f.reactivar);

    final visibles = switch (_filtro) {
      _FiltroPrevia.todas => _filas,
      _FiltroPrevia.nuevas => _conEstado(EstadoFila.nuevo).toList(),
      _FiltroPrevia.existentes => _conEstado(EstadoFila.existente).toList(),
      _FiltroPrevia.errores => _conEstado(EstadoFila.error).toList(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            '$_nombreArchivo · ${_filas.length} filas',
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _FilaFiltros(
          children: [
            _Filtro(
              texto: 'Todas (${_filas.length})',
              seleccionado: _filtro == _FiltroPrevia.todas,
              onTap: () => setState(() => _filtro = _FiltroPrevia.todas),
            ),
            _Filtro(
              texto: 'Nuevas (${_conEstado(EstadoFila.nuevo).length})',
              seleccionado: _filtro == _FiltroPrevia.nuevas,
              onTap: () => setState(() => _filtro = _FiltroPrevia.nuevas),
            ),
            _Filtro(
              texto: 'Ya existen ($existentes)',
              seleccionado: _filtro == _FiltroPrevia.existentes,
              onTap: () => setState(() => _filtro = _FiltroPrevia.existentes),
            ),
            _Filtro(
              texto: 'Con error (${_conEstado(EstadoFila.error).length})',
              seleccionado: _filtro == _FiltroPrevia.errores,
              onTap: () => setState(() => _filtro = _FiltroPrevia.errores),
            ),
          ],
        ),
        if (existentes > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Ya registrados:',
                    style: Theme.of(context).textTheme.bodyMedium),
                TextButton(
                  onPressed: () => _accionParaTodas(AccionExistente.omitir),
                  child: const Text('Omitir todas'),
                ),
                TextButton(
                  onPressed: () => _accionParaTodas(AccionExistente.actualizar),
                  child: const Text('Actualizar todas'),
                ),
                if (desactivados.isNotEmpty)
                  FilterChip(
                    label: Text(
                        'Reactivar las desactivadas (${desactivados.length})'),
                    selected: todasReactivadas,
                    selectedColor: UniNorteColors.dorado,
                    onSelected: _reactivarTodas,
                  ),
              ],
            ),
          ),
        Expanded(
          child: visibles.isEmpty
              ? Center(
                  child: Text('No hay filas con este filtro',
                      style: Theme.of(context).textTheme.bodyMedium),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: visibles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final fila = visibles[i];
                    return _TarjetaFila(
                      fila: fila,
                      onAccion: (a) => setState(() => fila.accion = a),
                      onReactivar: (v) => setState(() => fila.reactivar = v),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _barraConfirmar() {
    return SafeArea(
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
                onPressed: _confirmar,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Confirmar carga'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaEnviando(BuildContext context) {
    final total = _tandas.length;
    final progreso = total == 0 ? 0.0 : _tandaActual / total;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _errorEnvio == null
                ? 'Procesando tanda ${min(_tandaActual + 1, total)} de $total…'
                : 'La carga se detuvo en la tanda ${_tandaActual + 1} de $total',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progreso,
              minHeight: 8,
              backgroundColor: UniNorteColors.dorado.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(UniNorteColors.dorado),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No cierres esta pantalla hasta que termine.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_errorEnvio != null) ...[
            const SizedBox(height: 20),
            _Recuadro(
              icono: Icons.error_outline,
              color: UniNorteColors.error,
              texto: _errorEnvio!,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _enviarPendientes,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            const SizedBox(height: 8),
            Text(
              'Las filas que ya se procesaron no se repiten.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _vistaTerminado(BuildContext context) {
    final resultados = _resultados.values;
    int contar(String r) => resultados.where((x) => x.resultado == r).length;
    final reactivados = resultados.where((x) => x.reactivado).length;
    final rechazadas = _filas
        .where((f) => _resultados[f.datos.numero]?.resultado == 'rechazado')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.check_circle_outline,
            color: UniNorteColors.exito, size: 56),
        const SizedBox(height: 8),
        Text(
          'Carga finalizada',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            _TarjetaResumen(
                valor: contar('creado'),
                etiqueta: 'Creados',
                color: UniNorteColors.exito),
            _TarjetaResumen(
                valor: contar('actualizado'),
                etiqueta: 'Actualizados',
                color: UniNorteColors.azulMarino),
            _TarjetaResumen(
                valor: reactivados,
                etiqueta: 'Reactivados',
                color: UniNorteColors.azulMarino),
            _TarjetaResumen(
                valor: contar('omitido'),
                etiqueta: 'Omitidos',
                color: UniNorteColors.textoSecundario),
            _TarjetaResumen(
                valor: contar('rechazado'),
                etiqueta: 'Rechazados',
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
        if (rechazadas.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Filas rechazadas',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final f in rechazadas)
            Card(
              child: ListTile(
                title: Text(
                  'Fila ${f.datos.numero} · C.I. ${f.datos.ci} · '
                  '${f.datos.nombre}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _resultados[f.datos.numero]?.error ?? '',
                  style: const TextStyle(color: UniNorteColors.error),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------

class _TarjetaFila extends StatelessWidget {
  final FilaPrevia fila;
  final ValueChanged<AccionExistente> onAccion;
  final ValueChanged<bool> onReactivar;

  const _TarjetaFila({
    required this.fila,
    required this.onAccion,
    required this.onReactivar,
  });

  @override
  Widget build(BuildContext context) {
    final d = fila.datos;
    final u = fila.existente;
    final estilo = Theme.of(context).textTheme.bodyMedium;

    final (etiqueta, colorEtiqueta) = switch (fila.estado) {
      EstadoFila.nuevo => ('Nuevo', UniNorteColors.exito),
      EstadoFila.existente => ('Ya existe', UniNorteColors.azulMarino),
      EstadoFila.error => ('Con error', UniNorteColors.error),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                _Etiqueta(texto: etiqueta, color: colorEtiqueta),
              ],
            ),
            const SizedBox(height: 4),
            Text('Fila ${d.numero} (línea ${d.linea} del archivo)',
                style: estilo),
            Text('C.I. ${d.ci} · ${d.correo}', style: estilo),
            Text('${d.carrera} · ${d.horas} h', style: estilo),
            if (fila.error != null) ...[
              const SizedBox(height: 8),
              _Recuadro(
                icono: Icons.error_outline,
                color: UniNorteColors.error,
                texto: fila.error!,
              ),
            ],
            if (fila.aviso != null) ...[
              const SizedBox(height: 8),
              _Recuadro(
                icono: Icons.info_outline,
                color: UniNorteColors.azulMarino,
                texto: fila.aviso!,
              ),
            ],
            if (u != null) ...[
              const SizedBox(height: 8),
              Text(
                'Registrado: ${u.nombreCompleto} · ${u.carrera} · '
                '${u.horasRequeridas ?? '-'} h · '
                '${u.activo ? 'Activo' : 'Desactivado'}',
                style: estilo,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('Omitir'),
                    selected: fila.accion == AccionExistente.omitir,
                    selectedColor: UniNorteColors.dorado,
                    onSelected: (_) => onAccion(AccionExistente.omitir),
                  ),
                  ChoiceChip(
                    label: const Text('Actualizar datos'),
                    selected: fila.accion == AccionExistente.actualizar,
                    selectedColor: UniNorteColors.dorado,
                    onSelected: fila.puedeActualizar
                        ? (_) => onAccion(AccionExistente.actualizar)
                        : null,
                  ),
                  if (fila.existenteDesactivado)
                    FilterChip(
                      label: const Text('Reactivar cuenta'),
                      selected: fila.reactivar,
                      selectedColor: UniNorteColors.dorado,
                      onSelected: onReactivar,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  final int numero;
  final String texto;
  final TextStyle? estilo;

  const _Paso({required this.numero, required this.texto, this.estilo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: UniNorteColors.dorado.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$numero',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: UniNorteColors.azulMarino,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: estilo)),
        ],
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
      width: 140,
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
              Text(etiqueta, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilaFiltros extends StatelessWidget {
  final List<Widget> children;
  const _FilaFiltros({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          for (final c in children)
            Padding(padding: const EdgeInsets.only(right: 8), child: c),
        ],
      ),
    );
  }
}

class _Filtro extends StatelessWidget {
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _Filtro({
    required this.texto,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(texto),
      selected: seleccionado,
      selectedColor: UniNorteColors.dorado,
      backgroundColor: Colors.white,
      onSelected: (_) => onTap(),
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