import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ModelDownloader {
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<String> getModelPath(String filename) async {
    final path = await _localPath;
    return '$path/$filename';
  }

  Future<bool> isModelDownloaded(String filename) async {
    final path = await getModelPath(filename);
    return File(path).exists();
  }

  Future<void> downloadModel(String url, String filename, Function(double) onProgress) async {
    _cancelToken = CancelToken();
    final finalPath = await getModelPath(filename);
    // Download to a .part temp file: an interrupted transfer must never leave
    // a partial file under the real name (it passes the existence check, then
    // native model loading fails with a confusing "generation failed: -1").
    final partPath = '$finalPath.part';
    final partFile = File(partPath);
    if (await partFile.exists()) {
      await partFile.delete(); // start over, no resume
    }

    try {
      await _dio.download(
        url,
        partPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
        cancelToken: _cancelToken,
      );
      await partFile.rename(finalPath);
    } catch (e) {
      if (await partFile.exists()) {
        await partFile.delete();
      }
      // Only DioException can be a cancellation; the cast used to turn any
      // other error type (e.g. a rename failure) into a TypeError.
      if (e is DioException && CancelToken.isCancel(e)) {
        debugPrint('Download cancelled');
      } else {
        rethrow;
      }
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
  }
}
