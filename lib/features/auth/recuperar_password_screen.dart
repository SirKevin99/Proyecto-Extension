import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';

enum _PasoRecuperacion { ingresarCi, ingresarOtp, nuevaPassword, exito }

class RecuperarPasswordScreen extends ConsumerStatefulWidget {
  const RecuperarPasswordScreen({super.key});

  @override
  ConsumerState<RecuperarPasswordScreen> createState() =>
      _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState
    extends ConsumerState<RecuperarPasswordScreen> {
  final _formKeyCi = GlobalKey<FormState>();
  final _formKeyOtp = GlobalKey<FormState>();
  final _formKeyPassword = GlobalKey<FormState>();

  final _ciController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmarPasswordController = TextEditingController();

  _PasoRecuperacion _paso = _PasoRecuperacion.ingresarCi;
  bool _cargando = false;
  String? _correoResuelto;
  bool _passwordVisible = false;

  @override
  void dispose() {
    _ciController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmarPasswordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Paso 1: resolver correo institucional desde C.I. y enviar OTP
  // ---------------------------------------------------------------
  Future<void> _solicitarOtp() async {
    if (!_formKeyCi.currentState!.validate()) return;
    setState(() => _cargando = true);

    try {
      final resultado = await supabase
          .from('usuarios')
          .select('correo_institucional')
          .eq('ci', _ciController.text.trim())
          .maybeSingle();

      if (resultado == null) {
        _mostrarError('La cédula ingresada no está registrada.');
        return;
      }

      final correo = resultado['correo_institucional'] as String;

      await supabase.auth.signInWithOtp(
        email: correo,
        shouldCreateUser: false,
      );

      setState(() {
        _correoResuelto = correo;
        _paso = _PasoRecuperacion.ingresarOtp;
      });
    } on AuthException catch (e) {
      _mostrarError(e.message);
    } catch (_) {
      _mostrarError('No se pudo enviar el código. Intentá nuevamente.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ---------------------------------------------------------------
  // Paso 2: verificar el código OTP de 6 dígitos
  // ---------------------------------------------------------------
  Future<void> _verificarOtp() async {
    if (!_formKeyOtp.currentState!.validate()) return;
    setState(() => _cargando = true);

    try {
      await supabase.auth.verifyOTP(
        email: _correoResuelto!,
        token: _otpController.text.trim(),
        type: OtpType.email,
      );

      setState(() => _paso = _PasoRecuperacion.nuevaPassword);
    } on AuthException catch (e) {
      _mostrarError('Código incorrecto o expirado.');
    } catch (_) {
      _mostrarError('No se pudo verificar el código. Intentá nuevamente.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ---------------------------------------------------------------
  // Paso 3: establecer nueva contraseña (sesión ya válida tras OTP)
  // ---------------------------------------------------------------
  Future<void> _establecerNuevaPassword() async {
    if (!_formKeyPassword.currentState!.validate()) return;
    setState(() => _cargando = true);

    try {
      await supabase.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );

      // Cerramos la sesión temporal creada por el OTP: el usuario
      // debe volver a loguearse con su C.I. y la nueva contraseña,
      // manteniendo el flujo de login único definido en el proyecto.
      await supabase.auth.signOut();

      setState(() => _paso = _PasoRecuperacion.exito);
    } on AuthException catch (e) {
      _mostrarError(e.message);
    } catch (_) {
      _mostrarError('No se pudo actualizar la contraseña.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
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
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildPaso(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaso() {
    switch (_paso) {
      case _PasoRecuperacion.ingresarCi:
        return _vistaIngresarCi();
      case _PasoRecuperacion.ingresarOtp:
        return _vistaIngresarOtp();
      case _PasoRecuperacion.nuevaPassword:
        return _vistaNuevaPassword();
      case _PasoRecuperacion.exito:
        return _vistaExito();
    }
  }

  Widget _vistaIngresarCi() {
    return Form(
      key: _formKeyCi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Recuperar contraseña',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Ingresá tu número de cédula. Te enviaremos un código a tu '
            'correo institucional.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _ciController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cédula de Identidad',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: (valor) {
              if (valor == null || valor.trim().isEmpty) {
                return 'Ingresá tu número de C.I.';
              }
              if (!RegExp(r'^\d{4,10}$').hasMatch(valor.trim())) {
                return 'C.I. inválida';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _cargando ? null : _solicitarOtp,
            child: _cargando
                ? const _BotonCargando()
                : const Text('Enviar código'),
          ),
        ],
      ),
    );
  }

  Widget _vistaIngresarOtp() {
    return Form(
      key: _formKeyOtp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Verificar código',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Ingresá el código de 6 dígitos enviado a $_correoResuelto',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '000000',
            ),
            validator: (valor) {
              if (valor == null || valor.trim().length != 6) {
                return 'El código debe tener 6 dígitos';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _cargando ? null : _verificarOtp,
            child: _cargando
                ? const _BotonCargando()
                : const Text('Verificar código'),
          ),
          TextButton(
            onPressed: _cargando
                ? null
                : () => setState(() => _paso = _PasoRecuperacion.ingresarCi),
            child: const Text('Cambiar cédula / reenviar código'),
          ),
        ],
      ),
    );
  }

  Widget _vistaNuevaPassword() {
    return Form(
      key: _formKeyPassword,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nueva contraseña',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          TextFormField(
            controller: _passwordController,
            obscureText: !_passwordVisible,
            decoration: InputDecoration(
              labelText: 'Nueva contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_passwordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
              ),
            ),
            validator: (valor) {
              if (valor == null || valor.length < 8) {
                return 'Mínimo 8 caracteres';
              }
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
            validator: (valor) {
              if (valor != _passwordController.text) {
                return 'Las contraseñas no coinciden';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _cargando ? null : _establecerNuevaPassword,
            child: _cargando
                ? const _BotonCargando()
                : const Text('Guardar contraseña'),
          ),
        ],
      ),
    );
  }

  Widget _vistaExito() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle,
            color: UniNorteColors.exito, size: 56),
        const SizedBox(height: 16),
        Text('¡Contraseña actualizada!',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Ya podés iniciar sesión con tu cédula y tu nueva contraseña.',
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

class _BotonCargando extends StatelessWidget {
  const _BotonCargando();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: UniNorteColors.azulMarino,
      ),
    );
  }
}