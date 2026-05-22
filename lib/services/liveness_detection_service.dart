import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessChallenge {
  blinkTwice,
  turnHeadLeft,
  turnHeadRight,
  turnHeadUp,
  turnHeadDown,
  smile,
}

class LivenessDetectionService {
  LivenessChallenge? _currentChallenge;
  int _blinkCount = 0;
  bool _leftTurnDone = false;
  bool _rightTurnDone = false;
  bool _upTurnDone = false;
  bool _downTurnDone = false;
  bool _smileDone = false;
  bool _wasEyesClosed = false;

  /// Registration: smile → look up → look down → right → left.
  static const List<LivenessChallenge> registrationSequence = [
    LivenessChallenge.smile,
    LivenessChallenge.turnHeadUp,
    LivenessChallenge.turnHeadDown,
    LivenessChallenge.turnHeadRight,
    LivenessChallenge.turnHeadLeft,
  ];

  /// Attendance: smile → right → left (no up/down).
  static const List<LivenessChallenge> attendanceSequence = [
    LivenessChallenge.smile,
    LivenessChallenge.turnHeadRight,
    LivenessChallenge.turnHeadLeft,
  ];

  static String labelFor(LivenessChallenge challenge) {
    switch (challenge) {
      case LivenessChallenge.smile:
        return 'Smile';
      case LivenessChallenge.turnHeadUp:
        return 'Look up';
      case LivenessChallenge.turnHeadDown:
        return 'Look down';
      case LivenessChallenge.turnHeadLeft:
        return 'Left';
      case LivenessChallenge.turnHeadRight:
        return 'Right';
      case LivenessChallenge.blinkTwice:
        return 'Blink';
    }
  }

  LivenessChallenge get currentChallenge =>
      _currentChallenge ?? LivenessChallenge.smile;

  void startChallenge(LivenessChallenge challenge) {
    _currentChallenge = challenge;
    _resetProgress();
  }

  void _resetProgress() {
    _blinkCount = 0;
    _leftTurnDone = false;
    _rightTurnDone = false;
    _upTurnDone = false;
    _downTurnDone = false;
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
      case LivenessChallenge.turnHeadUp:
        return _processPitch(face, lookUp: true);
      case LivenessChallenge.turnHeadDown:
        return _processPitch(face, lookUp: false);
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
      instruction: completed ? 'Blink verified!' : 'Blink twice ($_blinkCount/2)',
    );
  }

  ({double progress, bool completed, String instruction}) _processHeadTurn(
    Face face, {
    required bool isLeft,
  }) {
    final yaw = face.headEulerAngleY ?? 0;
    const threshold = 15.0;

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

  ({double progress, bool completed, String instruction}) _processPitch(
    Face face, {
    required bool lookUp,
  }) {
    final pitch = face.headEulerAngleX ?? 0;
    const threshold = 12.0;

    if (lookUp) {
      if (pitch > threshold) _upTurnDone = true;
      return (
        progress: _upTurnDone ? 1.0 : (pitch / threshold).clamp(0.0, 1.0),
        completed: _upTurnDone,
        instruction: _upTurnDone
            ? 'Look up verified!'
            : 'Tilt your head up toward the ceiling',
      );
    } else {
      if (pitch < -threshold) _downTurnDone = true;
      return (
        progress: _downTurnDone ? 1.0 : ((-pitch) / threshold).clamp(0.0, 1.0),
        completed: _downTurnDone,
        instruction: _downTurnDone
            ? 'Look down verified!'
            : 'Tilt your head down slightly',
      );
    }
  }

  ({double progress, bool completed, String instruction}) _processSmile(
    Face face,
  ) {
    final smileProb = face.smilingProbability ?? 0.0;
    if (smileProb > 0.7) _smileDone = true;
    return (
      progress: _smileDone ? 1.0 : smileProb.clamp(0.0, 1.0),
      completed: _smileDone,
      instruction: _smileDone
          ? 'Smile verified!'
          : 'Please smile clearly at the camera',
    );
  }
}
