import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'auditoria_provider.dart';

/// Auditoría general del sistema (solo superadmin, fase 5).
/// Muestra quién cambió qué y cuándo, de lo más reciente a lo más antiguo.
class AuditoriaScreen extends StatefulWidget {
  const AuditoriaScreen({super.key});

  @override
  State<AuditoriaScreen> createState() => _AuditoriaScreenState();
}

class _AuditoriaScreenState extends State<AuditoriaScreen> {
  static final DateFormat _formatoDia = DateFormat('dd/MM/yyyy', 'es');

  List<RegistroAuditoria> _registros = [];
  bool _cargando = true;
  bool _cargandoMas = false;
  bool _hayMas = false;
  String? _error;

  OrigenAuditoria _origen = OrigenAuditoria.todos;
  DateTimeRange? _rango;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Primera página con los filtros actuales.
  Future<void> _cargar() async {
    try {
      final r = await AuditoriaService.listar(
        origen: _origen,
        desde: _rango?.start,
        hasta: _rango?.end,
      );
      if (!mounted) return;
      setState(() {
        _registros = r;
        _hayMas = r.length == AuditoriaService.tamanoPagina;
        _error = null;
        _cargando = false;
      });
    } on AuditoriaException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    }
  }

  void _recargar() {
    setState(() {
      _cargando = true;
      _error = null;
    });
    _cargar();
  }

  Future<void> _cargarMas() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _cargandoMas = true);
    try {
      final r = await AuditoriaService.listar(
        origen: _origen,
        desde: _rango?.start,
        hasta: _rango?.end,
        offset: _registros.length,
      );
      if (!mounted) return;
      setState(() {
        _registros = [..._registros, ...r];
        _hayMas = r.length == AuditoriaService.tamanoPagina;
      });
    } on AuditoriaException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.mensaje),
        backgroundColor: UniNorteColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(ahora.year, ahora.month, ahora.day),
      initialDateRange: _rango,
      helpText: 'Rango de fechas',
      saveText: 'Aplicar',
    );
    if (rango == null || !mounted) return;
    _rango = rango;
    _recargar();
  }

  void _quitarRango() {
    _rango = null;
    _recargar();
  }

  void _cambiarOrigen(OrigenAuditoria o) {
    if (o == _origen) return;
    _origen = o;
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auditoría')),
      body: SafeArea(
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  for (final o in OrigenAuditoria.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(o.etiqueta),
                        selected: _origen == o,
                        selectedColor: UniNorteColors.dorado,
                        backgroundColor: Colors.white,
                        onSelected: (_) => _cambiarOrigen(o),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _elegirRango,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                      ),
                      icon: const Icon(Icons.date_range, size: 20),
                      label: Text(
                        _rango == null
                            ? 'Todas las fechas'
                            : '${_formatoDia.format(_rango!.start)} – '
                                '${_formatoDia.format(_rango!.end)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_rango != null)
                    IconButton(
                      tooltip: 'Quitar rango de fechas',
                      icon: const Icon(Icons.clear),
                      onPressed: _quitarRango,
                    ),
                ],
              ),
            ),
            Expanded(child: _contenido()),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Mensaje(
        icono: Icons.error_outline,
        texto: _error!,
        accion: OutlinedButton(
          onPressed: _recargar,
          child: const Text('Reintentar'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: _registros.isEmpty
          ? const _Mensaje(
              icono: Icons.history_toggle_off,
              texto: 'No hay registros con esos filtros',
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _registros.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i < _registros.length) {
                  return _TarjetaRegistro(registro: _registros[i]);
                }
                if (!_hayMas) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No hay más registros',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return OutlinedButton(
                  onPressed: _cargandoMas ? null : _cargarMas,
                  child: _cargandoMas
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cargar más'),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------
// Tarjeta de un registro
// ---------------------------------------------------------------

class _TarjetaRegistro extends StatelessWidget {
  final RegistroAuditoria registro;
  const _TarjetaRegistro({required this.registro});

  static final DateFormat _formatoFechaHora =
      DateFormat('dd/MM/yyyy HH:mm', 'es');

  @override
  Widget build(BuildContext context) {
    final r = registro;
    final actor = r.actorNombre == null
        ? 'Sistema (automático)'
        : '${r.actorNombre} (${_rolLegible(r.actorRol)})';
    final lineas = _lineasDetalle(r);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Quita las líneas que ExpansionTile dibuja al abrirse
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: UniNorteColors.dorado.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconoOrigen(r.origen),
                color: UniNorteColors.azulMarino, size: 22),
          ),
          title: Text(
            '${_accionLegible(r.accion)} · ${r.entidad ?? '(sin datos)'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: UniNorteColors.textoPrimario,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$actor\n${_formatoFechaHora.format(r.realizadoEn)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          children: lineas.isEmpty
              ? [
                  Text('Sin detalle',
                      style: Theme.of(context).textTheme.bodyMedium),
                ]
              : [
                  for (final l in lineas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _LineaDetalle(etiqueta: l.$1, valor: l.$2),
                    ),
                ],
        ),
      ),
    );
  }
}

class _LineaDetalle extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _LineaDetalle({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$etiqueta: ',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: UniNorteColors.textoPrimario,
            ),
          ),
          TextSpan(
            text: valor,
            style: const TextStyle(color: UniNorteColors.textoSecundario),
          ),
        ],
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

// ---------------------------------------------------------------
// Textos legibles
// ---------------------------------------------------------------

IconData _iconoOrigen(String origen) => switch (origen) {
      'usuarios' => Icons.person_outline,
      'eventos' => Icons.event_note_outlined,
      'asistencias' => Icons.how_to_reg_outlined,
      'validadores' => Icons.verified_user_outlined,
      'carreras' => Icons.school_outlined,
      _ => Icons.history,
    };

String _accionLegible(String accion) => switch (accion) {
      'alta' => 'Alta',
      'modificacion' => 'Modificación',
      'baja' => 'Baja',
      'correccion' => 'Corrección de asistencia',
      'cambio_horario' => 'Cambio de horario',
      'restablecer_clave' => 'Restablecimiento de clave',
      'carga_evento_pasado' => 'Carga de evento pasado',
      'edicion_evento_pasado' => 'Corrección de evento pasado',
      'reactivacion_evento' => 'Reactivación de evento',
      _ => accion,
    };

String _rolLegible(String? rol) => switch (rol) {
      'alumno' => 'alumno',
      'admin' => 'administrador',
      'superadmin' => 'superadmin',
      'validador' => 'validador',
      null => 'sin rol',
      _ => rol,
    };

/// Nombres de columnas en lenguaje de usuario.
const Map<String, String> _campos = {
  'nombre_completo': 'Nombre',
  'ci': 'C.I. / código',
  'correo_institucional': 'Correo',
  'carrera': 'Carrera',
  'rol': 'Rol',
  'activo': 'Activo',
  'horas_requeridas': 'Horas requeridas',
  'evento_asignado_id': 'Evento asignado',
  'vigente_hasta': 'Vigente hasta',
  'creado_por': 'Creado por',
  'nombre': 'Nombre',
  'descripcion': 'Descripción',
  'categoria': 'Categoría',
  'expositor': 'Expositor',
  'fecha': 'Fecha',
  'hora_inicio': 'Hora de inicio',
  'hora_fin': 'Hora de fin',
  'ubicacion': 'Ubicación',
  'modalidad': 'Modalidad',
  'horas_otorgadas': 'Horas otorgadas',
  'cupos_maximos': 'Cupos máximos',
  'tolerancia_entrada_min': 'Tolerancia de entrada (min)',
  'tolerancia_salida_min': 'Tolerancia de salida (min)',
  'salida_anticipada_en': 'Salida anticipada autorizada',
  'estado': 'Estado',
  'entrada_en': 'Entrada',
  'salida_en': 'Salida',
  'metodo_entrada': 'Método de entrada',
  'metodo_salida': 'Método de salida',
  'validado_por': 'Validado por',
  'hash_certificado': 'Certificado',
  'migrado': 'Migrado',
  'usuario_id': 'Usuario',
  'evento_id': 'Evento',
  'activa': 'Activa',
  'facultad_id': 'Facultad (ID)',
  'facultad': 'Facultad',
  'director_nombre': 'Director/a',
  'director_cargo': 'Cargo del director/a',
  'decano_nombre': 'Decano/a',
  'decano_cargo': 'Cargo del decano/a',
  'carga_historica': 'Cargado como evento pasado',
  'carreras': 'Carreras habilitadas',
};

/// Campos que no aportan en un alta (identificadores internos).
const Set<String> _omitirEnAlta = {'id', 'created_at', 'creado_en'};

String _etiquetaCampo(String clave) =>
    _campos[clave] ?? clave.replaceAll('_', ' ');

final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final RegExp _marcaTiempo = RegExp(r'^\d{4}-\d{2}-\d{2}T');
final RegExp _soloHora = RegExp(r'^\d{2}:\d{2}:\d{2}$');
final RegExp _soloFecha = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final DateFormat _fmtFechaHora = DateFormat('dd/MM/yyyy HH:mm', 'es');
final DateFormat _fmtFecha = DateFormat('dd/MM/yyyy', 'es');

String _valor(dynamic v, {String? campo}) {
  if (v == null) return '—';
  if (v is bool) return v ? 'Sí' : 'No';
  if (v is num) return '$v';
  // Listas (p. ej. las carreras habilitadas de un evento, script 21)
  if (v is List) return v.isEmpty ? '—' : v.join(', ');
  final s = v.toString();
  if (campo == 'rol') return _rolLegible(s);
  if (campo == 'hash_certificado') return 'emitido';
  if (_uuid.hasMatch(s)) return 'ID ${s.substring(0, 8)}';
  if (_marcaTiempo.hasMatch(s)) {
    final d = DateTime.tryParse(s);
    if (d != null) return _fmtFechaHora.format(d.toLocal());
  }
  if (_soloHora.hasMatch(s)) return s.substring(0, 5);
  if (_soloFecha.hasMatch(s)) {
    final d = DateTime.tryParse(s);
    if (d != null) return _fmtFecha.format(d);
  }
  return s;
}

String _cambio(dynamic antes, dynamic despues, {String? campo}) =>
    '${_valor(antes, campo: campo)} → ${_valor(despues, campo: campo)}';

/// Líneas (etiqueta, valor) para el detalle desplegable.
List<(String, String)> _lineasDetalle(RegistroAuditoria r) {
  final d = r.detalle;
  final lineas = <(String, String)>[];

  if (r.motivo != null) lineas.add(('Motivo', r.motivo!));

  switch (r.accion) {
    case 'correccion':
      final campo = d['campo'] == 'salida' ? 'Salida' : 'Entrada';
      lineas.add((campo, _cambio(d['antes'], d['despues'])));
    case 'cambio_horario':
      for (final clave in const ['hora_inicio', 'hora_fin']) {
        final c = d[clave];
        if (c is Map) {
          lineas.add((_etiquetaCampo(clave), _cambio(c['antes'], c['despues'])));
        }
      }
      if (d['con_entradas'] is bool) {
        lineas.add(('Había entradas registradas', _valor(d['con_entradas'])));
      }
    case 'restablecer_clave':
      lineas.add(('Evento', _valor(d['evento'])));
    default:
      // Cambios generales: { campo: { antes, despues } }
      // La carga de un evento pasado (script 21) es un alta.
      final esAlta = r.accion == 'alta' || r.accion == 'carga_evento_pasado';
      final claves = d.keys.toList()..sort();
      for (final clave in claves) {
        final c = d[clave];
        if (c is! Map) continue;
        if (esAlta) {
          if (_omitirEnAlta.contains(clave) || c['despues'] == null) continue;
          lineas.add((_etiquetaCampo(clave), _valor(c['despues'], campo: clave)));
        } else if (r.accion == 'baja') {
          lineas.add((_etiquetaCampo(clave), _valor(c['antes'], campo: clave)));
        } else {
          lineas.add((
            _etiquetaCampo(clave),
            _cambio(c['antes'], c['despues'], campo: clave),
          ));
        }
      }
  }
  return lineas;
}