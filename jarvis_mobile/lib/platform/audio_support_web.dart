import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

Future<String?> playBase64Audio(AudioPlayer player, List<int> bytes) async {
  // No file system on web — feed the bytes straight to the player.
  await player.play(BytesSource(Uint8List.fromList(bytes)));
  return null;
}

Future<void> deleteTempAudio(String? path) async {
  // Nothing to clean up on web.
}
