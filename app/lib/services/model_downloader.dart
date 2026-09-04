import 'dart:io';
import 'package:dio/dio.dart';
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
    final savePath = await getModelPath(filename);

    try {
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
        cancelToken: _cancelToken,
      );
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        print('Download cancelled');
      } else {
        rethrow;
      }
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
  }
}
