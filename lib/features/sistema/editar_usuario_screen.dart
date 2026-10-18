import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shared/carreras_provider.dart';
import 'usuarios_provider.dart';

/// Edición, desactivación y reactivación de un usuario (solo superadmin).
/// El correo no se edita (decisión del 18/10).
class EditarUsuarioScreen extends ConsumerStatefulWidget {
  final String usuarioId;
  const EditarUsuarioScreen({super.key, required this.usuarioId});

  @override
  ConsumerState<EditarUsuarioScreen> createState() =>
      _EditarUsuarioScreenState();
}

class _EditarUsuarioScreenState extends ConsumerState<EditarUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _ciController = TextEditingController();
  final _horasController = TextEditingController();

  UsuarioSistema? _usuario;
  String? _errorCarga;
  bool _cargando = true;
  bool _guardando = false;

  String _rol = 'alumno';
  String? _carrera;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _ciController.dispose();
    _horasController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final u = await GestionUsuariosService.obtener(widget.usuarioId);
      if (!mounted) return;
      _nombreController.text = u.nombreCompleto;
      _ciController.text = u.ci;
      _horasController.text = '${u.horasRequeridas}';
      setState(() {
        _usuario = u;
        _rol = u.rol == 'admin' ? 'admin' : 'alumno';
        _carrera = u.carrera;
        _errorCarga = null;
        _cargando = false;
      });
    } on GestionUsuarioException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCarga = e.mensaje;
        _cargando = false;
      });
    }
  }

  void _reintentar() {
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });
    _cargar();
  }

  Future<bool> _confirmar({
    required String titulo,
    required String mensaje,
    required String accion,
    bool peligro = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: peligro
                ? TextButton.styleFrom(foregroundColor: UniNorteColors.error)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(accion),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _mostrar(ScaffoldMessengerState messenger, String texto,
      {bool error = false}) {
    messenger.showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? UniNorteColors.error : UniNorteColors.exito,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final u = _usuario!;
    final ciNueva = _ciController.text.trim();

    final avisos = <String>[
      if (ciNueva != u.ci)
        'La C.I. cambia: el usuario deberá iniciar sesión con la nueva '
            '($ciNueva). Avisale antes.',
      if (_rol != u.rol)
        _rol == 'admin'
            ? 'El usuario pasará a ser administrador.'
            : 'El usuario dejará de ser administrador y pasará a ser alumno.',
    ];
    if (avisos.isNotEmpty) {
      final ok = await _confirmar(
        titulo: 'Confirmar cambios',
        mensaje: avisos.join('\n\n'),
        accion: 'Guardar',
      );
      if (!ok || !mounted) return;
    }

    setState(() => _guardando = true);
    try {
      await GestionUsuariosService.editar(
        id: u.id,
        nombreCompleto: _nombreController.text.trim(),
        ci: ciNueva,
        carrera: _carrera!,
        horasRequeridas: int.parse(_horasController.text.trim()),
        rol: _rol,
      );
      if (!mounted) return;
      _mostrar(messenger, 'Cambios guardados');
      context.pop();
    } on GestionUsuarioException catch (e) {
      _mostrar(messenger, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cambiarEstado() async {
    final messenger = ScaffoldMessenger.of(context);
    final u = _usuario!;
    final desactivar = u.activo;

    final ok = await _confirmar(
      titulo: desactivar ? 'Desactivar usuario' : 'Reactivar usuario',
      mensaje: desactivar
          ? '${u.nombreCompleto} no podrá iniciar sesión. Su historial se '
              'conserva. Si ya tiene la app abierta, su sesión puede seguir '
              'activa hasta 1 hora.'
          : '${u.nombreCompleto} podrá volver a iniciar sesión con su C.I. '
              'y su contraseña.',
      accion: desactivar ? 'Desactivar' : 'Reactivar',
      peligro: desactivar,
    );
    if (!ok || !mounted) return;

    setState(() => _guardando = true);
    try {
      if (desactivar) {
        await GestionUsuariosService.desactivar(u.id);
      } else {
        await GestionUsuariosService.reactivar(u.id);
      }
      if (!mounted) return;
      _mostrar(messenger,
          desactivar ? 'Usuario desactivado' : 'Usuario reactivado');
      await _cargar();
    } on GestionUsuarioException catch (e) {
      _mostrar(messenger, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar usuario')),
      body: SafeArea(child: _cuerpo()),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorCarga != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: UniNorteColors.error, size: 48),
              const SizedBox(height: 12),
              Text(_errorCarga!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _reintentar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final u = _usuario!;
    if (!u.esEditable) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Esta cuenta no se gestiona desde aquí.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Encabezado(usuario: u),
          const SizedBox(height: 20),

          Text('Rol', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final r in const ['alumno', 'admin'])
                ChoiceChip(
                  label: Text(r == 'alumno' ? 'Alumno' : 'Administrador'),
                  selected: _rol == r,
                  selectedColor: UniNorteColors.dorado,
                  backgroundColor: Colors.white,
                  onSelected: _guardando
                      ? null
                      : (_) => setState(() => _rol = r),
                ),
            ],
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _nombreController,
            enabled: !_guardando,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v == null || v.trim().length < 3)
                ? 'Ingresá el nombre completo'
                : null,
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _ciController,
            enabled: !_guardando,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Cédula de Identidad',
              prefixIcon: Icon(Icons.badge_outlined),
              helperText: 'Es el dato con el que inicia sesión',
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return 'Ingresá la C.I.';
              if (!RegExp(r'^\d{4,10}$').hasMatch(t)) {
                return 'Entre 4 y 10 dígitos';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          _campoCarrera(),
          const SizedBox(height: 16),

          TextFormField(
            controller: _horasController,
            enabled: !_guardando,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Horas requeridas',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            validator: (v) {
              final n = int.tryParse(v?.trim() ?? '');
              if (n == null || n < 1 || n > 500) {
                return 'Entre 1 y 500 horas';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: UniNorteColors.azulMarino,
                    ),
                  )
                : const Text('Guardar cambios'),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('Estado de la cuenta',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            u.activo
                ? 'La cuenta está activa. Al desactivarla, el usuario no podrá '
                    'iniciar sesión; su historial se conserva.'
                : 'La cuenta está desactivada: el usuario no puede iniciar sesión.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (u.activo)
            OutlinedButton.icon(
              onPressed: _guardando ? null : _cambiarEstado,
              style: OutlinedButton.styleFrom(
                foregroundColor: UniNorteColors.error,
                side: const BorderSide(color: UniNorteColors.error, width: 1.5),
              ),
              icon: const Icon(Icons.block),
              label: const Text('Desactivar usuario'),
            )
          else
            OutlinedButton.icon(
              onPressed: _guardando ? null : _cambiarEstado,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reactivar usuario'),
            ),
        ],
      ),
    );
  }

  Widget _campoCarrera() {
    final carrerasAsync = ref.watch(carrerasProvider);

    return carrerasAsync.when(
      loading: () => const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Carrera',
          prefixIcon: Icon(Icons.school_outlined),
        ),
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Carrera',
          prefixIcon: Icon(Icons.school_outlined),
          errorText: 'No se pudo cargar la lista de carreras',
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => ref.invalidate(carrerasProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ),
      data: (carreras) {
        // Si la carrera actual no está en la lista oficial, se obliga a
        // elegir una (el servidor también lo exige).
        final enLista = carreras.any((c) => c.nombre == _carrera);
        final original = _usuario!.carrera;
        return DropdownButtonFormField<String>(
          initialValue: enLista ? _carrera : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Carrera',
            prefixIcon: const Icon(Icons.school_outlined),
            helperText: carreras.any((c) => c.nombre == original)
                ? null
                : 'La carrera actual ("$original") no está en la lista '
                    'oficial: elegí una',
            helperMaxLines: 2,
          ),
          items: [
            for (final c in carreras)
              DropdownMenuItem(
                value: c.nombre,
                child: Text(c.nombre, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _guardando ? null : (v) => setState(() => _carrera = v),
          validator: (v) => v == null ? 'Seleccioná la carrera' : null,
        );
      },
    );
  }
}

class _Encabezado extends StatelessWidget {
  final UsuarioSistema usuario;
  const _Encabezado({required this.usuario});

  @override
  Widget build(BuildContext context) {
    final u = usuario;
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
                    u.nombreCompleto,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (u.activo
                            ? UniNorteColors.exito
                            : UniNorteColors.error)
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    u.activo ? 'Activo' : 'Inactivo',
                    style: TextStyle(
                      color:
                          u.activo ? UniNorteColors.exito : UniNorteColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.email_outlined,
                    size: 16, color: UniNorteColors.textoSecundario),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    u.correo,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'El correo no se puede modificar.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}