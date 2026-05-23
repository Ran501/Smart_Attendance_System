import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import 'export_permission_service.dart';

class ReportExportResult {
  final File file;
  final String displayPath;

  const ReportExportResult({required this.file, required this.displayPath});
}

class ReportService {
  static final _stamp = DateFormat('yyyy-MM-dd_HHmm');
  static const _subfolder = 'FacePass';
  static final MediaStore _mediaStore = MediaStore();
  static bool _mediaStoreReady = false;

  String _exportFileName(String sessionId, String ext) {
    final safeId = sessionId.replaceAll(RegExp(r'[^\w-]'), '_');
    final time = _stamp.format(DateTime.now());
    return 'FacePass_attendance_${safeId}_$time.$ext';
  }

  Future<void> _ensureMediaStoreReady() async {
    if (_mediaStoreReady) return;
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = _subfolder;
    _mediaStoreReady = true;
  }

  Future<File> _writeTemp(String sessionId, String ext, List<int> bytes) async {
    final tempDir = await getTemporaryDirectory();
    final temp = File('${tempDir.path}/${_exportFileName(sessionId, ext)}');
    await temp.writeAsBytes(bytes);
    return temp;
  }

  Future<File> _writeTempText(
    String sessionId,
    String ext,
    String content,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final temp = File('${tempDir.path}/${_exportFileName(sessionId, ext)}');
    await temp.writeAsString(content);
    return temp;
  }

  Future<ReportExportResult> _saveToPublicDownloads(
    File tempFile,
    String fileName,
  ) async {
    await _ensureMediaStoreReady();
    await ExportPermissionService.requestBestEffort();

    SaveInfo? saveInfo;
    Object? mediaStoreError;
    try {
      saveInfo = await _mediaStore.saveFile(
        tempFilePath: tempFile.path,
        dirType: DirType.download,
        dirName: DirName.download,
      );
    } catch (e) {
      mediaStoreError = e;
    }

    if (saveInfo != null && saveInfo.uri.toString().isNotEmpty) {
      final savedName = saveInfo.name.isNotEmpty ? saveInfo.name : fileName;
      return ReportExportResult(
        file: tempFile,
        displayPath: 'Downloads/$_subfolder/$savedName',
      );
    }

    final fallback = await _fallbackDirectSave(tempFile, fileName);
    if (fallback != null) return fallback;

  if (mediaStoreError != null) {
      throw Exception('Could not save report: $mediaStoreError');
    }
    throw Exception(
      'Could not save to Downloads. Allow storage in Settings, then try again.',
    );
  }

  Future<ReportExportResult?> _fallbackDirectSave(
    File tempFile,
    String fileName,
  ) async {
    final allowed = await ExportPermissionService.ensureGrantedForLegacyWrite();
    if (!allowed) return null;

    final candidates = <Directory>[];

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      candidates.add(Directory('${downloads.path}/$_subfolder'));
    }
    if (Platform.isAndroid) {
      candidates.add(Directory('/storage/emulated/0/Download/$_subfolder'));
    }

    for (final dir in candidates) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final dest = File('${dir.path}/$fileName');
        await dest.writeAsBytes(await tempFile.readAsBytes(), flush: true);
        if (await dest.exists()) {
          return ReportExportResult(
            file: dest,
            displayPath: 'Downloads/$_subfolder/$fileName',
          );
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<ReportExportResult> _publishExport(File tempFile, String fileName) async {
    if (!kIsWeb && Platform.isAndroid) {
      return _saveToPublicDownloads(tempFile, fileName);
    }

    final downloads = await getDownloadsDirectory();
    if (downloads == null) {
      throw Exception('Downloads folder is not available on this device.');
    }

    final dir = Directory('${downloads.path}/$_subfolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dest = File('${dir.path}/$fileName');
    await dest.writeAsBytes(await tempFile.readAsBytes());
    return ReportExportResult(
      file: dest,
      displayPath: 'Downloads/$_subfolder/$fileName',
    );
  }

  Future<ReportExportResult> exportCsv({
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
    final name = _exportFileName(sessionId, 'csv');
    final temp = await _writeTempText(sessionId, 'csv', csv);
    return _publishExport(temp, name);
  }

  Future<ReportExportResult> exportPdf({
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
            headers: const ['Student', 'Status', 'Confidence', 'GPS OK'],
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
    final name = _exportFileName(sessionId, 'pdf');
    final temp = await _writeTemp(sessionId, 'pdf', await pdf.save());
    return _publishExport(temp, name);
  }

  Future<ReportExportResult> exportExcel({
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
    final name = _exportFileName(sessionId, 'xlsx');
    final bytes = excel.encode()!;
    final temp = await _writeTemp(sessionId, 'xlsx', bytes);
    return _publishExport(temp, name);
  }
}
