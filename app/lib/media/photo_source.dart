import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// One picture as the camera or the picker handed it over, before anything is
/// done to it.
///
/// Bytes rather than a path on purpose. A path is a handle on a file this app
/// does not own — the original in the camera roll — and passing it around
/// invites code to read it later, write next to it, or delete it. Reading once
/// and carrying the bytes keeps the original where it is.
@immutable
class PickedPhoto {
  const PickedPhoto(this.bytes);

  final Uint8List bytes;
}

/// What came back from asking for a photo.
///
/// Five cases rather than a nullable list, because the screen has something
/// different to say about each and only one of them is an error: a cancel is a
/// decision, a refusal needs a way into the system settings, and a build with
/// no camera needs to say so rather than showing a button that does nothing.
sealed class PhotoPick {
  const PhotoPick();
}

/// At least one picture, in the order it was chosen.
final class PhotoPicked extends PhotoPick {
  const PhotoPicked(this.photos);

  final List<PickedPhoto> photos;
}

/// The camera or the picker was closed without choosing. **Nothing is sent.**
final class PhotoCancelled extends PhotoPick {
  const PhotoCancelled();
}

/// The system refused: no camera or photo permission.
final class PhotoRefused extends PhotoPick {
  const PhotoRefused({required this.camera});

  /// Which permission it was, so the sentence can name the right one.
  final bool camera;
}

/// This build or this platform has no camera or picker to open.
final class PhotoUnavailable extends PhotoPick {
  const PhotoUnavailable();
}

/// Something else went wrong. [detail] is for the message, not for a log.
final class PhotoFailed extends PhotoPick {
  const PhotoFailed(this.detail);

  final String detail;
}

/// Where photos come from, behind an interface.
///
/// The same reason the keystore, the microphone and the notification
/// permission are behind one: every case above has to be reachable in a test
/// on a machine with no camera, and a refusal that can only be produced by
/// tapping "Don't Allow" on a real phone is a refusal nobody ever checks.
abstract interface class PhotoSource {
  /// Opens the camera. One picture, or one of the other cases.
  Future<PhotoPick> capture();

  /// Opens the system photo picker for one or more pictures.
  Future<PhotoPick> pickImages();
}

/// The real one, on `image_picker`.
///
/// Two deliberate settings:
///
/// * **`requestFullMetadata: false`.** On iOS this is what keeps the app out
///   of the full photo library: the picker hands back the pictures that were
///   chosen and nothing else, and the app never asks to read the library. It
///   also means iOS strips the metadata before this code sees it, which is a
///   second pair of hands on the same job rather than a reason to skip ours.
/// * **no `imageQuality`.** Letting the plugin re-encode would take the
///   orientation decision away from [PhotoImage], which has to bake the tag in
///   before it is thrown away. The resizing and the stripping happen in one
///   place, where there is a test for them.
///
/// Neither the camera nor the picker writes to the public gallery: the picture
/// goes to a temporary file the plugin owns, which is read once here.
class ImagePickerPhotoSource implements PhotoSource {
  ImagePickerPhotoSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PhotoPick> capture() => _guard(() async {
        final shot = await _picker.pickImage(
          source: ImageSource.camera,
          requestFullMetadata: false,
        );
        if (shot == null) return const PhotoCancelled();
        return PhotoPicked([PickedPhoto(await _readAndTidy(shot))]);
      }, camera: true);

  @override
  Future<PhotoPick> pickImages() => _guard(() async {
        final chosen = await _picker.pickMultiImage(requestFullMetadata: false);
        if (chosen.isEmpty) return const PhotoCancelled();
        final photos = <PickedPhoto>[];
        // Sequential, so the order the pictures were chosen in is the order
        // they are read in and the order they are sent in.
        for (final file in chosen) {
          photos.add(PickedPhoto(await _readAndTidy(file)));
        }
        return PhotoPicked(photos);
      }, camera: false);

  /// Reads the picture and deletes the plugin's copy of it.
  ///
  /// **This never touches anything in the photo library.** What the plugin
  /// hands back is not the original: a capture goes to the app's own temporary
  /// directory and never to the public gallery, and a library selection is
  /// copied into that same private directory before the path is returned. The
  /// original stays exactly where it was.
  ///
  /// The copy, on the other hand, is a decrypted photograph sitting in a file.
  /// Leaving it there means a chat whose messages disappear has left its
  /// pictures in a cache folder that survives the conversation, so it goes as
  /// soon as the bytes are in memory. A failure to delete is not worth an error
  /// on screen — the picture is already read, and the next cache clear takes
  /// the file.
  Future<Uint8List> _readAndTidy(XFile file) async {
    final bytes = await file.readAsBytes();
    try {
      await File(file.path).delete();
    } on Object {
      // Nothing to say and nothing to do. Never rethrown: a temp file that
      // would not delete must not turn a picked photo into an error.
    }
    return bytes;
  }

  /// Turns the plugin's exceptions into the cases above.
  Future<PhotoPick> _guard(Future<PhotoPick> Function() body, {required bool camera}) async {
    try {
      return await body();
    } on Object catch (failure) {
      return photoPickFailure(failure, camera: camera);
    }
  }
}

/// Which case an exception from the picker means.
///
/// Public and separate from the class that throws it, because this is the part
/// worth a test and the part that cannot be reached through a plugin on a
/// machine with no camera. `image_picker` reports a refused permission as a
/// `PlatformException` with a documented code, which is the only way to tell a
/// refusal from a failure without pulling in a second permissions package.
PhotoPick photoPickFailure(Object failure, {required bool camera}) {
  if (failure is MissingPluginException) return const PhotoUnavailable();
  if (failure is! PlatformException) return PhotoFailed('$failure');
  return switch (failure.code) {
    'camera_access_denied' => const PhotoRefused(camera: true),
    'photo_access_denied' => const PhotoRefused(camera: false),
    // Restricted rather than refused — a managed device, or parental controls.
    // Nothing the app can ask for, and the same sentence and the same way into
    // the settings is the right answer.
    'camera_access_restricted' || 'photo_access_restricted' => PhotoRefused(camera: camera),
    // The plugin's own word for "no camera on this device", and what a
    // simulator answers.
    'no_available_camera' || 'not_supported' => const PhotoUnavailable(),
    _ => PhotoFailed(failure.message ?? failure.code),
  };
}

/// What a build with no camera and no picker reports.
class NoPhotoSource implements PhotoSource {
  const NoPhotoSource();

  @override
  Future<PhotoPick> capture() async => const PhotoUnavailable();

  @override
  Future<PhotoPick> pickImages() async => const PhotoUnavailable();
}
