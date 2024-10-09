import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:ffipeg/ffipeg.dart';
import 'package:ffipeg_builder/src/constants.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as path;

import 'dart_object_extension.dart';

class FFmpegConfigBuilder extends Builder {
  final BuilderOptions options;

  FFmpegConfigBuilder(this.options);

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': [configExtension]
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) {
      return;
    }

    final library = await buildStep.resolver.libraryFor(buildStep.inputId);
    final annotation = ffmpegGenAnnotation.firstAnnotationOf(library);
    if (annotation == null) {
      return;
    }

    final headerPaths = annotation.getStringList('headerPaths');
    final llvmPaths = annotation.getStringList('llvmPaths');
    final libraries = annotation.getEnumList('libraries', FFmpegLibrary.values);
    final excludeAllByDefault = annotation.getBoolValue('excludeAllByDefault')!;
    final functions = annotation.getIncludeExclude('functions');
    final structs = annotation.getIncludeExclude('structs');
    final enums = annotation.getIncludeExclude('enums');
    final globals = annotation.getIncludeExclude('globals');
    final typedefs = annotation.getIncludeExclude('typedefs');
    final className = annotation.getStringValue('className')!;
    final excludeHeaders = annotation.getStringList('excludeHeaders');

    final (includePath, headers) =
        await _searchForFFmpegHeaders(headerPaths, libraries, excludeHeaders);

    final configMap = <String, dynamic>{
      'silence-enum-warning': true,
      'preamble': '''
        // ignore_for_file: type=lint, doc_directive_unknown, unused_field, unused_element
      ''',
      'llvm-path': llvmPaths,
      'name': className,
      'compiler-opts': ['-I$includePath'],
      'headers': {
        'entry-points': headers,
      },
      'exclude-all-by-default': excludeAllByDefault,
      'functions': _includeExclude(functions),
      'structs': _includeExclude(structs),
      'enums': _includeExclude(enums),
      'globals': _includeExclude(globals),
      'typedefs': _includeExclude(typedefs),
    };

    final data = json.encode(configMap);

    final outputId = buildStep.inputId.changeExtension(configExtension);
    await buildStep.writeAsString(outputId, data);
  }

  Map<String, dynamic> _includeExclude(FFIncludeExclude includeExclude) {
    return switch (includeExclude) {
      FFInclude include => {'include': include.include},
      FFExclude exclude => {'exclude': exclude.exclude},
    };
  }

  /// Searches for FFmpeg headers in the provided headerPaths.
  /// Returns a list of all *.h file paths found within the `lib*` subdirectories.
  Future<(String, List<String>)> _searchForFFmpegHeaders(
    List<String> headerPaths,
    List<FFmpegLibrary> libraries,
    List<String> excludeHeaders,
  ) async {
    if (headerPaths.isEmpty) {
      final packageUri =
          await Isolate.resolvePackageUri(Uri.parse('package:ffipeg_builder/'));
      final defaultSearchPath = path.join(
          path.dirname(path.fromUri(packageUri)), 'ffmpeg-headers/current');
      headerPaths.add(defaultSearchPath);
    }

    for (final headerPath in headerPaths) {
      if (Directory(headerPath).existsSync()) {
        final foundHeaders = <String>[];

        // Find headers for each FFmpeg library
        for (final lib in libraries) {
          final libDir = '$headerPath/${lib.dir}';

          if (Directory(libDir).existsSync()) {
            final headerFiles =
                Glob('$libDir/*.h').listSync().whereType<File>();

            if (headerFiles.isNotEmpty) {
              foundHeaders.addAll(headerFiles
                  .map((file) => file.path)
                  .where((p) => !excludeHeaders.any(p.endsWith)));
            }
          }
        }

        if (foundHeaders.isNotEmpty) {
          return (headerPath, foundHeaders);
        }
      }
    }

    throw Exception(
        'FFmpeg headers not found in any of the provided search paths: $headerPaths');
  }
}
