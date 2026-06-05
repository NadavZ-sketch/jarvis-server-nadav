import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> playBase64Audio(AudioPlayer player, List<int> bytes) async {
  final tmpDir = await getTemporaryDirectory();
  final tmpPath =
      '${tmpDir.path}/jarvis_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
  await File(tmpPath).writeAsBytes(bytes);
  await player.play(DeviceFileSource(tmpPath));
  return tmpPath;
}

Future<void> deleteTempAudio(String? path) async {
  if (path == null) return;
  try {
    await File(path).delete();
  } catch (_) {}
}
