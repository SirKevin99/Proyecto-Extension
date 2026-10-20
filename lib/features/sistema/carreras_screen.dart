import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/carreras_provider.dart';
import 'carreras_admin_provider.dart';

/// Administración de carreras y facultades (solo superadmin, fase 7).
/// - Crear, editar (renombrar), desactivar y reactivar carreras.
/// - Crear y editar facultades (no se desactivan).
/// Facultad y director/a de cada carrera, y decano/a de cada facultad,
/// son los firmantes del certificado.
class CarrerasScreen extends ConsumerStatefulWidget {
  const CarrerasScreen({super.key});

  @override
  ConsumerState<CarrerasScreen> createState() => _CarrerasScreenState();
}

class _CarrerasScreenState extends ConsumerState<CarrerasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });

  bool _ocupado = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _mostrar(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? UniNorteColors.error : UniNorteColors.exito,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Refresca esta pantalla y las listas de carreras del resto de la app
  /// (alta de usuarios, eventos).
  void _refrescar() {
    ref.invalidate(carrerasAdminProvider);
    ref.invalidate(facultadesProvider);
    ref.invalidate(carrerasProvider);
  }

  // ---------------- Carreras ----------------

  Future<void> _abrirCarrera(CarreraAdmin? carrera) async {
    final List<Facultad> facultades;
    try {
      facultades = await CarrerasAdminService.listarFacultades();
    } on CarrerasException catch (e) {
      _mostrar(e.mensaje, error: true);
      return;
    }
    if (!mounted) return;
    if (facultades.isEmpty) {
      _mostrar('Primero creá una facultad en la pestaña "Facultades".',
          error: true);
      return;
    }

    final mensaje = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _FormCarreraDialog(carrera: carrera, facultades: facultades),
    );
    if (mensaje == null || !mounted) return;
    _refrescar();
    _mostrar(mensaje);
  }

  Future<void> _desactivar(CarreraAdmin c) async {
    setState(() => _ocupado = true);
    final ResumenCarrera r;
    try {
      r = await CarrerasAdminService.resumen(c.id);
    } on CarrerasException catch (e) {
      if (mounted) {
        setState(() => _ocupado = false);
        _mostrar(e.mensaje, error: true);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _ocupado = false);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AlertaDesactivar(carrera: c, resumen: r),
    );
    if (ok != true || !mounted) return;

    setState(() => _ocupado = true);
    try {
      await CarrerasAdminService.desactivar(c.id);
      if (!mounted) return;
      _refrescar();
      _mostrar('Carrera desactivada');
    } on CarrerasException catch (e) {
      if (mounted) _mostrar(e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _reactivar(CarreraAdmin c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reactivar carrera'),
        content: Text(
          '"${c.nombre}" volverá a estar disponible para altas de alumnos '
          'y para habilitar eventos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reactivar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _ocupado = true);
    try {
      await CarrerasAdminService.reactivar(c.id);
      if (!mounted) return;
      _refrescar();
      _mostrar('Carrera reactivada');
    } on CarrerasException catch (e) {
      if (mounted) _mostrar(e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ---------------- Facultades ----------------

  Future<void> _abrirFacultad(Facultad? facultad) async {
    final mensaje = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FormFacultadDialog(facultad: facultad),
    );
    if (mensaje == null || !mounted) return;
    _refrescar();
    _mostrar(mensaje);
  }

  @override
  Widget build(BuildContext context) {
    final enCarreras = _tabs.index == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carreras y facultades'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: UniNorteColors.dorado,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          tabs: const [
            Tab(text: 'Carreras'),
            Tab(text: 'Facultades'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ocupado
            ? null
            : () => enCarreras ? _abrirCarrera(null) : _abrirFacultad(null),
        backgroundColor: UniNorteColors.dorado,
        foregroundColor: UniNorteColors.azulMarino,
        icon: const Icon(Icons.add),
        label: Text(enCarreras ? 'Nueva carrera' : 'Nueva facultad'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_ocupado) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _ListaCarreras(
                    habilitado: !_ocupado,
                    onEditar: _abrirCarrera,
                    onDesactivar: _desactivar,
                    onReactivar: _reactivar,
                  ),
                  _ListaFacultades(
                    habilitado: !_ocupado,
                    onEditar: _abrirFacultad,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Lista de carreras
// ---------------------------------------------------------------

class _ListaCarreras extends ConsumerWidget {
  final bool habilitado;
  final void Function(CarreraAdmin) onEditar;
  final void Function(CarreraAdmin) onDesactivar;
  final void Function(CarreraAdmin) onReactivar;

  const _ListaCarreras({
    required this.habilitado,
    required this.onEditar,
    required this.onDesactivar,
    required this.onReactivar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carrerasAsync = ref.watch(carrerasAdminProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(carrerasAdminProvider.future),
      child: carrerasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Mensaje(
          icono: Icons.error_outline,
          texto: e is CarrerasException
              ? e.mensaje
              : 'No se pudo cargar la lista de carreras',
          accion: OutlinedButton(
            onPressed: () => ref.invalidate(carrerasAdminProvider),
            child: const Text('Reintentar'),
          ),
        ),
        data: (carreras) {
          if (carreras.isEmpty) {
            return const _Mensaje(
              icono: Icons.school_outlined,
              texto: 'No hay carreras cargadas',
            );
          }
          final sinFirmantes =
              carreras.where((c) => c.activa && c.faltanFirmantes).length;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (sinFirmantes > 0) ...[
                _Aviso(
                  texto: sinFirmantes == 1
                      ? '1 carrera activa no tiene facultad o director/a. '
                          'Completalos para que el certificado tenga firmantes.'
                      : '$sinFirmantes carreras activas no tienen facultad o '
                          'director/a. Completalos para que el certificado '
                          'tenga firmantes.',
                ),
                const SizedBox(height: 12),
              ],
              for (final c in carreras)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TarjetaCarrera(
                    carrera: c,
                    habilitado: habilitado,
                    onEditar: () => onEditar(c),
                    onDesactivar: () => onDesactivar(c),
                    onReactivar: () => onReactivar(c),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

enum _AccionCarrera { editar, desactivar, reactivar }

class _TarjetaCarrera extends StatelessWidget {
  final CarreraAdmin carrera;
  final bool habilitado;
  final VoidCallback onEditar;
  final VoidCallback onDesactivar;
  final VoidCallback onReactivar;

  const _TarjetaCarrera({
    required this.carrera,
    required this.habilitado,
    required this.onEditar,
    required this.onDesactivar,
    required this.onReactivar,
  });

  @override
  Widget build(BuildContext context) {
    final c = carrera;
    final colorIcono =
        c.activa ? UniNorteColors.azulMarino : UniNorteColors.textoSecundario;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: habilitado ? onEditar : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (c.activa
                          ? UniNorteColors.dorado
                          : UniNorteColors.textoSecundario)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.school_outlined, color: colorIcono),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.nombre,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: UniNorteColors.textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.facultad == null
                          ? 'Sin facultad'
                          : 'Facultad de ${c.facultad}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      c.directorNombre == null
                          ? 'Sin director/a'
                          : '${c.directorCargo}: ${c.directorNombre}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Etiqueta(
                          texto: c.alumnosActivos == 1
                              ? '1 alumno activo'
                              : '${c.alumnosActivos} alumnos activos',
                          color: UniNorteColors.azulMarino,
                        ),
                        _Etiqueta(
                          texto: c.eventosVigentes == 1
                              ? '1 evento vigente'
                              : '${c.eventosVigentes} eventos vigentes',
                          color: UniNorteColors.azulMarino,
                        ),
                        if (!c.activa)
                          const _Etiqueta(
                            texto: 'Desactivada',
                            color: UniNorteColors.error,
                          ),
                        if (c.activa && c.faltanFirmantes)
                          const _Etiqueta(
                            texto: 'Faltan firmantes',
                            color: UniNorteColors.advertencia,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_AccionCarrera>(
                tooltip: 'Acciones',
                enabled: habilitado,
                onSelected: (a) {
                  switch (a) {
                    case _AccionCarrera.editar:
                      onEditar();
                    case _AccionCarrera.desactivar:
                      onDesactivar();
                    case _AccionCarrera.reactivar:
                      onReactivar();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _AccionCarrera.editar,
                    child: Text('Editar'),
                  ),
                  if (c.activa)
                    const PopupMenuItem(
                      value: _AccionCarrera.desactivar,
                      child: Text('Desactivar',
                          style: TextStyle(color: UniNorteColors.error)),
                    )
                  else
                    const PopupMenuItem(
                      value: _AccionCarrera.reactivar,
                      child: Text('Reactivar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Lista de facultades
// ---------------------------------------------------------------

class _ListaFacultades extends ConsumerWidget {
  final bool habilitado;
  final void Function(Facultad) onEditar;

  const _ListaFacultades({required this.habilitado, required this.onEditar});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facultadesAsync = ref.watch(facultadesProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(facultadesProvider.future),
      child: facultadesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Mensaje(
          icono: Icons.error_outline,
          texto: e is CarrerasException
              ? e.mensaje
              : 'No se pudo cargar la lista de facultades',
          accion: OutlinedButton(
            onPressed: () => ref.invalidate(facultadesProvider),
            child: const Text('Reintentar'),
          ),
        ),
        data: (facultades) {
          if (facultades.isEmpty) {
            return const _Mensaje(
              icono: Icons.account_balance_outlined,
              texto: 'Todavía no hay facultades.\n'
                  'Creá la primera con "Nueva facultad".',
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: facultades.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final f = facultades[i];
              return Card(
                child: ListTile(
                  enabled: habilitado,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: UniNorteColors.dorado.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_outlined,
                        color: UniNorteColors.azulMarino),
                  ),
                  title: Text(
                    'Facultad de ${f.nombre}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: UniNorteColors.textoPrimario,
                    ),
                  ),
                  subtitle: Text('${f.decanoCargo}: ${f.decanoNombre}'),
                  trailing: const Icon(Icons.chevron_right,
                      color: UniNorteColors.textoSecundario),
                  onTap: () => onEditar(f),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------
// Formulario de carrera (crear / editar)
// ---------------------------------------------------------------

/// Devuelve el mensaje de éxito al cerrarse, o null si se canceló.
class _FormCarreraDialog extends StatefulWidget {
  final CarreraAdmin? carrera; // null = nueva
  final List<Facultad> facultades;

  const _FormCarreraDialog({required this.carrera, required this.facultades});

  @override
  State<_FormCarreraDialog> createState() => _FormCarreraDialogState();
}

class _FormCarreraDialogState extends State<_FormCarreraDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.carrera?.nombre);
  late final _director =
      TextEditingController(text: widget.carrera?.directorNombre);
  late int? _facultadId = widget.carrera?.facultadId;
  late String? _cargo = widget.carrera?.directorCargo;

  bool _guardando = false;
  String? _error;

  bool get _esNueva => widget.carrera == null;

  /// Una carrera desactivada no se puede renombrar (script 19).
  bool get _nombreBloqueado => !_esNueva && !widget.carrera!.activa;

  @override
  void dispose() {
    _nombre.dispose();
    _director.dispose();
    super.dispose();
  }

  String _limpio(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_cargo == null) {
      setState(() => _error = 'Elegí el cargo: Director o Directora.');
      return;
    }

    final nombre = _limpio(_nombre.text);
    final director = _limpio(_director.text);
    final c = widget.carrera;
    final renombra = c != null && nombre != c.nombre;

    if (c != null && renombra) {
      final alumnos = c.alumnosActivos == 1
          ? '1 alumno activo'
          : '${c.alumnosActivos} alumnos activos';
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cambiar el nombre'),
          content: Text(
            '"${c.nombre}" pasará a llamarse "$nombre".\n\n'
            'Todos los usuarios que tienen esta carrera '
            '($alumnos, '
            'además de los inactivos y administradores) quedarán con el '
            'nombre nuevo. Los eventos habilitados no cambian.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cambiar nombre'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _guardando = true);
    try {
      String mensaje;
      if (c == null) {
        await CarrerasAdminService.crearCarrera(
          nombre: nombre,
          facultadId: _facultadId!,
          directorNombre: director,
          directorCargo: _cargo!,
        );
        mensaje = 'Carrera creada';
      } else {
        final n = await CarrerasAdminService.editarCarrera(
          id: c.id,
          nombre: nombre,
          facultadId: _facultadId!,
          directorNombre: director,
          directorCargo: _cargo!,
        );
        mensaje = !renombra
            ? 'Cambios guardados'
            : n == 1
                ? 'Carrera renombrada (1 usuario actualizado)'
                : 'Carrera renombrada ($n usuarios actualizados)';
      }
      if (!mounted) return;
      Navigator.of(context).pop(mensaje);
    } on CarrerasException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facultadValida =
        widget.facultades.any((f) => f.id == _facultadId) ? _facultadId : null;

    return AlertDialog(
      title: Text(_esNueva ? 'Nueva carrera' : 'Editar carrera'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nombre,
                  enabled: !_guardando && !_nombreBloqueado,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Nombre de la carrera',
                    prefixIcon: const Icon(Icons.school_outlined),
                    helperText: _nombreBloqueado
                        ? 'Reactivá la carrera para cambiarle el nombre.'
                        : 'Sin "Carrera de" (se agrega en el certificado).',
                    helperMaxLines: 2,
                  ),
                  validator: (v) {
                    final t = _limpio(v ?? '');
                    if (t.length < 3 || t.length > 120) {
                      return 'Entre 3 y 120 caracteres';
                    }
                    if (RegExp(r'^carrera(\s|$)', caseSensitive: false)
                        .hasMatch(t)) {
                      return 'Escribilo sin "Carrera de"';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: facultadValida,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Facultad',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                  items: [
                    for (final f in widget.facultades)
                      DropdownMenuItem(
                        value: f.id,
                        child: Text('Facultad de ${f.nombre}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _facultadId = v),
                  validator: (v) => v == null ? 'Elegí una facultad' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _director,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Director/a de la carrera',
                    prefixIcon: Icon(Icons.person_outline),
                    helperText: 'Con su título, tal como va en el certificado '
                        '(p. ej. "Prof. Dra. María Pérez").',
                    helperMaxLines: 2,
                  ),
                  validator: (v) {
                    final t = _limpio(v ?? '');
                    if (t.length < 5 || t.length > 150) {
                      return 'Ingresá el nombre con su título';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Text('Cargo', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final cargo in const ['Director', 'Directora'])
                      ChoiceChip(
                        label: Text(cargo),
                        selected: _cargo == cargo,
                        selectedColor: UniNorteColors.dorado,
                        backgroundColor: Colors.white,
                        onSelected: _guardando
                            ? null
                            : (_) => setState(() => _cargo = cargo),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: const TextStyle(color: UniNorteColors.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_esNueva ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Formulario de facultad (crear / editar)
// ---------------------------------------------------------------

class _FormFacultadDialog extends StatefulWidget {
  final Facultad? facultad; // null = nueva
  const _FormFacultadDialog({required this.facultad});

  @override
  State<_FormFacultadDialog> createState() => _FormFacultadDialogState();
}

class _FormFacultadDialogState extends State<_FormFacultadDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.facultad?.nombre);
  late final _decano =
      TextEditingController(text: widget.facultad?.decanoNombre);
  late String? _cargo = widget.facultad?.decanoCargo;

  bool _guardando = false;
  String? _error;

  bool get _esNueva => widget.facultad == null;

  @override
  void dispose() {
    _nombre.dispose();
    _decano.dispose();
    super.dispose();
  }

  String _limpio(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_cargo == null) {
      setState(() => _error = 'Elegí el cargo: Decano o Decana.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final f = widget.facultad;
      if (f == null) {
        await CarrerasAdminService.crearFacultad(
          nombre: _limpio(_nombre.text),
          decanoNombre: _limpio(_decano.text),
          decanoCargo: _cargo!,
        );
      } else {
        await CarrerasAdminService.editarFacultad(
          id: f.id,
          nombre: _limpio(_nombre.text),
          decanoNombre: _limpio(_decano.text),
          decanoCargo: _cargo!,
        );
      }
      if (!mounted) return;
      Navigator.of(context)
          .pop(_esNueva ? 'Facultad creada' : 'Cambios guardados');
    } on CarrerasException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esNueva ? 'Nueva facultad' : 'Editar facultad'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nombre,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la facultad',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                    helperText:
                        'Sin "Facultad de" (se agrega en el certificado).',
                    helperMaxLines: 2,
                  ),
                  validator: (v) {
                    final t = _limpio(v ?? '');
                    if (t.length < 3 || t.length > 120) {
                      return 'Entre 3 y 120 caracteres';
                    }
                    if (RegExp(r'^facultad(\s|$)', caseSensitive: false)
                        .hasMatch(t)) {
                      return 'Escribilo sin "Facultad de"';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _decano,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Decano/a de la facultad',
                    prefixIcon: Icon(Icons.person_outline),
                    helperText: 'Con su título, tal como va en el certificado.',
                    helperMaxLines: 2,
                  ),
                  validator: (v) {
                    final t = _limpio(v ?? '');
                    if (t.length < 5 || t.length > 150) {
                      return 'Ingresá el nombre con su título';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Text('Cargo', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final cargo in const ['Decano', 'Decana'])
                      ChoiceChip(
                        label: Text(cargo),
                        selected: _cargo == cargo,
                        selectedColor: UniNorteColors.dorado,
                        backgroundColor: Colors.white,
                        onSelected: _guardando
                            ? null
                            : (_) => setState(() => _cargo = cargo),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: const TextStyle(color: UniNorteColors.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_esNueva ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Alerta previa a desactivar
// ---------------------------------------------------------------

class _AlertaDesactivar extends StatelessWidget {
  final CarreraAdmin carrera;
  final ResumenCarrera resumen;

  const _AlertaDesactivar({required this.carrera, required this.resumen});

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final estilo = Theme.of(context).textTheme.bodyMedium;

    Widget lista(String titulo, int total, List<String> muestra) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$titulo: $total',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: UniNorteColors.textoPrimario,
            ),
          ),
          for (final m in muestra)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('• $m', style: estilo),
            ),
          if (total > muestra.length)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('… y ${total - muestra.length} más', style: estilo),
            ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Desactivar carrera'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${carrera.nombre}" dejará de aparecer en las altas de '
                'alumnos (individual y CSV) y al crear o editar eventos. '
                'Sus alumnos siguen activos y conservan su carrera, pero no '
                'recibirán eventos nuevos.',
              ),
              const SizedBox(height: 16),
              lista('Alumnos activos', r.alumnosActivos, r.muestraAlumnos),
              if (r.adminsActivos > 0) ...[
                const SizedBox(height: 8),
                Text('Administradores activos: ${r.adminsActivos}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: UniNorteColors.textoPrimario,
                    )),
              ],
              const SizedBox(height: 12),
              lista('Eventos vigentes', r.eventosVigentes, r.muestraEventos),
              if (r.eventosSoloEstaCarrera > 0) ...[
                const SizedBox(height: 12),
                _Aviso(
                  texto: r.eventosSoloEstaCarrera == 1
                      ? '1 evento vigente está habilitado solo para esta '
                          'carrera. Sigue igual, pero si se editan sus '
                          'carreras habrá que elegir otra.'
                      : '${r.eventosSoloEstaCarrera} eventos vigentes están '
                          'habilitados solo para esta carrera. Siguen igual, '
                          'pero si se editan sus carreras habrá que elegir otra.',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: UniNorteColors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Desactivar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Piezas comunes
// ---------------------------------------------------------------

class _Aviso extends StatelessWidget {
  final String texto;
  const _Aviso({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UniNorteColors.advertencia.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: UniNorteColors.azulMarino, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: const TextStyle(color: UniNorteColors.textoPrimario)),
          ),
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

/// Mensaje centrado que permite el gesto de "tirar para actualizar".
class _Mensaje extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Widget? accion;

  const _Mensaje({required this.icono, required this.texto, this.accion});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icono, color: UniNorteColors.textoSecundario, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    texto,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (accion != null) ...[
                    const SizedBox(height: 12),
                    accion!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}