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
    print('BUILDSTEP INPUT ID: ${buildStep.inputId}');
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) {
      return;
    }

    final library = await buildStep.resolver.libraryFor(buildStep.inputId);
    final outputId = buildStep.inputId.changeExtension(configExtension);

    final annotation = ffmpegGenAnnotation.firstAnnotationOf(library);
    if (annotation == null) {
      // Dart build system insists on being run twice to clean up output files from
      // multi-step builds, so let's be nice to the user and not make them re-run it.
      final dartOutputId = buildStep.inputId.changeExtension(outputExtension);
      final file = File(dartOutputId.path);
      if (await file.exists()) {
        print('Annotation removed; deleting ${dartOutputId.path}...');
        await file.delete();
      }
      return;
    }

    final headerPaths = annotation.getStringSet('headerPaths');
    final llvmPaths = annotation.getStringSet('llvmPaths');
    final libraries = annotation.getEnumSet('libraries', FFmpegLibrary.values);
    final excludeAllByDefault = annotation.getBoolValue('excludeAllByDefault')!;
    final functions = annotation.getIncludeExclude('functions');
    final structs = annotation.getIncludeExclude('structs');
    final enums = annotation.getIncludeExclude('enums');
    final unnamedEnums = annotation.getIncludeExclude('unnamedEnums');
    final unions = annotation.getIncludeExclude('unions');
    final globals = annotation.getIncludeExclude('globals');
    final macros = annotation.getIncludeExclude('macros');
    final typedefs = annotation.getIncludeExclude('typedefs');
    final className = annotation.getStringValue('className')!;
    final excludeHeaders = annotation.getStringSet('excludeHeaders');

    final (includePath, headers) =
        await _searchForFFmpegHeaders(headerPaths, libraries, excludeHeaders);

    final configMap = <String, dynamic>{
      'silence-enum-warning': true,
      'preamble': '''
        // ignore_for_file: type=lint, doc_directive_unknown, unused_field, unused_element
      ''',
      'llvm-path': llvmPaths.toList(),
      'name': className,
      'compiler-opts': ['-I$includePath'],
      'headers': {
        'entry-points': headers.toList(),
      },
      'exclude-all-by-default': excludeAllByDefault,
      'functions': _includeExclude(functions),
      'structs': _includeExclude(structs),
      'enums': _includeExclude(enums),
      'unnamed-enums': _includeExclude(unnamedEnums),
      'unions': _includeExclude(unions),
      'globals': _includeExclude(globals),
      'macros': _includeExclude(macros),
      'typedefs': _includeExclude(typedefs),
    };

    final data = json.encode(configMap);

    print('WRITE CONFIG TO $outputId');

    await buildStep.writeAsString(outputId, data);
  }

  Map<String, dynamic> _includeExclude(FFIncludeExclude includeExclude) {
    return switch (includeExclude) {
      FFInclude include => {'include': include.include.toList()},
      FFExclude exclude => {'exclude': exclude.exclude.toList()},
    };
  }

  /// Searches for FFmpeg headers in the provided headerPaths.
  /// Returns a list of all *.h file paths found within the `lib*` subdirectories.
  Future<(String, Set<String>)> _searchForFFmpegHeaders(
    Set<String> headerPaths,
    Set<FFmpegLibrary> libraries,
    Set<String> excludeHeaders,
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
        final foundHeaders = <String>{};

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
