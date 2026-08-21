import 'dart:convert';
import 'package:flutter/material.dart';

class MonitoringEvent {
  MonitoringEvent({
    required this.id,
    required this.timestamp,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.colorHex,
    required this.iconCode,
  });

  factory MonitoringEvent.fromJson(Map<String, dynamic> json) {
    return MonitoringEvent(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      category: json['category'] as String,
      colorHex: json['colorHex'] as int,
      iconCode: json['iconCode'] as int,
    );
  }

  final String id;
  final DateTime timestamp;
  final String title;
  final String subtitle;
  final String category;
  final int colorHex;
  final int iconCode;

  Color get color => Color(colorHex);
  IconData get icon => IconData(iconCode, fontFamily: 'MaterialIcons');

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'title': title,
        'subtitle': subtitle,
        'category': category,
        'colorHex': colorHex,
        'iconCode': iconCode,
      };

  @override
  String toString() => jsonEncode(toJson());
}
