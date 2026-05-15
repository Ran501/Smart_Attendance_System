class AttendanceSessionModel {
  final String id;
  final String classId;
  final String? subjectId;
  final String status;
  final DateTime startedAt;
  final DateTime endsAt;
  final String? sessionToken;
  final String? qrDataUrl;
  final String? qrPayload;
  final int? presentCount;
  final String? className;
  final String? subjectName;

  const AttendanceSessionModel({
    required this.id,
    required this.classId,
    this.subjectId,
    required this.status,
    required this.startedAt,
    required this.endsAt,
    this.sessionToken,
    this.qrDataUrl,
    this.qrPayload,
    this.presentCount,
    this.className,
    this.subjectName,
  });

  factory AttendanceSessionModel.fromJson(Map<String, dynamic> json) {
    return AttendanceSessionModel(
      id: json['id'] as String? ?? json['sessionId'] as String,
      classId: json['class_id'] as String? ?? json['classId'] as String,
      subjectId: json['subject_id'] as String? ?? json['subjectId'] as String?,
      status: json['status'] as String? ?? 'active',
      startedAt: DateTime.parse(
        json['started_at'] as String? ?? json['startedAt'] as String,
      ),
      endsAt: DateTime.parse(
        json['ends_at'] as String? ?? json['endsAt'] as String,
      ),
      sessionToken: json['session_token'] as String? ?? json['sessionToken'] as String?,
      qrDataUrl: json['qrDataUrl'] as String?,
      qrPayload: json['qrPayload'] as String? ?? json['qr_payload'] as String?,
      presentCount: json['present_count'] as int?,
      className: json['class_name'] as String?,
      subjectName: json['subject_name'] as String?,
    );
  }

  bool get isActive => status == 'active' && DateTime.now().isBefore(endsAt);

  Duration get remaining => endsAt.difference(DateTime.now());
}
