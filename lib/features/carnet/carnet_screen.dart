import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import 'carnet_provider.dart';

/// Carnet QR del alumno (fase 7, paso 7.2).
/// Muestra C.I., nombre, carrera y correo institucional, y un QR con esos
/// mismos datos en texto. Solo identifica al alumno: no marca asistencia.
/// Sin conexión, muestra los últimos datos guardados en el teléfono.
class CarnetScreen extends ConsumerWidget {
  const CarnetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carnetAsync = ref.watch(carnetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi carnet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: carnetAsync.isLoading
                ? null
                : () => ref.invalidate(carnetProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(carnetProvider.future),
          child: carnetAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Mensaje(
              texto: e is CarnetException
                  ? e.mensaje
                  : 'No se pudo cargar tu carnet',
              onReintentar: () => ref.invalidate(carnetProvider),
            ),
            data: (r) => _Contenido(resultado: r),
          ),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  final CarnetResultado resultado;
  const _Contenido({required this.resultado});

  static final DateFormat _formato = DateFormat('dd/MM/yyyy HH:mm', 'es');

  @override
  Widget build(BuildContext context) {
    final d = resultado.datos;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        if (resultado.sinConexion) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: UniNorteColors.advertencia.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    color: UniNorteColors.azulMarino, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sin conexión. Se muestran los datos guardados el '
                    '${_formato.format(d.actualizadoEn)}.',
                    style:
                        const TextStyle(color: UniNorteColors.textoPrimario),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _Tarjeta(datos: d),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Este carnet solo te identifica como alumno. No sirve para marcar '
          'asistencia: para eso usá el QR o el PIN del evento.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final DatosCarnet datos;
  const _Tarjeta({required this.datos});

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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: UniNorteColors.dorado,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.school_outlined,
                      color: UniNorteColors.azulMarino),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'UniNorte',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Carnet de alumno',
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              d.nombreCompleto.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: UniNorteColors.textoPrimario,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _Dato(icono: Icons.badge_outlined, etiqueta: 'C.I.', valor: d.ci),
                _Dato(
                    icono: Icons.school_outlined,
                    etiqueta: 'Carrera',
                    valor: d.carrera),
                _Dato(
                    icono: Icons.email_outlined,
                    etiqueta: 'Correo',
                    valor: d.correo),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Fondo blanco y margen ("zona tranquila") para que cualquier
          // lector lo tome bien.
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: d.textoQr,
                version: QrVersions.auto,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                size: 240,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: UniNorteColors.azulMarino,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: UniNorteColors.azulMarino,
                ),
                semanticsLabel: 'Código QR del carnet',
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: UniNorteColors.textoSecundario),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              etiqueta,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: UniNorteColors.textoPrimario,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mensaje de error centrado que permite "tirar para actualizar".
class _Mensaje extends StatelessWidget {
  final String texto;
  final VoidCallback onReintentar;

  const _Mensaje({required this.texto, required this.onReintentar});

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
                  const Icon(Icons.cloud_off_outlined,
                      color: UniNorteColors.textoSecundario, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    texto,
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
            ),
          ),
        ),
      ),
    );
  }
}