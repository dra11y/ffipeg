import 'package:analyzer/dart/constant/value.dart';
import 'package:ffipeg/ffipeg.dart';
import 'package:source_gen/source_gen.dart';

extension DartObjectExtension on DartObject {
  Set<String> getStringSet(String fieldName) =>
      getField(fieldName)!.toSetValue()!.map((e) => e.toStringValue()!).toSet();

  String? getStringValue(String fieldName) =>
      getField(fieldName)!.toStringValue();

  bool? getBoolValue(String fieldName) => getField(fieldName)!.toBoolValue();

  Set<T> getEnumSet<T>(String fieldName, List<T> values) => getField(fieldName)!
      .toSetValue()!
      .map((e) => values[e.getField('index')!.toIntValue()!])
      .toSet();

  FFIncludeExclude getIncludeExclude(String fieldName) {
    final field = getField(fieldName)!;

    if (const TypeChecker.fromRuntime(FFInclude).isExactlyType(field.type!)) {
      return FFInclude(field.getStringSet('include'));
    }

    if (const TypeChecker.fromRuntime(FFExclude).isExactlyType(field.type!)) {
      return FFExclude(field.getStringSet('exclude'));
    }

    if (const TypeChecker.fromRuntime(FFAllowAll).isExactlyType(field.type!)) {
      return const FFAllowAll();
    }

    if (const TypeChecker.fromRuntime(FFDenyAll).isExactlyType(field.type!)) {
      return const FFDenyAll();
    }

    throw UnsupportedError('Unsupported FFIncludeExclude type: $type');
  }
}
