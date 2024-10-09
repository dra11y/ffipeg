import 'package:analyzer/dart/constant/value.dart';
import 'package:ffipeg/ffipeg.dart';

extension DartObjectExtension on DartObject {
  List<String> getStringList(String fieldName) => getField(fieldName)!
      .toListValue()!
      .map((e) => e.toStringValue()!)
      .toList();

  String? getStringValue(String fieldName) =>
      getField(fieldName)!.toStringValue();

  bool? getBoolValue(String fieldName) => getField(fieldName)!.toBoolValue();

  List<T> getEnumList<T>(String fieldName, List<T> values) =>
      getField(fieldName)!
          .toListValue()!
          .map((e) => values[e.getField('index')!.toIntValue()!])
          .toList();

  FFIncludeExclude getIncludeExclude(String fieldName) {
    final field = getField(fieldName)!;
    final type = field.type!.element!.name;

    switch (type) {
      case 'FFInclude':
        return FFInclude(field.getStringList('include'));
      case 'FFExclude':
        return FFExclude(field.getStringList('exclude'));
      case 'FFIncludeAll':
        return const FFIncludeAll();
      case 'FFExcludeAll':
        return const FFExcludeAll();
      default:
        throw UnsupportedError('Unsupported FFIncludeExclude type: $type');
    }
  }
}
