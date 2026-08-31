import 'package:flutter/material.dart';

/// Metadata model for vocabulary dictionaries
class DictInfo {
  final String id;
  final String name;
  final String shortName;
  final String description;
  final String assetPath;
  final int estimatedCount;
  final IconData icon;
  final bool isCustom;
  final String? filePath;
  final DateTime? createdAt;

  const DictInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.description,
    required this.assetPath,
    required this.estimatedCount,
    this.icon = Icons.menu_book_rounded,
    this.isCustom = false,
    this.filePath,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shortName': shortName,
        'description': description,
        'assetPath': assetPath,
        'estimatedCount': estimatedCount,
        'isCustom': isCustom,
        'filePath': filePath,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory DictInfo.fromJson(Map<String, dynamic> json) {
    return DictInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      shortName: json['shortName'] as String? ?? json['name'] as String,
      description: json['description'] as String? ?? '',
      assetPath: json['assetPath'] as String? ?? '',
      estimatedCount: json['estimatedCount'] as int? ?? 0,
      icon: (json['isCustom'] == true)
          ? Icons.folder_special_rounded
          : Icons.menu_book_rounded,
      isCustom: json['isCustom'] as bool? ?? false,
      filePath: json['filePath'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DictInfo && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

