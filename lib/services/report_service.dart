import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportService {
  Future<File> exportCsv({
    required String sessionId,
    required List<Map<String, dynamic>> records,
  }) async {
    final rows = [
      ['Student', 'Student ID', 'Status', 'Confidence', 'Geo Valid', 'WiFi Valid', 'Time'],
      ...records.map((r) => [
            r['full_name'] ?? '',
            r['student_code'] ?? '',
            r['status'] ?? '',
            '${((r['match_confidence'] as num? ?? 0) * 100).toStringAsFixed(1)}%',
            '${r['geo_valid'] ?? false}',
            '${r['wifi_valid'] ?? false}',
            r['marked_at']?.toString() ?? '',
          ]),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    return _writeFile('attendance_$sessionId.csv', csv);
  }

  Future<File> exportPdf({
    required String sessionId,
    required Map<String, dynamic> session,
    required List<Map<String, dynamic>> records,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Attendance Report - $sessionId')),
          pw.Text('Class: ${session['class_name'] ?? session['class_id']}'),
          pw.Text('Subject: ${session['subject_name'] ?? ''}'),
          pw.Text('Date: ${session['started_at'] ?? ''}'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Student', 'Status', 'Confidence', 'GPS OK'],
            data: records
                .map((r) => [
                      r['full_name'] ?? '',
                      r['status'] ?? '',
                      '${((r['match_confidence'] as num? ?? 0) * 100).toStringAsFixed(1)}%',
                      '${r['geo_valid'] ?? false}',
                    ])
                .toList(),
          ),
        ],
      ),
    );
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/attendance_$sessionId.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  Future<File> exportExcel({
    required String sessionId,
    required List<Map<String, dynamic>> records,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Attendance'];
    sheet.appendRow([
      TextCellValue('Student'),
      TextCellValue('Status'),
      TextCellValue('Confidence'),
      TextCellValue('Marked At'),
    ]);
    for (final r in records) {
      sheet.appendRow([
        TextCellValue('${r['full_name']}'),
        TextCellValue('${r['status']}'),
        TextCellValue(
          '${((r['match_confidence'] as num? ?? 0) * 100).toStringAsFixed(1)}%',
        ),
        TextCellValue('${r['marked_at']}'),
      ]);
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/attendance_$sessionId.xlsx';
    final bytes = excel.encode();
    final file = File(path);
    await file.writeAsBytes(bytes!);
    return file;
  }

  Future<File> _writeFile(String name, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(content);
    return file;
  }
}
