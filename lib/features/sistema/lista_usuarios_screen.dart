import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import 'usuarios_provider.dart';

/// Lista de usuarios del sistema (solo superadmin, fase 5).
class ListaUsuariosScreen extends ConsumerStatefulWidget {
  const ListaUsuariosScreen({super.key});

  @override
  ConsumerState<ListaUsuariosScreen> createState() =>
      _ListaUsuariosScreenState();
}

class _ListaUsuariosScreenState extends ConsumerState<ListaUsuariosScreen> {
  final _busquedaController = TextEditingController();
  Timer? _espera;
  FiltrosUsuarios _filtros = const FiltrosUsuarios();

  @override
  void dispose() {
    _espera?.cancel();
    _busquedaController.dispose();
    super.dispose();
  }

  void _alEscribir(String texto) {
    setState(() {}); // actualiza el botón de borrar
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _filtros = _filtros.copyWith(busqueda: texto));
    });
  }

  void _borrarBusqueda() {
    _espera?.cancel();
    _busquedaController.clear();
    setState(() => _filtros = _filtros.copyWith(busqueda: ''));
  }

  Future<void> _abrir(UsuarioSistema u) async {
    await context.push(AppRoutes.editarUsuarioPath(u.id));
    if (!mounted) return;
    ref.invalidate(usuariosSistemaProvider);
  }

  @override
  Widget build(BuildContext context) {
    final usuariosAsync = ref.watch(usuariosSistemaProvider(_filtros));
    final miId = supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _busquedaController,
                onChanged: _alEscribir,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o C.I.',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busquedaController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Borrar búsqueda',
                          onPressed: _borrarBusqueda,
                        ),
                ),
              ),
            ),
            _FilaFiltros(
              children: [
                _Filtro(
                  texto: 'Todos',
                  seleccionado: _filtros.rol == FiltroRolUsuario.todos,
                  onTap: () => setState(() =>
                      _filtros = _filtros.copyWith(rol: FiltroRolUsuario.todos)),
                ),
                _Filtro(
                  texto: 'Alumnos',
                  seleccionado: _filtros.rol == FiltroRolUsuario.alumno,
                  onTap: () => setState(() => _filtros =
                      _filtros.copyWith(rol: FiltroRolUsuario.alumno)),
                ),
                _Filtro(
                  texto: 'Administradores',
                  seleccionado: _filtros.rol == FiltroRolUsuario.admin,
                  onTap: () => setState(() =>
                      _filtros = _filtros.copyWith(rol: FiltroRolUsuario.admin)),
                ),
              ],
            ),
            _FilaFiltros(
              children: [
                _Filtro(
                  texto: 'Cualquier estado',
                  seleccionado: _filtros.estado == FiltroEstadoUsuario.todos,
                  onTap: () => setState(() => _filtros =
                      _filtros.copyWith(estado: FiltroEstadoUsuario.todos)),
                ),
                _Filtro(
                  texto: 'Activos',
                  seleccionado: _filtros.estado == FiltroEstadoUsuario.activos,
                  onTap: () => setState(() => _filtros =
                      _filtros.copyWith(estado: FiltroEstadoUsuario.activos)),
                ),
                _Filtro(
                  texto: 'Inactivos',
                  seleccionado:
                      _filtros.estado == FiltroEstadoUsuario.inactivos,
                  onTap: () => setState(() => _filtros =
                      _filtros.copyWith(estado: FiltroEstadoUsuario.inactivos)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(usuariosSistemaProvider(_filtros).future),
                child: usuariosAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _Mensaje(
                    icono: Icons.error_outline,
                    texto: 'No se pudo cargar la lista de usuarios',
                    accion: OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(usuariosSistemaProvider(_filtros)),
                      child: const Text('Reintentar'),
                    ),
                  ),
                  data: (usuarios) {
                    if (usuarios.isEmpty) {
                      return const _Mensaje(
                        icono: Icons.person_search_outlined,
                        texto: 'No hay usuarios con esos filtros',
                      );
                    }
                    final hayMas = usuarios.length >= limiteUsuarios;
                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: usuarios.length + (hayMas ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == usuarios.length) {
                          return Text(
                            'Se muestran los primeros $limiteUsuarios. '
                            'Afiná la búsqueda para ver otros.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          );
                        }
                        final u = usuarios[i];
                        final esPropio = u.id == miId;
                        return _TarjetaUsuario(
                          usuario: u,
                          esPropio: esPropio,
                          onTap: u.esEditable && !esPropio
                              ? () => _abrir(u)
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaFiltros extends StatelessWidget {
  final List<Widget> children;
  const _FilaFiltros({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          for (final c in children)
            Padding(padding: const EdgeInsets.only(right: 8), child: c),
        ],
      ),
    );
  }
}

class _Filtro extends StatelessWidget {
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _Filtro({
    required this.texto,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(texto),
      selected: seleccionado,
      selectedColor: UniNorteColors.dorado,
      backgroundColor: Colors.white,
      onSelected: (_) => onTap(),
    );
  }
}

class _TarjetaUsuario extends StatelessWidget {
  final UsuarioSistema usuario;
  final bool esPropio;
  final VoidCallback? onTap;

  const _TarjetaUsuario({
    required this.usuario,
    required this.esPropio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final u = usuario;
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
                  color: (u.activo
                          ? UniNorteColors.dorado
                          : UniNorteColors.textoSecundario)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  u.rol == 'alumno'
                      ? Icons.school_outlined
                      : Icons.admin_panel_settings_outlined,
                  color: u.activo
                      ? UniNorteColors.azulMarino
                      : UniNorteColors.textoSecundario,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.nombreCompleto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: UniNorteColors.textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'C.I. ${u.ci} · ${u.carrera}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Etiqueta(
                          texto: u.rolLegible,
                          color: UniNorteColors.azulMarino,
                        ),
                        if (!u.activo)
                          const _Etiqueta(
                            texto: 'Inactivo',
                            color: UniNorteColors.error,
                          ),
                        if (esPropio)
                          const _Etiqueta(
                            texto: 'Tu cuenta',
                            color: UniNorteColors.exito,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right,
                    color: UniNorteColors.textoSecundario),
            ],
          ),
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color color;

  const _Etiqueta({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
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