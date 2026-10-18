import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../shared/carreras_provider.dart';
import 'admin_usuarios_provider.dart';

class AltaUsuarioScreen extends ConsumerStatefulWidget {
  const AltaUsuarioScreen({super.key});

  @override
  ConsumerState<AltaUsuarioScreen> createState() => _AltaUsuarioScreenState();
}

class _AltaUsuarioScreenState extends ConsumerState<AltaUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _ciController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();

  String _rol = 'alumno';
  String? _carrera; // nombre completo de la lista oficial
  bool _passwordVisible = false;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _ciController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _limpiar() {
    _nombreController.clear();
    _ciController.clear();
    _correoController.clear();
    _passwordController.clear();
    setState(() {
      _rol = 'alumno';
      _carrera = null;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final nombre = _nombreController.text.trim();
    setState(() => _guardando = true);

    try {
      await AdminUsuariosService.crearUsuario(
        rol: _rol,
        nombreCompleto: nombre,
        ci: _ciController.text.trim(),
        correoLocal: _correoController.text.trim(),
        carrera: _carrera!,
        password: _passwordController.text,
      );
      if (!mounted) return;
      _limpiar();
      messenger.showSnackBar(SnackBar(
        content: Text('Usuario creado: $nombre'),
        backgroundColor: UniNorteColors.exito,
        behavior: SnackBarBehavior.floating,
      ));
    } on AltaException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.mensaje),
        backgroundColor: UniNorteColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
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
      data: (carreras) => DropdownButtonFormField<String>(
        value: _carrera,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Carrera',
          prefixIcon: Icon(Icons.school_outlined),
        ),
        items: [
          for (final c in carreras)
            DropdownMenuItem(
              value: c.nombre,
              child: Text(c.nombre, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _carrera = v),
        validator: (v) => v == null ? 'Seleccioná la carrera' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alta de usuario')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Tipo de usuario',
                  style: Theme.of(context).textTheme.bodyMedium),
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
                      onSelected: (_) => setState(() => _rol = r),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nombreController,
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
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cédula de Identidad',
                  prefixIcon: Icon(Icons.badge_outlined),
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

              TextFormField(
                controller: _correoController,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Usuario institucional',
                  prefixIcon: const Icon(Icons.email_outlined),
                  suffixText: SupabaseConfig.dominioInstitucional,
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Ingresá el usuario';
                  if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(t)) {
                    return 'Solo letras, números, punto o guion';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _campoCarrera(),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                obscureText: !_passwordVisible,
                decoration: InputDecoration(
                  labelText: 'Contraseña inicial',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _passwordVisible = !_passwordVisible),
                  ),
                ),
                validator: (v) => (v == null || v.length < 8)
                    ? 'Mínimo 8 caracteres'
                    : null,
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
                    : const Text('Crear usuario'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}