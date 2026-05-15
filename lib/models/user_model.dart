class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String? studentId;

  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.studentId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String? ?? json['full_name'] as String? ?? '',
      role: json['role'] as String,
      studentId: json['studentId'] as String? ?? json['student_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'role': role,
        'studentId': studentId,
      };

  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher';
  bool get isAdmin => role == 'admin';
}
