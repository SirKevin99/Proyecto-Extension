import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import '../carnet/carnet_provider.dart';

/// Perfil del alumno (fase 8, paso 8.1).
/// Muestra los mismos datos del carnet (C.I., nombre completo, carrera y
/// correo institucional) y reutiliza `carnetProvider`: con conexión lee del
/// servidor y actualiza los datos guardados en el teléfono; sin conexión
/// muestra los últimos guardados. El alumno no puede editar nada: las
/// correcciones las hace la administración. Admin y superadmin no tienen
/// perfil (la guardia del router solo deja entrar al alumno).
class PerfilScreen extends ConsumerWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfilAsync = ref.watch(carnetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: perfilAsync.isLoading
                ? null
                : () => ref.invalidate(carnetProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(carnetProvider);
            try {
              await ref.read(carnetProvider.future);
            } catch (_) {
              // El error se muestra en la pantalla.
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...perfilAsync.when(
                        loading: () => const [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ],
                        error: (_, _) => [
                          _Mensaje(
                            onReintentar: () => ref.invalidate(carnetProvider),
                          ),
                        ],
                        data: (r) => _contenido(context, r),
                      ),
                      const SizedBox(height: 24),
                      // Siempre visible, también si no se pudieron cargar
                      // los datos.
                      OutlinedButton.icon(
                        onPressed: () => _confirmarLogout(context, ref),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: UniNorteColors.error,
                          side: const BorderSide(
                              color: UniNorteColors.error, width: 1.5),
                        ),
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar sesión'),
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

  static final DateFormat _formato = DateFormat('dd/MM/yyyy HH:mm', 'es');

  List<Widget> _contenido(BuildContext context, CarnetResultado resultado) {
    final d = resultado.datos;

    return [
      if (resultado.sinConexion) ...[
        _Aviso(
          icono: Icons.cloud_off_outlined,
          fondo: UniNorteColors.advertencia.withValues(alpha: 0.12),
          texto: 'Sin conexión. Se muestran los datos guardados el '
              '${_formato.format(d.actualizadoEn)}.',
        ),
        const SizedBox(height: 16),
      ],
      _TarjetaDatos(datos: d),
      const SizedBox(height: 16),
      _Aviso(
        icono: Icons.info_outline,
        fondo: UniNorteColors.azulMarino.withValues(alpha: 0.06),
        texto: 'Tus datos no se pueden modificar desde la app. Si alguno es '
            'incorrecto, solicitá la corrección a la administración de '
            'extensión.',
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => context.push(AppRoutes.carnetQr),
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Ver mi carnet QR'),
      ),
    ];
  }

  void _confirmarLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro que querés salir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}

class _TarjetaDatos extends StatelessWidget {
  final DatosCarnet datos;
  const _TarjetaDatos({required this.datos});

  String get _iniciales {
    final partes = datos.nombreCompleto
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return partes.isEmpty ? '?' : partes;
  }

  @override
  Widget build(BuildContext context) {
    final d = datos;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: UniNorteColors.azulMarino,
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: UniNorteColors.dorado,
                  child: Text(
                    _iniciales,
                    style: const TextStyle(
                      color: UniNorteColors.azulMarino,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.nombreCompleto,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Alumno',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              children: [
                _Dato(icono: Icons.badge_outlined, etiqueta: 'C.I.', valor: d.ci),
                const Divider(height: 1),
                _Dato(
                  icono: Icons.person_outline,
                  etiqueta: 'Nombre completo',
                  valor: d.nombreCompleto,
                ),
                const Divider(height: 1),
                _Dato(
                  icono: Icons.school_outlined,
                  etiqueta: 'Carrera',
                  valor: d.carrera,
                ),
                const Divider(height: 1),
                _Dato(
                  icono: Icons.email_outlined,
                  etiqueta: 'Correo institucional',
                  valor: d.correo,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dato de solo lectura: etiqueta arriba y valor abajo, para que los
/// correos y las carreras largas entren en pantallas angostas.
class _Dato extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String valor;

  const _Dato({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: UniNorteColors.textoSecundario),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: UniNorteColors.textoPrimario,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final Color fondo;
  final String texto;

  const _Aviso({
    required this.icono,
    required this.fondo,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: UniNorteColors.azulMarino, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(color: UniNorteColors.textoPrimario),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sin conexión y sin datos guardados (el alumno nunca abrió el perfil ni el
/// carnet con conexión desde que inició sesión).
class _Mensaje extends StatelessWidget {
  final VoidCallback onReintentar;
  const _Mensaje({required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined,
              color: UniNorteColors.textoSecundario, size: 44),
          const SizedBox(height: 12),
          Text(
            'No se pudieron cargar tus datos. Conectate a internet una vez '
            'para guardarlos en el teléfono; después podrás verlos sin '
            'conexión.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}