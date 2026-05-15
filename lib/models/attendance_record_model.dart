class AttendanceRecordModel {
  final String id;
  final String sessionId;
  final String status;
  final double? matchConfidence;
  final DateTime markedAt;
  final String? subjectName;
  final String? className;
  final String? rejectionReason;

  const AttendanceRecordModel({
    required this.id,
    required this.sessionId,
    required this.status,
    this.matchConfidence,
    required this.markedAt,
    this.subjectName,
    this.className,
    this.rejectionReason,
  });

  factory AttendanceRecordModel.fromJson(Map<String, dynamic> json) {
    return AttendanceRecordModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      status: json['status'] as String,
      matchConfidence: (json['match_confidence'] as num?)?.toDouble(),
      markedAt: DateTime.parse(json['marked_at'] as String),
      subjectName: json['subject_name'] as String?,
      className: json['class_name'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }
}
