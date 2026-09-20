import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import 'home_provider.dart';

class HomeEstudianteScreen extends ConsumerWidget {
  const HomeEstudianteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progresoAsync = ref.watch(progresoEstudianteProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi progreso'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Mi carnet QR',
            onPressed: () => context.push(AppRoutes.carnetQr),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => _confirmarLogout(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(progresoEstudianteProvider.future),
        child: progresoAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _vistaError(context, ref),
          data: (progreso) => _vistaContenido(context, progreso),
        ),
      ),
      bottomNavigationBar: _BarraNavegacionEstudiante(indiceActual: 0),
    );
  }

  Widget _vistaError(BuildContext context, WidgetRef ref) {
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
                  const Icon(Icons.error_outline,
                      color: UniNorteColors.error, size: 48),
                  const SizedBox(height: 12),
                  const Text('No se pudo cargar tu progreso'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(progresoEstudianteProvider),
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

  Widget _vistaContenido(BuildContext context, ProgresoEstudiante progreso) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Hola, ${progreso.nombreCompleto.split(' ').first} 👋',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(progreso.carrera,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),

        _TarjetaProgreso(progreso: progreso),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: _TarjetaMetrica(
                icono: Icons.event_available_outlined,
                valor: '${progreso.eventosInscriptos}',
                etiqueta: 'Inscripciones',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TarjetaMetrica(
                icono: Icons.hourglass_top_outlined,
                valor: '${progreso.eventosPendientesAsistencia}',
                etiqueta: 'Pend. validación',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Text('Accesos rápidos',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _AccesoRapido(
          icono: Icons.explore_outlined,
          titulo: 'Explorar eventos',
          subtitulo: 'Inscribite a nuevas extensiones',
          onTap: () => context.push(AppRoutes.listaEventos),
        ),
        const SizedBox(height: 10),
        _AccesoRapido(
          icono: Icons.workspace_premium_outlined,
          titulo: 'Mis certificados',
          subtitulo: 'Descargá y verificá tus certificados',
          onTap: () => context.push(AppRoutes.certificados),
        ),
        const SizedBox(height: 10),
        _AccesoRapido(
          icono: Icons.qr_code_2,
          titulo: 'Mi carnet QR',
          subtitulo: 'Presentalo para el Check-In',
          onTap: () => context.push(AppRoutes.carnetQr),
        ),
      ],
    );
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

class _TarjetaProgreso extends StatelessWidget {
  final ProgresoEstudiante progreso;
  const _TarjetaProgreso({required this.progreso});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: UniNorteColors.azulMarino,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Horas de extensión',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: UniNorteColors.dorado,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(progreso.porcentaje * 100).round()}%',
                  style: const TextStyle(
                    color: UniNorteColors.azulMarino,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${progreso.horasCompletadas}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                ' / ${progreso.horasRequeridas} hrs',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progreso.porcentaje,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(UniNorteColors.dorado),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            progreso.horasFaltantes == 0
                ? '¡Completaste tus horas requeridas!'
                : 'Te faltan ${progreso.horasFaltantes} horas',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaMetrica extends StatelessWidget {
  final IconData icono;
  final String valor;
  final String etiqueta;

  const _TarjetaMetrica({
    required this.icono,
    required this.valor,
    required this.etiqueta,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Column(
          children: [
            Icon(icono, color: UniNorteColors.azulMarino, size: 26),
            const SizedBox(height: 8),
            Text(valor,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              etiqueta,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccesoRapido extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _AccesoRapido({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                  color: UniNorteColors.dorado.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: UniNorteColors.azulMarino),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(subtitulo,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: UniNorteColors.textoSecundario),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarraNavegacionEstudiante extends StatelessWidget {
  final int indiceActual;
  const _BarraNavegacionEstudiante({required this.indiceActual});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: indiceActual,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            break; // ya estamos en home
          case 1:
            context.push(AppRoutes.listaEventos);
            break;
          case 2:
            context.push(AppRoutes.certificados);
            break;
          case 3:
            context.push(AppRoutes.perfil);
            break;
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
        NavigationDestination(
            icon: Icon(Icons.explore_outlined), label: 'Eventos'),
        NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            label: 'Certificados'),
        NavigationDestination(
            icon: Icon(Icons.person_outline), label: 'Perfil'),
      ],
    );
  }
}