import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:voice_app/models/recording.dart';

part 'transcript_segment.g.dart';

@collection
class TranscriptSegment {
  Id id = Isar.autoIncrement;

  late String speaker;

  late String text;

  @Index()
  List<String>? searchTokens;

  late int startTimeMs;
  late int endTimeMs;

  List<TranslationData>? translations;

  @Backlink(to: 'transcripts')
  final recording = IsarLink<Recording>();
}

@embedded
class TranslationData {
  String? langCode;
  String? text;
}