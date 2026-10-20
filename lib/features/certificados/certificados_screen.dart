import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/theme.dart';
import 'certificado_pdf.dart';
import 'certificados_provider.dart';

/// Certificados del alumno (fase 7, paso 7.3c).
/// - Disponibles: se abren en una vista previa para compartir, guardar o
///   imprimir. El PDF se genera en el teléfono y no se guarda en Supabase.
/// - Pendientes: el evento terminó, pero la carrera todavía no tiene
///   cargados sus firmantes.
class CertificadosScreen extends ConsumerWidget {
  const CertificadosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(misCertificadosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis certificados')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(misCertificadosProvider.future),
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Mensaje(
              icono: Icons.cloud_off_outlined,
              texto: e is CertificadosException
                  ? e.mensaje
                  : 'No se pudieron cargar tus certificados',
              accion: OutlinedButton(
                onPressed: () => ref.invalidate(misCertificadosProvider),
                child: const Text('Reintentar'),
              ),
            ),
            data: (lista) => _Contenido(certificados: lista),
          ),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  final List<Certificado> certificados;
  const _Contenido({required this.certificados});

  void _abrir(BuildContext context, Certificado c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _VistaPreviaCertificado(certificado: c),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (certificados.isEmpty) {
      return const _Mensaje(
        icono: Icons.workspace_premium_outlined,
        texto: 'Todavía no tenés certificados.\n'
            'Aparecen cuando finaliza un evento en el que registraste '
            'tu entrada y tu salida.',
      );
    }

    final disponibles = certificados.where((c) => c.disponible).toList();
    final pendientes = certificados.where((c) => !c.disponible).toList();
    final titulo = Theme.of(context).textTheme.titleLarge;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (disponibles.isNotEmpty) ...[
          Text('Disponibles', style: titulo),
          const SizedBox(height: 10),
          for (final c in disponibles) ...[
            _TarjetaCertificado(certificado: c, onTap: () => _abrir(context, c)),
            const SizedBox(height: 10),
          ],
        ],
        if (pendientes.isNotEmpty) ...[
          if (disponibles.isNotEmpty) const SizedBox(height: 14),
          Text('Pendientes', style: titulo),
          const SizedBox(height: 4),
          Text(
            'El evento ya finalizó, pero faltan cargar los datos de los '
            'firmantes de tu carrera. El certificado aparecerá acá en '
            'cuanto estén.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          for (final c in pendientes) ...[
            _TarjetaCertificado(certificado: c, onTap: null),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _TarjetaCertificado extends StatelessWidget {
  final Certificado certificado;
  final VoidCallback? onTap;

  const _TarjetaCertificado({required this.certificado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = certificado;
    final fecha = DateFormat('dd MMM yyyy', 'es').format(c.fecha);
    final color =
        c.disponible ? UniNorteColors.azulMarino : UniNorteColors.textoSecundario;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (c.disponible
                          ? UniNorteColors.dorado
                          : UniNorteColors.textoSecundario)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  c.disponible
                      ? Icons.workspace_premium_outlined
                      : Icons.hourglass_top_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.evento,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: UniNorteColors.textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$fecha · ${c.horas == 1 ? '1 hora' : '${c.horas} horas'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (!c.disponible)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Pendiente: faltan los firmantes de tu carrera',
                          style: TextStyle(
                            color: UniNorteColors.textoSecundario,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (c.disponible)
                const Icon(Icons.chevron_right,
                    color: UniNorteColors.textoSecundario),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vista previa del PDF con los botones de compartir (o guardar) e
/// imprimir del paquete `printing`.
class _VistaPreviaCertificado extends StatelessWidget {
  final Certificado certificado;
  const _VistaPreviaCertificado({required this.certificado});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Certificado')),
      body: PdfPreview(
        build: (_) => CertificadoPdf.generar(certificado),
        pdfFileName: certificado.nombreArchivo,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        loadingWidget: const Center(child: CircularProgressIndicator()),
        onError: (context, error) => const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No se pudo generar el certificado. Intentá de nuevo.',
            textAlign: TextAlign.center,
          ),
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