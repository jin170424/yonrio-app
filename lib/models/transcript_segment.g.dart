// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript_segment.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetTranscriptSegmentCollection on Isar {
  IsarCollection<TranscriptSegment> get transcriptSegments => this.collection();
}

const TranscriptSegmentSchema = CollectionSchema(
  name: r'TranscriptSegment',
  id: 4875653609457479542,
  properties: {
    r'endTimeMs': PropertySchema(
      id: 0,
      name: r'endTimeMs',
      type: IsarType.long,
    ),
    r'searchTokens': PropertySchema(
      id: 1,
      name: r'searchTokens',
      type: IsarType.stringList,
    ),
    r'speaker': PropertySchema(
      id: 2,
      name: r'speaker',
      type: IsarType.string,
    ),
    r'startTimeMs': PropertySchema(
      id: 3,
      name: r'startTimeMs',
      type: IsarType.long,
    ),
    r'text': PropertySchema(
      id: 4,
      name: r'text',
      type: IsarType.string,
    ),
    r'translations': PropertySchema(
      id: 5,
      name: r'translations',
      type: IsarType.objectList,
      target: r'TranslationData',
    )
  },
  estimateSize: _transcriptSegmentEstimateSize,
  serialize: _transcriptSegmentSerialize,
  deserialize: _transcriptSegmentDeserialize,
  deserializeProp: _transcriptSegmentDeserializeProp,
  idName: r'id',
  indexes: {
    r'searchTokens': IndexSchema(
      id: 2062148741461982474,
      name: r'searchTokens',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'searchTokens',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {
    r'recording': LinkSchema(
      id: -8916433243071100242,
      name: r'recording',
      target: r'Recording',
      single: true,
      linkName: r'transcripts',
    )
  },
  embeddedSchemas: {r'TranslationData': TranslationDataSchema},
  getId: _transcriptSegmentGetId,
  getLinks: _transcriptSegmentGetLinks,
  attach: _transcriptSegmentAttach,
  version: '3.1.0+1',
);

int _transcriptSegmentEstimateSize(
  TranscriptSegment object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final list = object.searchTokens;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount += value.length * 3;
        }
      }
    }
  }
  bytesCount += 3 + object.speaker.length * 3;
  bytesCount += 3 + object.text.length * 3;
  {
    final list = object.translations;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        final offsets = allOffsets[TranslationData]!;
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount +=
              TranslationDataSchema.estimateSize(value, offsets, allOffsets);
        }
      }
    }
  }
  return bytesCount;
}

void _transcriptSegmentSerialize(
  TranscriptSegment object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.endTimeMs);
  writer.writeStringList(offsets[1], object.searchTokens);
  writer.writeString(offsets[2], object.speaker);
  writer.writeLong(offsets[3], object.startTimeMs);
  writer.writeString(offsets[4], object.text);
  writer.writeObjectList<TranslationData>(
    offsets[5],
    allOffsets,
    TranslationDataSchema.serialize,
    object.translations,
  );
}

TranscriptSegment _transcriptSegmentDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = TranscriptSegment();
  object.endTimeMs = reader.readLong(offsets[0]);
  object.id = id;
  object.searchTokens = reader.readStringList(offsets[1]);
  object.speaker = reader.readString(offsets[2]);
  object.startTimeMs = reader.readLong(offsets[3]);
  object.text = reader.readString(offsets[4]);
  object.translations = reader.readObjectList<TranslationData>(
    offsets[5],
    TranslationDataSchema.deserialize,
    allOffsets,
    TranslationData(),
  );
  return object;
}

P _transcriptSegmentDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readStringList(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readObjectList<TranslationData>(
        offset,
        TranslationDataSchema.deserialize,
        allOffsets,
        TranslationData(),
      )) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _transcriptSegmentGetId(TranscriptSegment object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _transcriptSegmentGetLinks(
    TranscriptSegment object) {
  return [object.recording];
}

void _transcriptSegmentAttach(
    IsarCollection<dynamic> col, Id id, TranscriptSegment object) {
  object.id = id;
  object.recording
      .attach(col, col.isar.collection<Recording>(), r'recording', id);
}

extension TranscriptSegmentQueryWhereSort
    on QueryBuilder<TranscriptSegment, TranscriptSegment, QWhere> {
  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension TranscriptSegmentQueryWhere
    on QueryBuilder<TranscriptSegment, TranscriptSegment, QWhereClause> {
  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhereClause>
      searchTokensIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'searchTokens',
        value: [null],
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhereClause>
      searchTokensIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'searchTokens',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhereClause>
      searchTokensEqualTo(List<String>? searchTokens) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'searchTokens',
        value: [searchTokens],
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterWhereClause>
      searchTokensNotEqualTo(List<String>? searchTokens) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'searchTokens',
              lower: [],
              upper: [searchTokens],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'searchTokens',
              lower: [searchTokens],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'searchTokens',
              lower: [searchTokens],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'searchTokens',
              lower: [],
              upper: [searchTokens],
              includeUpper: false,
            ));
      }
    });
  }
}

extension TranscriptSegmentQueryFilter
    on QueryBuilder<TranscriptSegment, TranscriptSegment, QFilterCondition> {
  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      endTimeMsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endTimeMs',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      endTimeMsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endTimeMs',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      endTimeMsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endTimeMs',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      endTimeMsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endTimeMs',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'searchTokens',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'searchTokens',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'searchTokens',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'searchTokens',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'searchTokens',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'searchTokens',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'searchTokens',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'searchTokens',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'searchTokens',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'searchTokens',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'searchTokens',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'searchTokens',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'searchTokens',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'searchTokens',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'searchTokens',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'searchTokens',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'searchTokens',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      searchTokensLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'searchTokens',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'speaker',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'speaker',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'speaker',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'speaker',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'speaker',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'speaker',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'speaker',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'speaker',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'speaker',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      speakerIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'speaker',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      startTimeMsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startTimeMs',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      startTimeMsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'startTimeMs',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      startTimeMsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'startTimeMs',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      startTimeMsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'startTimeMs',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'text',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'text',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'text',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      textIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'text',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      translationsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'translations',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      translationsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'translations',
      ));
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      translationsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'translations',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      translationsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'translations',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      translationsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'translations',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      translationsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'translations',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      translationsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'translations',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      translationsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'translations',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }
}

extension TranscriptSegmentQueryObject
    on QueryBuilder<TranscriptSegment, TranscriptSegment, QFilterCondition> {
  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      translationsElement(FilterQuery<TranslationData> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'translations');
    });
  }
}

extension TranscriptSegmentQueryLinks
    on QueryBuilder<TranscriptSegment, TranscriptSegment, QFilterCondition> {
  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      recording(FilterQuery<Recording> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'recording');
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterFilterCondition>
      recordingIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'recording', 0, true, 0, true);
    });
  }
}

extension TranscriptSegmentQuerySortBy
    on QueryBuilder<TranscriptSegment, TranscriptSegment, QSortBy> {
  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      sortByEndTimeMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTimeMs', Sort.asc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      sortByEndTimeMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTimeMs', Sort.desc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      sortBySpeaker() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'speaker', Sort.asc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      sortBySpeakerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'speaker', Sort.desc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      sortByStartTimeMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTimeMs', Sort.asc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      sortByStartTimeMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTimeMs', Sort.desc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      sortByText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.asc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      sortByTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.desc);
    });
  }
}

extension TranscriptSegmentQuerySortThenBy
    on QueryBuilder<TranscriptSegment, TranscriptSegment, QSortThenBy> {
  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      thenByEndTimeMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTimeMs', Sort.asc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      thenByEndTimeMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTimeMs', Sort.desc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      thenBySpeaker() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'speaker', Sort.asc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      thenBySpeakerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'speaker', Sort.desc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      thenByStartTimeMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTimeMs', Sort.asc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      thenByStartTimeMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTimeMs', Sort.desc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      thenByText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.asc);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QAfterSortBy>
      thenByTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'text', Sort.desc);
    });
  }
}

extension TranscriptSegmentQueryWhereDistinct
    on QueryBuilder<TranscriptSegment, TranscriptSegment, QDistinct> {
  QueryBuilder<TranscriptSegment, TranscriptSegment, QDistinct>
      distinctByEndTimeMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endTimeMs');
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QDistinct>
      distinctBySearchTokens() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'searchTokens');
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QDistinct>
      distinctBySpeaker({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'speaker', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QDistinct>
      distinctByStartTimeMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'startTimeMs');
    });
  }

  QueryBuilder<TranscriptSegment, TranscriptSegment, QDistinct> distinctByText(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'text', caseSensitive: caseSensitive);
    });
  }
}

extension TranscriptSegmentQueryProperty
    on QueryBuilder<TranscriptSegment, TranscriptSegment, QQueryProperty> {
  QueryBuilder<TranscriptSegment, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<TranscriptSegment, int, QQueryOperations> endTimeMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endTimeMs');
    });
  }

  QueryBuilder<TranscriptSegment, List<String>?, QQueryOperations>
      searchTokensProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'searchTokens');
    });
  }

  QueryBuilder<TranscriptSegment, String, QQueryOperations> speakerProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'speaker');
    });
  }

  QueryBuilder<TranscriptSegment, int, QQueryOperations> startTimeMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'startTimeMs');
    });
  }

  QueryBuilder<TranscriptSegment, String, QQueryOperations> textProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'text');
    });
  }

  QueryBuilder<TranscriptSegment, List<TranslationData>?, QQueryOperations>
      translationsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'translations');
    });
  }
}

// **************************************************************************
// IsarEmbeddedGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

const TranslationDataSchema = Schema(
  name: r'TranslationData',
  id: -5772577600259628940,
  properties: {
    r'langCode': PropertySchema(
      id: 0,
      name: r'langCode',
      type: IsarType.string,
    ),
    r'text': PropertySchema(
      id: 1,
      name: r'text',
      type: IsarType.string,
    )
  },
  estimateSize: _translationDataEstimateSize,
  serialize: _translationDataSerialize,
  deserialize: _translationDataDeserialize,
  deserializeProp: _translationDataDeserializeProp,
);

int _translationDataEstimateSize(
  TranslationData object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.langCode;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.text;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _translationDataSerialize(
  TranslationData object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.langCode);
  writer.writeString(offsets[1], object.text);
}

TranslationData _translationDataDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = TranslationData();
  object.langCode = reader.readStringOrNull(offsets[0]);
  object.text = reader.readStringOrNull(offsets[1]);
  return object;
}

P _translationDataDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension TranslationDataQueryFilter
    on QueryBuilder<TranslationData, TranslationData, QFilterCondition> {
  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'langCode',
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'langCode',
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'langCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'langCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'langCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'langCode',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'langCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'langCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'langCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'langCode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'langCode',
        value: '',
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      langCodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'langCode',
        value: '',
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'text',
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'text',
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'text',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'text',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'text',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'text',
        value: '',
      ));
    });
  }

  QueryBuilder<TranslationData, TranslationData, QAfterFilterCondition>
      textIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'text',
        value: '',
      ));
    });
  }
}

extension TranslationDataQueryObject
    on QueryBuilder<TranslationData, TranslationData, QFilterCondition> {}
