import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import 'auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ciController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _passwordVisible = false;

  @override
  void dispose() {
    _ciController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

   ref.read(authProvider.notifier).login(
  identificador: _ciController.text.trim(), // Reemplazado 'ci:' por 'identificador:'
  password: _passwordController.text,
);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final cargando = authState.status == AuthStatus.cargando;

    // Mostrar error en Snackbar cuando cambia el estado a error.
    ref.listen<AuthState>(authProvider, (previo, actual) {
      if (actual.status == AuthStatus.error && actual.mensajeError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(actual.mensajeError!),
            backgroundColor: UniNorteColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: UniNorteColors.azulMarino,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  _LogoInstitucional(),
                  const SizedBox(height: 8),
                  const Text(
                    'UniNorte Extensiones',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gestión de horas de extensión académica',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 40),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Iniciar sesión',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 20),

                            TextFormField(
                              controller: _ciController,
                              keyboardType: TextInputType.text,
                              textCapitalization: TextCapitalization.characters,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: const InputDecoration(
                              labelText: 'C.I. o código de validador',
                              prefixIcon: Icon(Icons.badge_outlined),
                              hintText: 'Ej: 4567890 o VAL-4821',
                              ),
                              validator: (valor) {
                              final v = valor?.trim().toUpperCase() ?? '';
                              if (v.isEmpty) return 'Ingresá tu C.I. o tu código de validador';
                              if (!RegExp(r'^(\d{4,10}|VAL-\d{4})$').hasMatch(v)) {
                              return 'Usá tu C.I. (solo números) o el código VAL-0000';
                              }
                              return null;
                              },
                              ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _passwordController,
                              obscureText: !_passwordVisible,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _passwordVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(() {
                                    _passwordVisible = !_passwordVisible;
                                  }),
                                ),
                              ),
                              validator: (valor) {
                                if (valor == null || valor.isEmpty) {
                                  return 'Ingresá tu contraseña';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),

                            Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push(AppRoutes.recuperarPassword),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              const SizedBox(height: 12),

              ElevatedButton(
                onPressed: cargando ? null : _submit,
                child: cargando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: UniNorteColors.azulMarino,
                        ),
                      )
                    : const Text('Ingresar'),
              ),
              const SizedBox(height: 8),

             
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoInstitucional extends StatelessWidget {
  const _LogoInstitucional();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      margin: const EdgeInsets.symmetric(horizontal: 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: UniNorteColors.dorado,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.school,
        color: UniNorteColors.azulMarino,
        size: 44,
      ),
    );
  }
}