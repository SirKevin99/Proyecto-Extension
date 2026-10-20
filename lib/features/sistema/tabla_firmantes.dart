import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'carreras_admin_provider.dart';

/// Tabla editable de firmantes por carrera (superadmin, web; fase 7.3b).
/// - Una fila por carrera: carrera, facultad, decano/a y cargo, director/a
///   y cargo. Columnas fijas; se pueden agregar filas (carreras nuevas).
/// - Los cambios quedan en la tabla hasta "Guardar cambios", que envía las
///   filas nuevas o modificadas y las guarda todas o ninguna.
/// - "Pegar desde Excel" carga varias filas copiadas de una planilla.
/// - Al cambiar el decano/a de una fila, ofrece aplicarlo a las demás
///   carreras de la misma facultad.
class TablaFirmantes extends StatefulWidget {
  final List<CarreraAdmin> carreras;

  /// Se llama después de guardar, para recargar los datos.
  final VoidCallback onGuardado;

  /// Avisa si hay cambios sin guardar (para confirmar al salir).
  final ValueChanged<bool> onCambiosPendientes;

  const TablaFirmantes({
    super.key,
    required this.carreras,
    required this.onGuardado,
    required this.onCambiosPendientes,
  });

  @override
  State<TablaFirmantes> createState() => _TablaFirmantesState();
}

const List<String> _cargosDecano = ['Decano', 'Decana'];
const List<String> _cargosDirector = [
  'Director',
  'Directora',
  'Coordinador',
  'Coordinadora',
];

/// Ancho de cada columna (la tabla se desplaza en horizontal).
const double _wNum = 48;
const double _wCarrera = 250;
const double _wFacultad = 220;
const double _wPersona = 250;
const double _wCargo = 140;
const double _wCargoDir = 160;
const double _wEstado = 130;
const double _wAccion = 48;
const double _anchoTabla = _wNum +
    _wCarrera +
    _wFacultad +
    _wPersona +
    _wCargo +
    _wPersona +
    _wCargoDir +
    _wEstado +
    _wAccion;

String _limpio(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
String? _oNull(String s) {
  final t = _limpio(s);
  return t.isEmpty ? null : t;
}

/// Una fila en edición. [original] null = carrera nueva.
class _Fila {
  final CarreraAdmin? original;
  final TextEditingController nombre;
  final TextEditingController facultad;
  final TextEditingController decano;
  final TextEditingController director;
  String? decanoCargo;
  String? directorCargo;

  _Fila(this.original)
      : nombre = TextEditingController(text: original?.nombre ?? ''),
        facultad = TextEditingController(text: original?.facultad ?? ''),
        decano = TextEditingController(text: original?.decanoNombre ?? ''),
        director = TextEditingController(text: original?.directorNombre ?? ''),
        decanoCargo = original?.decanoCargo,
        directorCargo = original?.directorCargo;

  bool get nueva => original == null;
  bool get activa => original?.activa ?? true;

  bool get renombrada =>
      !nueva && _limpio(nombre.text) != original!.nombre;

  bool get modificada {
    final o = original;
    if (o == null) return true;
    return _limpio(nombre.text) != o.nombre ||
        _oNull(facultad.text) != o.facultad ||
        _oNull(decano.text) != o.decanoNombre ||
        decanoCargo != o.decanoCargo ||
        _oNull(director.text) != o.directorNombre ||
        directorCargo != o.directorCargo;
  }

  /// Fila nueva todavía vacía (no se envía).
  bool get vacia =>
      nueva &&
      _oNull(nombre.text) == null &&
      _oNull(facultad.text) == null &&
      _oNull(decano.text) == null &&
      _oNull(director.text) == null &&
      decanoCargo == null &&
      directorCargo == null;

  FilaFirmantes aEnviar() => FilaFirmantes(
        id: original?.id,
        nombre: _limpio(nombre.text),
        facultad: _oNull(facultad.text),
        decanoNombre: _oNull(decano.text),
        decanoCargo: decanoCargo,
        directorNombre: _oNull(director.text),
        directorCargo: directorCargo,
      );

  void dispose() {
    nombre.dispose();
    facultad.dispose();
    decano.dispose();
    director.dispose();
  }
}

class _TablaFirmantesState extends State<TablaFirmantes>
    with AutomaticKeepAliveClientMixin {
  final List<_Fila> _filas = [];
  final _scrollH = ScrollController();
  final _scrollV = ScrollController();
  bool _guardando = false;
  bool _recargarAlLlegar = false;
  bool _avisadoCambios = false;

  @override
  bool get wantKeepAlive => true; // conserva lo editado al cambiar de pestaña

  @override
  void initState() {
    super.initState();
    _cargarDesde(widget.carreras);
  }

  @override
  void didUpdateWidget(covariant TablaFirmantes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.carreras, widget.carreras) &&
        (_recargarAlLlegar || !_hayCambios)) {
      _recargarAlLlegar = false;
      _cargarDesde(widget.carreras);
    }
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.dispose();
    }
    _scrollH.dispose();
    _scrollV.dispose();
    super.dispose();
  }

  void _cargarDesde(List<CarreraAdmin> carreras) {
    for (final f in _filas) {
      f.dispose();
    }
    _filas
      ..clear()
      ..addAll(carreras.map(_Fila.new));
    _notificarCambios();
  }

  bool get _hayCambios => _filas.any((f) => !f.vacia && f.modificada);

  int get _cantidadCambios =>
      _filas.where((f) => !f.vacia && f.modificada).length;

  void _notificarCambios() {
    final hay = _hayCambios;
    if (hay != _avisadoCambios) {
      _avisadoCambios = hay;
      // Puede llamarse durante la construcción (didUpdateWidget): el aviso
      // al padre se hace después del cuadro actual.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCambiosPendientes(_avisadoCambios);
      });
    }
  }

  void _cambio() {
    setState(() {});
    _notificarCambios();
  }

  void _mostrar(String texto, {bool error = false, SnackBarAction? accion}) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? UniNorteColors.error : UniNorteColors.azulMarino,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: accion == null ? 4 : 8),
      action: accion,
    ));
  }

  // ---------------- Acciones de la barra ----------------

  void _agregarFila() {
    setState(() => _filas.add(_Fila(null)));
    _notificarCambios();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollV.hasClients) {
        _scrollV.animateTo(_scrollV.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _quitarFila(_Fila f) {
    setState(() => _filas.remove(f));
    f.dispose();
    _notificarCambios();
  }

  Future<void> _descartar() async {
    final ok = await _confirmar(
      titulo: 'Descartar cambios',
      mensaje: 'Se perderán los $_cantidadCambios cambios sin guardar.',
      accion: 'Descartar',
    );
    if (!ok || !mounted) return;
    setState(() => _cargarDesde(widget.carreras));
  }

  /// Ofrece copiar decano/a y cargo a las otras carreras de la facultad.
  void _ofrecerPropagar(_Fila origen) {
    final fac = _oNull(origen.facultad.text)?.toLowerCase();
    final decano = _oNull(origen.decano.text);
    if (fac == null || decano == null || origen.decanoCargo == null) return;

    final otras = _filas.where((f) =>
        !identical(f, origen) &&
        _oNull(f.facultad.text)?.toLowerCase() == fac &&
        (_oNull(f.decano.text) != decano || f.decanoCargo != origen.decanoCargo));
    final lista = otras.toList();
    if (lista.isEmpty) return;

    _mostrar(
      '¿Aplicar este decano/a a las otras ${lista.length} carrera(s) de la '
      'Facultad de ${_limpio(origen.facultad.text)}?',
      accion: SnackBarAction(
        label: 'Aplicar',
        textColor: UniNorteColors.dorado,
        onPressed: () {
          if (!mounted) return;
          setState(() {
            for (final f in lista) {
              f.decano.text = decano;
              f.decanoCargo = origen.decanoCargo;
            }
          });
          _notificarCambios();
        },
      ),
    );
  }

  Future<void> _pegar() async {
    final filasPegadas = await showDialog<List<List<String>>>(
      context: context,
      builder: (_) => const _PegarDialog(),
    );
    if (filasPegadas == null || filasPegadas.isEmpty || !mounted) return;

    String? cargo(String v, List<String> opciones) {
      final t = _limpio(v).toLowerCase();
      if (t.isEmpty) return null;
      for (final o in opciones) {
        if (o.toLowerCase() == t) return o;
      }
      return '';
    }

    String sinPrefijo(String v, String prefijo) {
      final t = _limpio(v);
      return t.toLowerCase().startsWith(prefijo) ? t.substring(prefijo.length) : t;
    }

    var actualizadas = 0, nuevas = 0, cargosInvalidos = 0;
    setState(() {
      for (final c in filasPegadas) {
        String col(int i) => i < c.length ? c[i] : '';
        final nombre = sinPrefijo(col(0), 'carrera de ');
        if (nombre.isEmpty) continue;

        var fila = _filas.cast<_Fila?>().firstWhere(
            (f) => _limpio(f!.nombre.text).toLowerCase() == nombre.toLowerCase(),
            orElse: () => null);
        if (fila == null) {
          fila = _Fila(null)..nombre.text = nombre;
          _filas.add(fila);
          nuevas++;
        } else {
          actualizadas++;
        }
        fila.facultad.text = sinPrefijo(col(1), 'facultad de ');
        fila.decano.text = _limpio(col(2));
        final cd = cargo(col(3), _cargosDecano);
        final cr = cargo(col(5), _cargosDirector);
        if (cd == '' || cr == '') cargosInvalidos++;
        fila.decanoCargo = cd == '' ? null : cd;
        fila.director.text = _limpio(col(4));
        fila.directorCargo = cr == '' ? null : cr;
      }
    });
    _notificarCambios();
    _mostrar(
      'Pegado: $actualizadas fila(s) actualizada(s) y $nuevas nueva(s). '
      '${cargosInvalidos > 0 ? '$cargosInvalidos fila(s) con un cargo no reconocido: quedó vacío. ' : ''}'
      'Revisá y tocá "Guardar cambios".',
    );
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    final aEnviar = _filas.where((f) => !f.vacia && f.modificada).toList();
    if (aEnviar.isEmpty) {
      _mostrar('No hay cambios para guardar');
      return;
    }
    final sinNombre = aEnviar.where((f) => _oNull(f.nombre.text) == null);
    if (sinNombre.isNotEmpty) {
      _mostrar(
          'Fila ${_filas.indexOf(sinNombre.first) + 1}: falta el nombre de la carrera.',
          error: true);
      return;
    }

    final renombres = aEnviar.where((f) => f.renombrada).toList();
    if (renombres.isNotEmpty) {
      final detalle = renombres
          .map((f) =>
              '• ${f.original!.nombre} → ${_limpio(f.nombre.text)} '
              '(${f.original!.alumnosActivos} alumno(s) activo(s))')
          .join('\n');
      final ok = await _confirmar(
        titulo: 'Cambio de nombre',
        mensaje: 'Estas carreras cambian de nombre. Los usuarios que las '
            'tienen quedarán con el nombre nuevo; los certificados ya '
            'emitidos conservan el anterior.\n\n$detalle',
        accion: 'Guardar',
      );
      if (!ok || !mounted) return;
    }

    setState(() => _guardando = true);
    try {
      final r = await CarrerasAdminService.guardarFirmantes(
          aEnviar.map((f) => f.aEnviar()).toList());
      if (!mounted) return;
      final partes = [
        if (r.actualizadas > 0) '${r.actualizadas} actualizada(s)',
        if (r.creadas > 0) '${r.creadas} nueva(s)',
        if (r.usuariosRenombrados > 0)
          '${r.usuariosRenombrados} usuario(s) con el nombre nuevo',
        if (r.certificadosEmitidos > 0)
          '${r.certificadosEmitidos} certificado(s) emitido(s)',
      ];
      _mostrar('Guardado: ${partes.join(', ')}.');
      _recargarAlLlegar = true;
      widget.onGuardado();
    } on CarrerasException catch (e) {
      // El servidor numera las filas enviadas; se traduce a la fila de la tabla.
      final m = RegExp(r'^Fila (\d+):').firstMatch(e.mensaje);
      var mensaje = e.mensaje;
      if (m != null) {
        final i = int.parse(m.group(1)!) - 1;
        if (i >= 0 && i < aEnviar.length) {
          final f = aEnviar[i];
          mensaje = mensaje.replaceFirst(m.group(0)!,
              'Fila ${_filas.indexOf(f) + 1} (${_limpio(f.nombre.text)}):');
        }
      }
      _mostrar(mensaje, error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String mensaje,
    required String accion,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(titulo),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: Text(mensaje)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(accion),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ---------------- Construcción ----------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cambios = _cantidadCambios;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _guardando || cambios == 0 ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: UniNorteColors.azulMarino),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(cambios == 0
                    ? 'Guardar cambios'
                    : 'Guardar cambios ($cambios)'),
              ),
              _BotonBarra(
                icono: Icons.add,
                texto: 'Agregar fila',
                onPressed: _guardando ? null : _agregarFila,
              ),
              _BotonBarra(
                icono: Icons.content_paste,
                texto: 'Pegar desde Excel',
                onPressed: _guardando ? null : _pegar,
              ),
              _BotonBarra(
                icono: Icons.undo,
                texto: 'Descartar cambios',
                onPressed: _guardando || cambios == 0 ? null : _descartar,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Nombres sin "Carrera de" ni "Facultad de" (se agregan en el '
            'certificado) y con el título, tal como se imprimen '
            '(p. ej. "Ing. Karina Obregón"). Firma el director/a; si la '
            'carrera no tiene, el coordinador/a. Sin facultad, decano/a o '
            'director/a la carrera no emite certificados.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollH,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollH,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: _anchoTabla,
                child: Column(
                  children: [
                    const _Encabezado(),
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollV,
                        child: ListView.builder(
                          controller: _scrollV,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _filas.length,
                          itemBuilder: (context, i) => _filaWidget(i),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filaWidget(int i) {
    final f = _filas[i];
    final fondo = f.nueva
        ? UniNorteColors.exito.withValues(alpha: 0.06)
        : f.modificada
            ? UniNorteColors.dorado.withValues(alpha: 0.10)
            : (i.isEven ? Colors.white : UniNorteColors.fondoClaro);

    return Container(
      key: ObjectKey(f),
      color: fondo,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: _wNum,
            child: Text('${i + 1}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          _Celda(
            ancho: _wCarrera,
            child: f.activa
                ? _Texto(
                    controller: f.nombre,
                    habilitado: !_guardando,
                    pista: 'Carrera',
                    onChanged: _cambio,
                  )
                : Tooltip(
                    message: 'Reactivá la carrera para cambiarle el nombre',
                    child: _Texto(
                      controller: f.nombre,
                      habilitado: false,
                      pista: 'Carrera',
                      onChanged: _cambio,
                    ),
                  ),
          ),
          _Celda(
            ancho: _wFacultad,
            child: _Texto(
              controller: f.facultad,
              habilitado: !_guardando,
              pista: 'Facultad',
              onChanged: _cambio,
            ),
          ),
          _Celda(
            ancho: _wPersona,
            child: _Texto(
              controller: f.decano,
              habilitado: !_guardando,
              pista: 'Decano/a con título',
              onChanged: _cambio,
              onTerminado: () => _ofrecerPropagar(f),
            ),
          ),
          _Celda(
            ancho: _wCargo,
            child: _Opciones(
              valor: f.decanoCargo,
              opciones: _cargosDecano,
              habilitado: !_guardando,
              onChanged: (v) {
                f.decanoCargo = v;
                _cambio();
                _ofrecerPropagar(f);
              },
            ),
          ),
          _Celda(
            ancho: _wPersona,
            child: _Texto(
              controller: f.director,
              habilitado: !_guardando,
              pista: 'Director/a con título',
              onChanged: _cambio,
            ),
          ),
          _Celda(
            ancho: _wCargoDir,
            child: _Opciones(
              valor: f.directorCargo,
              opciones: _cargosDirector,
              habilitado: !_guardando,
              onChanged: (v) {
                f.directorCargo = v;
                _cambio();
              },
            ),
          ),
          SizedBox(width: _wEstado, child: _Estado(fila: f)),
          SizedBox(
            width: _wAccion,
            child: f.nueva
                ? IconButton(
                    tooltip: 'Quitar fila',
                    icon: const Icon(Icons.close,
                        color: UniNorteColors.textoSecundario),
                    onPressed: _guardando ? null : () => _quitarFila(f),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// Piezas de la tabla
// ---------------------------------------------------------------

class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    );
    Widget celda(double w, String t) => SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(t, style: estilo),
          ),
        );

    return Container(
      decoration: const BoxDecoration(
        color: UniNorteColors.azulMarino,
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          celda(_wNum, '#'),
          celda(_wCarrera, 'Carrera'),
          celda(_wFacultad, 'Facultad'),
          celda(_wPersona, 'Decano/a'),
          celda(_wCargo, 'Cargo'),
          celda(_wPersona, 'Director/a de la carrera'),
          celda(_wCargoDir, 'Cargo'),
          celda(_wEstado, 'Estado'),
          celda(_wAccion, ''),
        ],
      ),
    );
  }
}

class _Celda extends StatelessWidget {
  final double ancho;
  final Widget child;
  const _Celda({required this.ancho, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: ancho,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: child,
        ),
      );
}

const InputDecoration _decoracionCelda = InputDecoration(
  isDense: true,
  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
);

class _Texto extends StatelessWidget {
  final TextEditingController controller;
  final bool habilitado;
  final String pista;
  final VoidCallback onChanged;
  final VoidCallback? onTerminado;

  const _Texto({
    required this.controller,
    required this.habilitado,
    required this.pista,
    required this.onChanged,
    this.onTerminado,
  });

  @override
  Widget build(BuildContext context) {
    final campo = TextField(
      controller: controller,
      enabled: habilitado,
      style: const TextStyle(fontSize: 14),
      decoration: _decoracionCelda.copyWith(hintText: pista),
      onChanged: (_) => onChanged(),
    );
    final alTerminar = onTerminado;
    if (alTerminar == null) return campo;
    // Al salir del campo (Tab, clic en otra celda) se ofrece propagar.
    return Focus(
      skipTraversal: true,
      onFocusChange: (tieneFoco) {
        if (!tieneFoco) alTerminar();
      },
      child: campo,
    );
  }
}

class _Opciones extends StatelessWidget {
  final String? valor;
  final List<String> opciones;
  final bool habilitado;
  final ValueChanged<String?> onChanged;

  const _Opciones({
    required this.valor,
    required this.opciones,
    required this.habilitado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // DropdownButton (no FormField): el valor se toma siempre de la fila,
    // así se actualiza al pegar, propagar o descartar.
    return InputDecorator(
      decoration: _decoracionCelda.copyWith(enabled: habilitado),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: opciones.contains(valor) ? valor : null,
          isExpanded: true,
          isDense: true,
          style: const TextStyle(
              fontSize: 14, color: UniNorteColors.textoPrimario),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final o in opciones)
              DropdownMenuItem<String?>(value: o, child: Text(o)),
          ],
          onChanged: habilitado ? onChanged : null,
        ),
      ),
    );
  }
}

class _Estado extends StatelessWidget {
  final _Fila fila;
  const _Estado({required this.fila});

  @override
  Widget build(BuildContext context) {
    final o = fila.original;
    final (texto, color) = o == null
        ? ('Nueva', UniNorteColors.exito)
        : !o.activa
            ? ('Desactivada', UniNorteColors.error)
            : fila.modificada
                ? ('Modificada', UniNorteColors.azulMarino)
                : ('Activa', UniNorteColors.textoSecundario);

    final pendientes = o?.certificadosPendientes ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(texto,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          if (pendientes > 0)
            Text('$pendientes cert. pendiente(s)',
                style: const TextStyle(
                    color: UniNorteColors.textoSecundario, fontSize: 11)),
        ],
      ),
    );
  }
}

class _BotonBarra extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback? onPressed;

  const _BotonBarra({
    required this.icono,
    required this.texto,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      icon: Icon(icono, size: 20),
      label: Text(texto),
    );
  }
}

// ---------------------------------------------------------------
// Pegar desde Excel
// ---------------------------------------------------------------

/// Recibe filas copiadas de Excel (columnas separadas por tabulación;
/// también acepta ";"). Orden: Carrera, Facultad, Decano/a, Cargo,
/// Director/a, Cargo. Si la primera fila es el encabezado, se ignora.
class _PegarDialog extends StatefulWidget {
  const _PegarDialog();

  @override
  State<_PegarDialog> createState() => _PegarDialogState();
}

class _PegarDialogState extends State<_PegarDialog> {
  final _texto = TextEditingController();

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  List<List<String>> _filas() {
    final lineas = _texto.text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final filas = [
      for (final l in lineas)
        (l.contains('\t') ? l.split('\t') : l.split(';'))
            .map((c) => c.trim().replaceAll(RegExp(r'^"|"$'), ''))
            .toList(),
    ];
    if (filas.isNotEmpty &&
        filas.first.isNotEmpty &&
        filas.first.first.toLowerCase().startsWith('carrera')) {
      filas.removeAt(0); // encabezado
    }
    return filas;
  }

  @override
  Widget build(BuildContext context) {
    final cantidad = _filas().length;
    return AlertDialog(
      title: const Text('Pegar desde Excel'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Copiá las filas en Excel con estas columnas, en este orden, y '
              'pegalas acá (Ctrl+V):\n'
              'Carrera · Facultad · Decano/a · Cargo (Decano/Decana) · '
              'Director/a · Cargo (Director/Directora/Coordinador/Coordinadora)\n'
              'Las carreras que ya existen se actualizan; las demás se '
              'agregan como filas nuevas. Nada se guarda hasta tocar '
              '"Guardar cambios".',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _texto,
              maxLines: 10,
              minLines: 6,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: const InputDecoration(hintText: 'Pegá aquí…'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              cantidad == 1 ? '1 fila detectada' : '$cantidad filas detectadas',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: cantidad == 0
              ? null
              : () => Navigator.of(context).pop(_filas()),
          child: const Text('Cargar en la tabla'),
        ),
      ],
    );
  }
}