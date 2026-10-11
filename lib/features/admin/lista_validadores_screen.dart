import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../home/home_provider.dart';
import 'validadores_provider.dart';

class ListaValidadoresScreen extends ConsumerWidget {
  const ListaValidadoresScreen({super.key});

  Future<void> _deshabilitar(
      BuildContext context, WidgetRef ref, ValidadorActivo v) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deshabilitar validador'),
        content: Text(
          '${v.nombre} perderá el acceso de inmediato y se cerrará su sesión '
          'de asistencia. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: UniNorteColors.error),
            child: const Text('Deshabilitar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await desactivarValidador(v.id);
      ref.invalidate(validadoresProvider);
      ref.invalidate(metricasAdminProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Validador deshabilitado')));
      }
    } catch (e) {
      final mensaje = e is PostgrestException
          ? e.message
          : 'No se pudo deshabilitar al validador';
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensaje)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(validadoresProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Validadores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(AppRoutes.altaValidador);
          ref.invalidate(validadoresProvider);
          ref.invalidate(metricasAdminProvider);
        },
        backgroundColor: UniNorteColors.dorado,
        foregroundColor: UniNorteColors.azulMarino,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo validador'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: UniNorteColors.error, size: 48),
              const SizedBox(height: 12),
              const Text('No se pudieron cargar los validadores'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(validadoresProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        data: (lista) => RefreshIndicator(
          onRefresh: () => ref.refresh(validadoresProvider.future),
          child: lista.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 80),
                    Center(child: Text('No hay validadores activos')),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: lista.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) =>
                      _TarjetaValidador(
                        validador: lista[i],
                        onDeshabilitar: () =>
                            _deshabilitar(context, ref, lista[i]),
                      ),
                ),
        ),
      ),
    );
  }
}

class _TarjetaValidador extends StatelessWidget {
  final ValidadorActivo validador;
  final VoidCallback onDeshabilitar;

  const _TarjetaValidador({
    required this.validador,
    required this.onDeshabilitar,
  });

  @override
  Widget build(BuildContext context) {
    final fmtFecha = DateFormat('dd MMM yyyy', 'es');
    final fmtVence = DateFormat('dd/MM HH:mm');
    final v = validador;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_outlined,
                    color: UniNorteColors.exito, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    v.nombre,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.event_note_outlined,
                    size: 14, color: UniNorteColors.textoSecundario),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    v.eventoNombre == null
                        ? 'Sin evento asignado'
                        : '${v.eventoNombre} · '
                            '${v.eventoFecha == null ? '' : fmtFecha.format(v.eventoFecha!)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 14, color: UniNorteColors.textoSecundario),
                const SizedBox(width: 6),
                Text('Vence el ${fmtVence.format(v.vigenteHasta)}',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDeshabilitar,
                style: OutlinedButton.styleFrom(
                  foregroundColor: UniNorteColors.error,
                  side: const BorderSide(color: UniNorteColors.error),
                ),
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Deshabilitar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}