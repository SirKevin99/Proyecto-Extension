import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';

/// Registro de autogestión: exclusivo para alumnos.
///
/// La creación de cuentas de docente/admin NO pasa por esta pantalla
/// pública — se hace desde el panel de administración (módulo Admin,
/// fuera del alcance de este prototipo), asignando el rol manualmente.
/// Esto evita que cualquier usuario pueda autoasignarse rol docente.
class RegistroScreen extends ConsumerStatefulWidget {
  const RegistroScreen({super.key});

  @override
  ConsumerState<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends ConsumerState<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _ciController = TextEditingController();
  final _correoLocalController = TextEditingController();
  final _carreraController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmarPasswordController = TextEditingController();

  bool _cargando = false;
  bool _passwordVisible = false;
  bool _registroExitoso = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _ciController.dispose();
    _correoLocalController.dispose();
    _carreraController.dispose();
    _passwordController.dispose();
    _confirmarPasswordController.dispose();
    super.dispose();
  }

  String get _correoCompleto =>
      '${_correoLocalController.text.trim()}${SupabaseConfig.dominioInstitucional}';

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);

    try {
      // 1. Verificar unicidad de C.I. antes de crear el usuario en Auth,
      //    para no dejar cuentas huérfanas en auth.users si la C.I. ya
      //    existe en la tabla `usuarios` (constraint UNIQUE).
      final ciExistente = await supabase
          .from('usuarios')
          .select('id')
          .eq('ci', _ciController.text.trim())
          .maybeSingle();

      if (ciExistente != null) {
        _mostrarError('Ya existe una cuenta registrada con esa cédula.');
        return;
      }

      // 2. Crear usuario en Supabase Auth con el correo institucional
      //    compuesto (dominio fijo, no editable por el usuario).
      final authResponse = await supabase.auth.signUp(
        email: _correoCompleto,
        password: _passwordController.text,
      );

      final userId = authResponse.user?.id;
      if (userId == null) {
        _mostrarError('No se pudo crear la cuenta. Intentá nuevamente.');
        return;
      }

      // 3. Insertar el perfil en la tabla `usuarios`, con rol fijo
      //    'alumno' — la única asignación permitida desde autogestión.
      //    RLS debe garantizar que un usuario solo pueda insertar su
      //    propia fila (id = auth.uid()) y no pueda escribir `rol`
      //    con un valor distinto de 'alumno' vía policy/CHECK.
      await supabase.from('usuarios').insert({
        'id': userId,
        'nombre_completo': _nombreController.text.trim(),
        'ci': _ciController.text.trim(),
        'correo_institucional': _correoCompleto,
        'carrera': _carreraController.text.trim(),
        'rol': 'alumno',
      });

      setState(() => _registroExitoso = true);
    } on AuthException catch (e) {
      _mostrarError(_mensajeAuthLegible(e.message));
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        _mostrarError('Ya existe una cuenta con esa cédula o correo.');
      } else {
        _mostrarError('No se pudo completar el registro.');
      }
    } catch (_) {
      _mostrarError('Ocurrió un error inesperado. Intentá nuevamente.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _mensajeAuthLegible(String mensajeOriginal) {
    if (mensajeOriginal.toLowerCase().contains('already registered')) {
      return 'Ese correo institucional ya está registrado.';
    }
    return mensajeOriginal;
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: UniNorteColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UniNorteColors.azulMarino,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(
          color: Colors.white,
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child:
                      _registroExitoso ? _vistaExito() : _vistaFormulario(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _vistaFormulario() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Crear cuenta de alumno',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'El registro es exclusivo para alumnos. Docentes y '
            'administradores son habilitados por la universidad.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),

          TextFormField(
            controller: _nombreController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v == null || v.trim().length < 3)
                ? 'Ingresá tu nombre completo'
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
              if (v == null || v.trim().isEmpty) return 'Ingresá tu C.I.';
              if (!RegExp(r'^\d{4,10}$').hasMatch(v.trim())) {
                return 'C.I. inválida';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Correo institucional: solo se edita la parte local; el
          // dominio institucional es fijo y no editable, garantizando
          // la validación de dominio pedida por el proyecto.
          TextFormField(
            controller: _correoLocalController,
            keyboardType: TextInputType.text,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Usuario institucional',
              prefixIcon: const Icon(Icons.email_outlined),
              suffixText: SupabaseConfig.dominioInstitucional,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Ingresá tu usuario institucional';
              }
              if (RegExp(r'[^a-zA-Z0-9._-]').hasMatch(v.trim())) {
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
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Ingresá tu carrera' : null,
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _passwordController,
            obscureText: !_passwordVisible,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_passwordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
              ),
            ),
            validator: (v) {
              if (v == null || v.length < 8) return 'Mínimo 8 caracteres';
              return null;
            },
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _confirmarPasswordController,
            obscureText: !_passwordVisible,
            decoration: const InputDecoration(
              labelText: 'Confirmar contraseña',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (v) {
              if (v != _passwordController.text) {
                return 'Las contraseñas no coinciden';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _cargando ? null : _registrar,
            child: _cargando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: UniNorteColors.azulMarino,
                    ),
                  )
                : const Text('Registrarme'),
          ),
        ],
      ),
    );
  }

  Widget _vistaExito() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: UniNorteColors.exito, size: 56),
        const SizedBox(height: 16),
        Text('¡Cuenta creada!', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Revisá tu correo institucional ($_correoCompleto) para '
          'confirmar tu cuenta antes de iniciar sesión.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => context.pop(),
          child: const Text('Volver al login'),
        ),
      ],
    );
  }
}