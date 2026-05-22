import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';

enum LivenessChallenge { blinkTwice, turnHeadLeft, turnHeadRight, smile }

class LivenessDetectionService {
  LivenessChallenge? _currentChallenge;
  int _blinkCount = 0;
  bool _leftTurnDone = false;
  bool _rightTurnDone = false;
  bool _smileDone = false;
  bool _wasEyesClosed = false;

  LivenessChallenge get currentChallenge =>
      _currentChallenge ?? LivenessChallenge.smile;

  List<LivenessChallenge> generateChallengeSequence() {
    final turns = [
      LivenessChallenge.turnHeadLeft,
      LivenessChallenge.turnHeadRight,
    ];
    turns.shuffle(Random());
    return [LivenessChallenge.smile, turns.first];
  }

  void startChallenge(LivenessChallenge challenge) {
    _currentChallenge = challenge;
    _resetProgress();
  }

  void _resetProgress() {
    _blinkCount = 0;
    _leftTurnDone = false;
    _rightTurnDone = false;
    _smileDone = false;
    _wasEyesClosed = false;
  }

  ({double progress, bool completed, String instruction}) processFrame(
    Face face,
  ) {
    switch (_currentChallenge) {
      case LivenessChallenge.blinkTwice:
        return _processBlink(face);
      case LivenessChallenge.turnHeadLeft:
        return _processHeadTurn(face, isLeft: true);
      case LivenessChallenge.turnHeadRight:
        return _processHeadTurn(face, isLeft: false);
      case LivenessChallenge.smile:
        return _processSmile(face);
      case null:
        return (progress: 0, completed: false, instruction: 'Initializing...');
    }
  }

  ({double progress, bool completed, String instruction}) _processBlink(
    Face face,
  ) {
    final left = face.leftEyeOpenProbability ?? 1.0;
    final right = face.rightEyeOpenProbability ?? 1.0;
    final eyesClosed = left < 0.3 && right < 0.3;

    if (_wasEyesClosed && !eyesClosed) {
      _blinkCount++;
    }
    _wasEyesClosed = eyesClosed;

    final completed = _blinkCount >= 2;
    return (
      progress: (_blinkCount / 2).clamp(0.0, 1.0),
      completed: completed,
      instruction: completed
          ? 'Blink verified!'
          : 'Blink twice (${_blinkCount}/2)',
    );
  }

  ({double progress, bool completed, String instruction}) _processHeadTurn(
    Face face, {
    required bool isLeft,
  }) {
    final yaw = face.headEulerAngleY ?? 0;

    // ML Kit analyses the raw camera image. The preview is mirrored only for
    // display, so the yaw sign must use the raw-image direction. This keeps the
    // liveness step natural: when the app asks for right, turning to your right
    // completes the right-turn step, and the same for left.
    const threshold = 15.0;

    debugPrint('[Liveness] yaw=$yaw isLeft=$isLeft');

    if (isLeft) {
      if (yaw < -threshold) _leftTurnDone = true;
      return (
        progress: _leftTurnDone ? 1.0 : ((-yaw) / threshold).clamp(0.0, 1.0),
        completed: _leftTurnDone,
        instruction: _leftTurnDone
            ? 'Left turn verified!'
            : 'Turn your head to YOUR left',
      );
    } else {
      if (yaw > threshold) _rightTurnDone = true;
      return (
        progress: _rightTurnDone ? 1.0 : (yaw / threshold).clamp(0.0, 1.0),
        completed: _rightTurnDone,
        instruction: _rightTurnDone
            ? 'Right turn verified!'
            : 'Turn your head to YOUR right',
      );
    }
  }

  ({double progress, bool completed, String instruction}) _processSmile(
    Face face,
  ) {
    final smileProb = face.smilingProbability ?? 0.0;
    // FIX: removed the null-bypass — if smileProb is null we should NOT
    // auto-pass. Require an actual detected smile.
    if (smileProb > 0.65) _smileDone = true;
    return (
      progress: _smileDone ? 1.0 : smileProb.clamp(0.0, 1.0),
      completed: _smileDone,
      instruction: _smileDone
          ? 'Smile verified!'
          : 'Please smile at the camera',
    );
  }

  bool runFullLivenessSequence(
    List<Face> faces,
    List<LivenessChallenge> challenges,
  ) {
    if (faces.isEmpty) return false;
    return challenges.every((c) {
      startChallenge(c);
      final result = processFrame(faces.first);
      return result.completed;
    });
  }
}
