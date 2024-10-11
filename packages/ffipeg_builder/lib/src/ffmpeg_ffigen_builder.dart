import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:ffigen/ffigen.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'constants.dart';

/// Slow-running builder to run FfiGen on the generated config for FFmpeg.
/// We run FfiGen() in a separate isolate to avoid Logger.root conflicts.
class FFmpegFfiGenBuilder extends Builder {
  final BuilderOptions options;

  FFmpegFfiGenBuilder(this.options);

  @override
  Map<String, List<String>> get buildExtensions => const {
        configExtension: [outputExtension]
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    log.info('Running FFmpegFfiGenBuilder on ${buildStep.inputId}');
    final data = await buildStep.readAsString(buildStep.inputId);
    final Map<String, dynamic> configMap;

    try {
      configMap = json.decode(data);
    } catch (e) {
      log.severe('Failed to decode JSON data: $data');
      rethrow;
    }

    final tempDir = await Directory.systemTemp.createTemp('ffipeg_builder');
    final tempOutputFile = File(path.join(tempDir.path,
        'ffigen_output_${DateTime.now().millisecondsSinceEpoch}.dart'));

    configMap['description'] = 'FFmpeg bindings generated using ffipeg';
    configMap['ignore-source-errors'] = true;
    configMap['output'] = {
      'bindings': tempOutputFile.path,
    };

    final packageConfig = await buildStep.packageConfig;

    final config = YamlConfig.fromYaml(YamlMap.wrap(configMap),
        packageConfig: packageConfig);

    final result = await _runFfiGen(config);
    switch (result) {
      case FfiGenOK ok:
        final outputId = buildStep.inputId.changeExtension('.dart');
        await buildStep.writeAsString(outputId, ok.generatedContent);
        await tempDir.delete(recursive: true);
      case FfiGenError error:
        throw error;
    }
  }
}

/// Runs FfiGen in a separate isolate to avoid logging conflicts and returns the generated content.
Future<FfiGenResult> _runFfiGen(YamlConfig config) async {
  final receivePort = ReceivePort();
  await Isolate.spawn(_ffiGenIsolate, [receivePort.sendPort, config]);
  return await receivePort.first;
}

sealed class FfiGenResult {
  const FfiGenResult();
}

final class FfiGenOK extends FfiGenResult {
  const FfiGenOK(this.generatedContent);

  final String generatedContent;
}

final class FfiGenError extends FfiGenResult implements Exception {
  const FfiGenError(this.errors);

  final List<String> errors;

  @override
  String toString() => '''
FfiGenError: The following errors occurred running FfiGen():
${errors.map((e) => e.startsWith(' ') ? e : '\n-   $e').join('\n')}
''';
}

/// The entry point for the isolate running FfiGen.
void _ffiGenIsolate(List<dynamic> args) async {
  final sendPort = args[0] as SendPort;
  final config = args[1] as YamlConfig;
  final ffiGen = FfiGen();
  final List<String> errors = [];
  Logger.root
    ..clearListeners()
    ..onRecord.listen((record) {
      if (record.level >= Level.SEVERE ||
          (record.level == Level.WARNING &&
              record.message.contains('errors in source files'))) {
        errors.add(record.message);
      }
    });
  ffiGen.run(config);
  final result = errors.isEmpty
      ? FfiGenOK(await File(config.output.toFilePath()).readAsString())
      : FfiGenError(errors);
  sendPort.send(result);
}
