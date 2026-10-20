import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'certificados_provider.dart';

/// Genera el PDF del certificado en el teléfono (no se guarda en Supabase).
/// Diseño aprobado por Kevin el 20/10: igual al certificado original
/// (A4 horizontal), con el fondo, el sello y las fuentes del paso 7.0.
/// Las medidas están en puntos (1/72 de pulgada) desde el borde superior
/// izquierdo, tomadas del original.
class CertificadoPdf {
  CertificadoPdf._();

  // Rutas de los recursos (paso 7.0). Si cambian, ajustar solo acá.
  static const String _fondo = 'assets/certificados/fondo_certificado.jpg';
  static const String _sello = 'assets/certificados/sello_uninorte.jpg';
  static const String _serifRegular = 'assets/fonts/uninorte-serif-regular.ttf';
  static const String _serifBold = 'assets/fonts/uninorte-serif-bold.ttf';
  static const String _serifItalic = 'assets/fonts/uninorte-serif-italic.ttf';
  static const String _barlow = 'assets/fonts/Barlow-Medium.ttf';

  static _Recursos? _cache;

  static Future<_Recursos> _recursos() async {
    final c = _cache;
    if (c != null) return c;

    Future<Uint8List> bytes(String ruta) async =>
        (await rootBundle.load(ruta)).buffer.asUint8List();
    Future<pw.Font> fuente(String ruta) async =>
        pw.Font.ttf(await rootBundle.load(ruta));

    final r = _Recursos(
      fondo: pw.MemoryImage(await bytes(_fondo)),
      sello: pw.MemoryImage(await bytes(_sello)),
      regular: await fuente(_serifRegular),
      bold: await fuente(_serifBold),
      italic: await fuente(_serifItalic),
      nombre: await fuente(_barlow),
    );
    _cache = r;
    return r;
  }

  static const List<String> _dias = [
    'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
  ];
  static const List<String> _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// "miércoles 14 de octubre de 2026" (sin coma, decisión del 20/10).
  static String fechaLarga(DateTime f) {
    final d = DateTime(f.year, f.month, f.day);
    return '${_dias[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]} '
        'de ${d.year}';
  }

  static String _horas(int h) => h == 1 ? '1 hora' : '$h horas';

  static Future<Uint8List> generar(Certificado c) async {
    if (!c.disponible) {
      throw StateError('El certificado todavía no tiene firmantes');
    }
    final r = await _recursos();

    const negro = PdfColor.fromInt(0xFF141414);
    const formato = PdfPageFormat(841.89, 595.28); // A4 horizontal
    final ancho = formato.width;

    pw.TextStyle estilo(pw.Font f, double size) =>
        pw.TextStyle(font: f, fontSize: size, color: negro);

    final doc = pw.Document(
      title: 'Certificado - ${c.evento}',
      author: 'UniNorte',
      creator: 'UniNorte Extensiones',
    );

    // Firma: línea punteada, nombre en negrita y cargo en cursiva,
    // centrados en [centro].
    List<pw.Widget> firma(double centro, String nombre, String cargo) => [
          pw.Positioned(
            left: centro - 98,
            top: 472.5,
            child: pw.Container(
              width: 196,
              height: 1,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: negro,
                    width: 0.9,
                    style: pw.BorderStyle.dotted,
                  ),
                ),
              ),
            ),
          ),
          pw.Positioned(
            left: centro - 150,
            top: 478.9,
            child: pw.SizedBox(
              width: 300,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                child: pw.Text(nombre, style: estilo(r.bold, 12)),
              ),
            ),
          ),
          pw.Positioned(
            left: centro - 150,
            top: 493.2,
            child: pw.SizedBox(
              width: 300,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                child: pw.Text(cargo, style: estilo(r.italic, 12)),
              ),
            ),
          ),
        ];

    doc.addPage(
      pw.Page(
        pageFormat: formato,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.SizedBox(
          width: formato.width,
          height: formato.height,
          child: pw.Stack(
            children: [
              // Fondo: bordes, logo, "CERTIFICADO", "Por cuanto", línea y escudo.
              pw.Positioned.fill(
                child: pw.Image(r.fondo, fit: pw.BoxFit.fill),
              ),

              // Nombre del alumno en mayúsculas (se achica si no entra).
              pw.Positioned(
                left: (ancho - 560) / 2,
                top: 295,
                child: pw.SizedBox(
                  width: 560,
                  height: 25.2,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    child: pw.Text(
                      c.alumno.toUpperCase(),
                      style: estilo(r.nombre, 21),
                    ),
                  ),
                ),
              ),

              // Texto justificado y carga horaria.
              pw.Positioned(
                left: 83.2,
                top: 341.8,
                child: pw.SizedBox(
                  width: 668.4,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.RichText(
                        textAlign: pw.TextAlign.justify,
                        text: pw.TextSpan(
                          style: estilo(r.regular, 14).copyWith(lineSpacing: 6.1),
                          children: [
                            const pw.TextSpan(text: 'ha participado en el evento '),
                            pw.TextSpan(
                              text: c.evento,
                              style: estilo(r.bold, 14),
                            ),
                            pw.TextSpan(
                              text: ', realizado en ${c.ubicacion} el día '
                                  '${fechaLarga(c.fecha)}. Se le otorga este '
                                  'certificado con todos los privilegios y '
                                  'prerrogativas que le correspondan.',
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 13.8),
                      pw.Text(
                        'Carga horaria: ${_horas(c.horas)}',
                        style: estilo(r.bold, 14),
                      ),
                    ],
                  ),
                ),
              ),

              // Sello en el centro, entre las firmas.
              pw.Positioned(
                left: 393,
                top: 419.5,
                child: pw.Image(r.sello, width: 84, height: 88),
              ),

              ...firma(
                269.25,
                c.directorNombre!,
                '${c.directorCargo} de la Carrera de ${c.carrera}',
              ),
              ...firma(
                593.3,
                c.decanoNombre!,
                '${c.decanoCargo} de la Facultad de ${c.facultad}',
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }
}

class _Recursos {
  final pw.ImageProvider fondo;
  final pw.ImageProvider sello;
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font nombre;

  const _Recursos({
    required this.fondo,
    required this.sello,
    required this.regular,
    required this.bold,
    required this.italic,
    required this.nombre,
  });
}