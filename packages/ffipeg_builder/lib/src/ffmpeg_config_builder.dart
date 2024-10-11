import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:ffipeg/ffipeg.dart';
import 'package:ffipeg_builder/src/constants.dart';
import 'package:ffipeg_builder/src/version_spec.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as path;

import 'dart_object_extension.dart';

/// Fast-running builder to generate the configuration JSON for FfiGen specific to FFmpeg.
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
    final outputId = buildStep.inputId.changeExtension(configExtension);

    final annotation = ffmpegGenAnnotation.firstAnnotationOf(library);
    if (annotation == null) {
      // Dart build system insists on being run twice to clean up output files from
      // multi-step builds, so let's be nice to the user and not make them re-run it.
      final dartOutputId = buildStep.inputId.changeExtension(outputExtension);
      final file = File(dartOutputId.path);
      if (await file.exists()) {
        log.info('Annotation removed; deleting ${dartOutputId.path}...');
        await file.delete();
      }
      return;
    }

    final versionSpec =
        VersionSpecifier.parse(annotation.getStringValue('versionSpec'));
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

    final (:String parentPath, :Set<String> headers) =
        await _searchForFFmpegHeaders(
      versionSpec: versionSpec,
      headerPaths: headerPaths,
      libraries: libraries,
      excludeHeaders: excludeHeaders,
    );

    final configMap = <String, dynamic>{
      'silence-enum-warning': true,
      'preamble': '''
        // ignore_for_file: type=lint, doc_directive_unknown, unused_field, unused_element
      ''',
      'llvm-path': llvmPaths.toList(),
      'name': className,
      'compiler-opts': ['-I$parentPath'],
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

    log.info('Writing config to $outputId');

    await buildStep.writeAsString(outputId, data);
  }

  Map<String, dynamic> _includeExclude(FFIncludeExclude includeExclude) {
    return switch (includeExclude) {
      FFInclude include => {'include': include.include.toList()},
      FFExclude exclude => {'exclude': exclude.exclude.toList()},
    };
  }

  /// Searches for FFmpeg headers in the provided headerPaths.
  /// Returns a tuple of: (String parentPath, list of all *.h file paths
  /// found within the `lib*` subdirectories.)
  Future<({String parentPath, Set<String> headers})> _searchForFFmpegHeaders({
    required VersionSpecifier? versionSpec,
    required Set<String> headerPaths,
    required Set<FFmpegLibrary> libraries,
    required Set<String> excludeHeaders,
  }) async {
    if (headerPaths.isEmpty) {
      final packageUri =
          await Isolate.resolvePackageUri(Uri.parse('package:ffipeg_builder/'));
      final defaultSearchPath =
          path.join(path.dirname(path.fromUri(packageUri)), 'ffmpeg-headers');
      headerPaths.add(defaultSearchPath);
    }

    String? versionMismatchError;
    void versionMismatch(String message) {
      versionMismatchError = message;
      log.warning(message);
    }

    outerLoop:
    for (final headerPath in headerPaths) {
      if (Directory(headerPath).existsSync()) {
        final headers = <String>{};

        String? parentPath;
        bool versionVerified = false;

        // Find headers for each FFmpeg library
        for (final lib in libraries) {
          // Search recursively for the `lib*` directories.
          final libGlob = Glob('$headerPath/**/${lib.dir}');
          // Take the first of:
          // - the `current` directory, if it exists
          // - the first directory when sorted in reverse order (highest version first)
          final libDirs = libGlob.listSync().whereType<Directory>().toList()
            ..sort((a, b) => b.path.compareTo(a.path));

          if (libDirs.isEmpty) {
            continue outerLoop;
          }

          if (!versionVerified && versionSpec != null) {
            // Glob for ffversion.h file in the same directory as libDirs
            final versionGlob =
                Glob('${libDirs.first.parent.path}/libavutil/ffversion.h');
            final versionFiles =
                versionGlob.listSync().whereType<File>().toList();

            if (versionFiles.isEmpty) {
              versionMismatch(
                  'FFmpeg version header not found in ${libDirs.first.parent.path}');
              continue outerLoop;
            }

            // Parse ffversion.h and verify version
            final versionFile = versionFiles.first;
            final versionContent = await versionFile.readAsString();
            final versionMatch = RegExp(r'#define FFMPEG_VERSION\s+"([^"]+)"')
                .firstMatch(versionContent);

            if (versionMatch == null) {
              versionMismatch(
                  'FFmpeg version not found in ${versionFile.path}');
              continue outerLoop;
            }

            final ffmpegVersionString = versionMatch.group(1);
            final ffmpegVersion = Version.parse(ffmpegVersionString!);

            if (!versionSpec.allows(ffmpegVersion)) {
              versionMismatch(
                  'Specified FFmpeg version $versionSpec but found $ffmpegVersion in ${versionFile.path}.');
              continue outerLoop;
            }
            versionVerified = true;
            parentPath = libDirs.first.parent.path;
          }

          final libDir = libDirs
                  .where((d) => d.uri.pathSegments.last == 'current')
                  .firstOrNull ??
              libDirs.firstOrNull;
          if (libDir == null) {
            // We didn't find this library's headers, so bail to the next entry in `headerPaths`.
            continue outerLoop;
          }

          final headerFiles =
              Glob('${libDir.path}/*.h').listSync().whereType<File>();

          if (headerFiles.isEmpty) {
            log.warning('No headers found for ${lib.dir} in ${libDir.path}');
            continue outerLoop;
          }

          parentPath = libDir.parent.path;

          final includedHeaders = headerFiles
              .map((file) => file.path)
              .where((p) => !excludeHeaders.any(p.endsWith));
          headers.addAll(includedHeaders);
        }

        if (headers.isNotEmpty && parentPath != null) {
          return (parentPath: parentPath, headers: headers);
        }
      }
    }

    throw Exception([
      if (versionMismatchError != null)
        'FFmpeg headers were found, but of the wrong version: $versionMismatchError'
      else
        'FFmpeg headers not found in any of the provided search paths: $headerPaths'
    ].join());
  }
}
