import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import 'admin_usuarios_provider.dart';

class AltaUsuarioScreen extends StatefulWidget {
  const AltaUsuarioScreen({super.key});

  @override
  State<AltaUsuarioScreen> createState() => _AltaUsuarioScreenState();
}

class _AltaUsuarioScreenState extends State<AltaUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _ciController = TextEditingController();
  final _correoController = TextEditingController();
  final _carreraController = TextEditingController();
  final _passwordController = TextEditingController();

  String _rol = 'alumno';
  bool _passwordVisible = false;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _ciController.dispose();
    _correoController.dispose();
    _carreraController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _limpiar() {
    _nombreController.clear();
    _ciController.clear();
    _correoController.clear();
    _carreraController.clear();
    _passwordController.clear();
    _formKey.currentState?.reset();
    setState(() => _rol = 'alumno');
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
        carrera: _carreraController.text.trim(),
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

              TextFormField(
                controller: _carreraController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Carrera',
                  prefixIcon: Icon(Icons.school_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ingresá la carrera'
                    : null,
              ),
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