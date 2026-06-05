// Platform-agnostic playback of base64-encoded TTS audio.
//
// On mobile/desktop the bytes are written to a temp file and played via
// [DeviceFileSource] (BytesSource is unreliable on Android in audioplayers v6).
// On web there is no file system, so the bytes are played directly through a
// [BytesSource]. The conditional import below picks the right implementation at
// compile time so `dart:io` never reaches the web build.
import 'package:audioplayers/audioplayers.dart';

import 'audio_support_native.dart'
    if (dart.library.html) 'audio_support_web.dart' as impl;

/// Plays [bytes] through [player]. Returns a temp-file path that the caller
/// should later pass to [deleteTempAudio], or `null` when no file was created
/// (web).
Future<String?> playBase64Audio(AudioPlayer player, List<int> bytes) =>
    impl.playBase64Audio(player, bytes);

/// Deletes the temp file previously returned by [playBase64Audio]. No-op on web
/// or when [path] is null.
Future<void> deleteTempAudio(String? path) => impl.deleteTempAudio(path);
