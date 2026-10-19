import 'dart:convert';
import 'dart:typed_data';

/// Lectura y generación de los CSV de la carga masiva de alumnos (fase 6).
///
/// Formato acordado: separador ";", una fila de encabezado y las columnas
/// en este orden. Los archivos que genera la app (plantilla, carreras e
/// informe) van en UTF-8 con BOM para que Excel los abra con tildes y ñ.

/// Separador de columnas (Excel en español).
const separadorCsv = ';';

/// Máximo de filas de datos por archivo (también lo exige el servidor).
const maxFilasArchivo = 300;

/// Encabezados de la plantilla, en el orden obligatorio.
const columnasPlantilla = [
  'nombre_completo',
  'ci',
  'correo',
  'carrera (nombre oficial exacto)',
  'horas_requeridas',
];

/// Cómo se reconoce cada encabezado (en minúsculas y sin puntos), para
/// aceptar pequeñas variaciones como "C.I." o "Nombre completo".
const _prefijosEncabezado = ['nombre', 'ci', 'correo', 'carrera', 'horas'];

/// Tamaño máximo del archivo (300 filas ocupan bastante menos).
const maxBytesArchivo = 1024 * 1024;

/// Una fila de datos del CSV, con los valores tal como vinieron (sin
/// espacios a los costados).
class FilaCsv {
  /// Posición entre las filas de datos (1..n), sin contar líneas vacías.
  /// Es el número que se envía al servidor.
  final int numero;

  /// Registro del archivo (1 = encabezado). Coincide con la fila de Excel
  /// salvo que alguna celda tenga saltos de línea.
  final int linea;

  final String nombre;
  final String ci;
  final String correo;
  final String carrera;
  final String horas;

  const FilaCsv({
    required this.numero,
    required this.linea,
    required this.nombre,
    required this.ci,
    required this.correo,
    required this.carrera,
    required this.horas,
  });
}

/// Error del archivo completo (formato, encabezado, cantidad de filas).
class ArchivoInvalidoException implements Exception {
  final String mensaje;
  const ArchivoInvalidoException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Lee el CSV y devuelve sus filas de datos.
List<FilaCsv> leerFilasCsv(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const ArchivoInvalidoException('El archivo está vacío');
  }
  if (bytes.length > maxBytesArchivo) {
    throw const ArchivoInvalidoException(
      'El archivo es demasiado grande (máximo 1 MB)',
    );
  }

  final registros = _parsearRegistros(decodificarCsv(bytes));

  final idxEncabezado = registros.indexWhere((r) => !_registroVacio(r));
  if (idxEncabezado < 0) {
    throw const ArchivoInvalidoException('El archivo está vacío');
  }

  final encabezado = registros[idxEncabezado];
  if (encabezado.length == 1 && encabezado.first.contains(',')) {
    throw const ArchivoInvalidoException(
      'El archivo usa comas como separador. Usá la plantilla y guardala '
      'con separador ";" (punto y coma).',
    );
  }
  if (!_encabezadoValido(encabezado)) {
    throw const ArchivoInvalidoException(
      'El encabezado no coincide con la plantilla. Descargá la plantilla '
      'y copiá los datos respetando el orden de las columnas.',
    );
  }

  final filas = <FilaCsv>[];
  for (var i = idxEncabezado + 1; i < registros.length; i++) {
    final r = registros[i];
    if (_registroVacio(r)) continue;
    String col(int j) => j < r.length ? r[j].trim() : '';
    filas.add(FilaCsv(
      numero: filas.length + 1,
      linea: i + 1,
      nombre: col(0),
      ci: col(1),
      correo: col(2),
      carrera: col(3),
      horas: col(4),
    ));
  }

  if (filas.isEmpty) {
    throw const ArchivoInvalidoException(
      'El archivo no tiene filas de datos (solo el encabezado)',
    );
  }
  if (filas.length > maxFilasArchivo) {
    throw ArchivoInvalidoException(
      'El archivo tiene ${filas.length} filas y el máximo es '
      '$maxFilasArchivo. Dividilo en varios archivos.',
    );
  }
  return filas;
}

/// UTF-8 (con o sin BOM). Si el archivo no es UTF-8 válido, se lee como
/// Latin-1, que es como guarda Excel el formato "CSV (delimitado...)".
String decodificarCsv(Uint8List bytes) {
  var datos = bytes;
  if (datos.length >= 3 &&
      datos[0] == 0xEF &&
      datos[1] == 0xBB &&
      datos[2] == 0xBF) {
    datos = Uint8List.sublistView(datos, 3);
  }
  try {
    return utf8.decode(datos);
  } on FormatException {
    return latin1.decode(datos);
  }
}

/// Parser de CSV con comillas ("a;b", comillas dobles escapadas) y
/// finales de línea \r\n, \n o \r.
List<List<String>> _parsearRegistros(String texto) {
  final registros = <List<String>>[];
  var registro = <String>[];
  var campo = StringBuffer();
  var entreComillas = false;

  for (var i = 0; i < texto.length; i++) {
    final c = texto[i];
    if (entreComillas) {
      if (c == '"') {
        if (i + 1 < texto.length && texto[i + 1] == '"') {
          campo.write('"');
          i++;
        } else {
          entreComillas = false;
        }
      } else {
        campo.write(c);
      }
    } else if (c == '"') {
      entreComillas = true;
    } else if (c == separadorCsv) {
      registro.add(campo.toString());
      campo = StringBuffer();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < texto.length && texto[i + 1] == '\n') i++;
      registro.add(campo.toString());
      campo = StringBuffer();
      registros.add(registro);
      registro = <String>[];
    } else {
      campo.write(c);
    }
  }

  if (campo.isNotEmpty || registro.isNotEmpty) {
    registro.add(campo.toString());
    registros.add(registro);
  }
  return registros;
}

bool _registroVacio(List<String> r) => r.every((c) => c.trim().isEmpty);

bool _encabezadoValido(List<String> encabezado) {
  if (encabezado.length < _prefijosEncabezado.length) return false;
  for (var j = 0; j < _prefijosEncabezado.length; j++) {
    final normalizado =
        encabezado[j].trim().toLowerCase().replaceAll('.', '');
    if (!normalizado.startsWith(_prefijosEncabezado[j])) return false;
  }
  return true;
}

// ---------------------------------------------------------------
// Generación de archivos
// ---------------------------------------------------------------

/// Plantilla vacía: solo el encabezado.
Uint8List generarPlantillaCsv() => generarCsv([columnasPlantilla]);

/// Lista oficial de carreras, una por línea, para copiar tal cual.
Uint8List generarCarrerasCsv(List<String> carreras) => generarCsv([
      ['carrera (copiar tal cual en la plantilla)'],
      for (final c in carreras) [c],
    ]);

/// CSV en UTF-8 con BOM, separador ";" y finales de línea \r\n.
/// Con [proteger], las celdas que Excel interpretaría como fórmula
/// (empiezan con = + - @) se guardan como texto.
Uint8List generarCsv(List<List<String>> filas, {bool proteger = false}) {
  final texto = StringBuffer();
  for (final fila in filas) {
    texto.write(fila.map((v) => _celda(v, proteger)).join(separadorCsv));
    texto.write('\r\n');
  }
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(texto.toString())]);
}

String _celda(String valor, bool proteger) {
  var v = valor;
  if (proteger && v.isNotEmpty && '=+-@'.contains(v[0])) v = "'$v";
  final requiereComillas = v.contains(separadorCsv) ||
      v.contains('"') ||
      v.contains('\n') ||
      v.contains('\r');
  return requiereComillas ? '"${v.replaceAll('"', '""')}"' : v;
}