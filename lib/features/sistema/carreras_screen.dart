import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/carreras_provider.dart';
import 'carreras_admin_provider.dart';
import 'tabla_firmantes.dart';

/// Carreras y firmantes (solo superadmin, fase 7).
/// - Pestaña "Carreras": estado de cada carrera, desactivar y reactivar.
/// - Pestaña "Firmantes": tabla editable para cargar facultad, decano/a y
///   director/a de cada carrera, agregar carreras nuevas y renombrarlas
///   (script 20, guardar_firmantes).
class CarrerasScreen extends ConsumerStatefulWidget {
  const CarrerasScreen({super.key});

  @override
  ConsumerState<CarrerasScreen> createState() => _CarrerasScreenState();
}

class _CarrerasScreenState extends ConsumerState<CarrerasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _ocupado = false;
  bool _cambiosSinGuardar = false;

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
    ref.invalidate(carrerasProvider);
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

  /// Confirma antes de salir si la tabla tiene cambios sin guardar.
  Future<void> _alIntentarSalir(bool yaSalio) async {
    if (yaSalio) return;
    final salir = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text(
            'La tabla de firmantes tiene cambios sin guardar. ¿Salir igual?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Seguir editando'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: UniNorteColors.error),
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Salir sin guardar'),
          ),
        ],
      ),
    );
    if (salir == true && mounted) {
      setState(() => _cambiosSinGuardar = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final carrerasAsync = ref.watch(carrerasAdminProvider);

    return PopScope(
      canPop: !_cambiosSinGuardar,
      onPopInvokedWithResult: (didPop, _) => _alIntentarSalir(didPop),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Carreras y firmantes'),
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: UniNorteColors.dorado,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
            tabs: const [
              Tab(text: 'Carreras'),
              Tab(text: 'Firmantes'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_ocupado) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: carrerasAsync.when(
                  // Mientras recarga (después de guardar) se siguen
                  // mostrando los datos anteriores.
                  skipLoadingOnRefresh: true,
                  skipLoadingOnReload: true,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
                  data: (carreras) => TabBarView(
                    controller: _tabs,
                    children: [
                      _ListaCarreras(
                        carreras: carreras,
                        habilitado: !_ocupado,
                        onRefrescar: () =>
                            ref.refresh(carrerasAdminProvider.future),
                        onVerFirmantes: () => _tabs.animateTo(1),
                        onDesactivar: _desactivar,
                        onReactivar: _reactivar,
                      ),
                      TablaFirmantes(
                        carreras: carreras,
                        onGuardado: _refrescar,
                        onCambiosPendientes: (hay) {
                          if (mounted && hay != _cambiosSinGuardar) {
                            setState(() => _cambiosSinGuardar = hay);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Pestaña "Carreras"
// ---------------------------------------------------------------

class _ListaCarreras extends StatelessWidget {
  final List<CarreraAdmin> carreras;
  final bool habilitado;
  final Future<void> Function() onRefrescar;
  final VoidCallback onVerFirmantes;
  final void Function(CarreraAdmin) onDesactivar;
  final void Function(CarreraAdmin) onReactivar;

  const _ListaCarreras({
    required this.carreras,
    required this.habilitado,
    required this.onRefrescar,
    required this.onVerFirmantes,
    required this.onDesactivar,
    required this.onReactivar,
  });

  @override
  Widget build(BuildContext context) {
    final sinFirmantes =
        carreras.where((c) => c.activa && c.faltanFirmantes).length;
    final pendientes =
        carreras.fold<int>(0, (s, c) => s + c.certificadosPendientes);

    return RefreshIndicator(
      onRefresh: onRefrescar,
      child: carreras.isEmpty
          ? const _Mensaje(
              icono: Icons.school_outlined,
              texto: 'No hay carreras cargadas',
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (sinFirmantes > 0) ...[
                  _Aviso(
                    texto: '${sinFirmantes == 1 ? '1 carrera activa no tiene' : '$sinFirmantes carreras activas no tienen'} '
                        'los firmantes completos (facultad, decano/a y '
                        'director/a): no pueden emitir certificados.'
                        '${pendientes > 0 ? ' Hay $pendientes certificado(s) esperando esos datos.' : ''}',
                    accion: TextButton(
                      onPressed: onVerFirmantes,
                      child: const Text('Cargar firmantes'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                for (final c in carreras)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TarjetaCarrera(
                      carrera: c,
                      habilitado: habilitado,
                      onTap: onVerFirmantes,
                      onDesactivar: () => onDesactivar(c),
                      onReactivar: () => onReactivar(c),
                    ),
                  ),
              ],
            ),
    );
  }
}

enum _AccionCarrera { firmantes, desactivar, reactivar }

class _TarjetaCarrera extends StatelessWidget {
  final CarreraAdmin carrera;
  final bool habilitado;
  final VoidCallback onTap;
  final VoidCallback onDesactivar;
  final VoidCallback onReactivar;

  const _TarjetaCarrera({
    required this.carrera,
    required this.habilitado,
    required this.onTap,
    required this.onDesactivar,
    required this.onReactivar,
  });

  @override
  Widget build(BuildContext context) {
    final c = carrera;
    final estilo = Theme.of(context).textTheme.bodyMedium;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: habilitado ? onTap : null,
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
                child: Icon(Icons.school_outlined,
                    color: c.activa
                        ? UniNorteColors.azulMarino
                        : UniNorteColors.textoSecundario),
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
                      style: estilo,
                    ),
                    Text(
                      c.decanoNombre == null
                          ? 'Sin decano/a'
                          : '${c.decanoCargo}: ${c.decanoNombre}',
                      style: estilo,
                    ),
                    Text(
                      c.directorNombre == null
                          ? 'Sin director/a'
                          : '${c.directorCargo}: ${c.directorNombre}',
                      style: estilo,
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
                        if (c.certificadosPendientes > 0)
                          _Etiqueta(
                            texto: c.certificadosPendientes == 1
                                ? '1 certificado pendiente'
                                : '${c.certificadosPendientes} certificados pendientes',
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
                    case _AccionCarrera.firmantes:
                      onTap();
                    case _AccionCarrera.desactivar:
                      onDesactivar();
                    case _AccionCarrera.reactivar:
                      onReactivar();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _AccionCarrera.firmantes,
                    child: Text('Editar en Firmantes'),
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
  final Widget? accion;
  const _Aviso({required this.texto, this.accion});

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto,
                    style:
                        const TextStyle(color: UniNorteColors.textoPrimario)),
                if (accion != null)
                  Align(alignment: Alignment.centerRight, child: accion!),
              ],
            ),
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