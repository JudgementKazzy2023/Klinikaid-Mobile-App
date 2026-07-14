import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_store_plus/media_store_plus.dart';

/// Utility to format rows as a valid CSV string per RFC-4180.
String buildCsv(List<List<dynamic>> rows) {
  if (rows.isEmpty) return '';
  return const ListToCsvConverter().convert(rows);
}

/// Utility to write the CSV to the public Android Downloads folder via MediaStore.
/// Returns true if the file was successfully written and registered, false otherwise.
Future<bool> saveCsvToDownloads({
  required String filename,
  required String csvContent,
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$filename');
    await tempFile.writeAsString(csvContent);

    // Initialize MediaStore before saving
    MediaStore.appFolder = "KlinikAId";
    await MediaStore.ensureInitialized();

    final mediaStore = MediaStore();
    // Save to Downloads collection using media_store_plus API
    final result = await mediaStore.saveFile(
      tempFilePath: tempFile.path,
      dirType: DirType.download,
      dirName: DirType.download.defaults,
    );

    return result != null;
  } catch (e) {
    print('[saveCsvToDownloads] Error saving via MediaStore: $e');
    return false;
  }
}
