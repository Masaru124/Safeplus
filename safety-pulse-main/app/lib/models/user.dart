import 'dart:convert';

/// User model for authentication
class User {
  final String id;
  final String email;
  final String username;
  final bool isActive;
  final DateTime createdAt;

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.isActive,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      username: json['username'] ?? '',
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Create a copy of this user with updated fields
  User copyWith({
    String? id,
    String? email,
    String? username,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Authentication token response from API
class AuthToken {
  final String accessToken;
  final String tokenType;
  final User user;

  AuthToken({
    required this.accessToken,
    this.tokenType = 'bearer',
    required this.user,
  });

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    return AuthToken(
      accessToken: json['access_token'] ?? '',
      tokenType: json['token_type'] ?? 'bearer',
      user: User.fromJson(json['user'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'token_type': tokenType,
      'user': user.toJson(),
    };
  }
}

/// Login request payload
class LoginRequest {
  final String email;
  final String password;

  LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() {
    return {'email': email, 'password': password};
  }
}

/// Registration request payload
class RegisterRequest {
  final String email;
  final String username;
  final String password;

  RegisterRequest({
    required this.email,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {'email': email, 'username': username, 'password': password};
  }
}
