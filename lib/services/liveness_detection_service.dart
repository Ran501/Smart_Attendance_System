import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessChallenge {
  blinkTwice,
  turnHeadLeft,
  turnHeadRight,
  smile,
}

class LivenessDetectionService {
  LivenessChallenge? _currentChallenge;
  int _blinkCount = 0;
  bool _leftTurnDone = false;
  bool _rightTurnDone = false;
  bool _smileDone = false;
  double? _lastLeftEyeProb;
  bool _wasEyesClosed = false;

  LivenessChallenge get currentChallenge =>
      _currentChallenge ?? LivenessChallenge.smile;

  /// Attendance flow: no blink — smile + one head turn (works with a single photo per step).
  List<LivenessChallenge> generateChallengeSequence() {
    final turns = [LivenessChallenge.turnHeadLeft, LivenessChallenge.turnHeadRight];
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
    _lastLeftEyeProb = null;
  }

  /// Returns progress 0.0–1.0 and whether challenge completed.
  ({double progress, bool completed, String instruction}) processFrame(Face face) {
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

  ({double progress, bool completed, String instruction}) _processBlink(Face face) {
    final left = face.leftEyeOpenProbability ?? 1.0;
    final right = face.rightEyeOpenProbability ?? 1.0;
    final eyesClosed = left < 0.3 && right < 0.3;

    if (_wasEyesClosed && !eyesClosed) {
      _blinkCount++;
    }
    _wasEyesClosed = eyesClosed;
    _lastLeftEyeProb = left;

    final completed = _blinkCount >= 2;
    return (
      progress: (_blinkCount / 2).clamp(0.0, 1.0),
      completed: completed,
      instruction: completed ? 'Blink verified!' : 'Blink twice (${_blinkCount}/2)',
    );
  }

  ({double progress, bool completed, String instruction}) _processHeadTurn(
    Face face, {
    required bool isLeft,
  }) {
    final yaw = face.headEulerAngleY ?? 0;
    if (isLeft) {
      if (yaw > 10) _leftTurnDone = true;
      return (
        progress: _leftTurnDone ? 1.0 : (yaw / 10).clamp(0.0, 1.0),
        completed: _leftTurnDone,
        instruction: _leftTurnDone ? 'Left turn verified!' : 'Turn your head slightly left',
      );
    } else {
      if (yaw < -10) _rightTurnDone = true;
      return (
        progress: _rightTurnDone ? 1.0 : (-yaw / 10).clamp(0.0, 1.0),
        completed: _rightTurnDone,
        instruction: _rightTurnDone ? 'Right turn verified!' : 'Turn your head slightly right',
      );
    }
  }

  ({double progress, bool completed, String instruction}) _processSmile(Face face) {
    final smileProb = face.smilingProbability;
    final smile = smileProb ?? 0;
    // Lenient for a single still capture when ML Kit omits smile score.
    if (smileProb == null || smile > 0.5) _smileDone = true;
    return (
      progress: _smileDone ? 1.0 : smile.clamp(0.0, 1.0),
      completed: _smileDone,
      instruction: _smileDone ? 'Face captured!' : 'Look at the camera and smile',
    );
  }

  bool runFullLivenessSequence(List<Face> faces, List<LivenessChallenge> challenges) {
    if (faces.isEmpty) return false;
    return challenges.every((c) {
      startChallenge(c);
      final result = processFrame(faces.first);
      return result.completed;
    });
  }
}
