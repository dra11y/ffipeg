import 'dart:ffi';
import 'dart:io';

import 'package:args/args.dart';
import 'package:ffipeg_muxer/ffipeg_muxer.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

ArgParser buildParser() {
  return ArgParser()
    ..addOption(
      'video',
      abbr: 'v',
      valueHelp: 'video_file',
      mandatory: true,
      help: 'Set video input file.',
    )
    ..addOption(
      'audio',
      abbr: 'a',
      valueHelp: 'audio_file',
      mandatory: true,
      help: 'Set audio input file.',
    )
    ..addOption(
      'format',
      abbr: 'f',
      valueHelp: 'FORMAT',
      help: 'Override output format (default: auto-detect by file extension).',
    )
    ..addFlag(
      'overwrite',
      abbr: 'y',
      negatable: false,
      help: 'Overwrite output file.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addOption(
      'log',
      abbr: 'l',
      valueHelp: 'LEVEL',
      allowed: Level.LEVELS.map((l) => l.name.toLowerCase()),
      defaultsTo: Level.SEVERE.name.toLowerCase(),
      help: 'Set log level (verbosity).',
    )
    ..addFlag(
      'version',
      negatable: false,
      help: 'Print the tool version.',
    );
}

const positionalArgs = <String>['output_file'];

String scriptName() {
  final executable = path.split(Platform.executable).last;
  final script = Platform.script.pathSegments.last;
  return executable == script ? script : '$executable $script';
}

void printUsage(ArgParser argParser) {
  print('Usage: ${scriptName()} ${positionalArgs.join(' ')}');
  print(argParser.usage);
  print('\nSet FFMPEG_PATH environment variable to specify path to ffmpeg.');
  print('(If not set, ffmpeg will be searched using the `which` command.)');
}

void main(List<String> arguments) {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);

    // Process the parsed arguments.
    if (results.wasParsed('help')) {
      printUsage(argParser);
      return;
    }
    if (results.wasParsed('version')) {
      print('ffipeg_muxer version: $packageVersion');
      return;
    }
    final logOption = results.option('log');
    final logLevel = Level.LEVELS.firstWhere(
        (l) => l.name.toLowerCase() == logOption,
        orElse: () => Level.SEVERE);

    final overwrite = results.wasParsed('overwrite');

    for (final option in argParser.options.values) {
      if (option.mandatory && !results.wasParsed(option.name)) {
        throw FormatException([
          'Missing required option:',
          if (option.abbr != null) ' -${option.abbr},',
          ' --${option.name}',
          if (option.valueHelp != null) '=${option.valueHelp}',
        ].join(''));
      }
    }

    final videoFile = results.option('video')!;
    final audioFile = results.option('audio')!;
    final format = results.option('format');

    if (results.rest.length < positionalArgs.length) {
      final missingArgs = positionalArgs.sublist(results.rest.length).join(' ');
      throw FormatException(
          'Missing required positional arguments: $missingArgs');
    } else if (results.rest.length > positionalArgs.length) {
      throw FormatException('Too many positional arguments provided.');
    }

    final [outputFile] = results.rest;

    final ffmpegPath = Platform.environment['FFMPEG_PATH'] ??
        Process.runSync('which', ['ffmpeg']).stdout.toString().trim();
    if (ffmpegPath.isEmpty) {
      throw Exception(
          'FFmpeg not found. Please ensure it is in your PATH, or set the FFMPEG_PATH environment variable.');
    }

    Logger.root.level = logLevel;
    Logger.root.onRecord.listen((record) {
      print('${record.level.name}: ${record.message}');
    });

    final muxer = Muxer(DynamicLibrary.open(ffmpegPath));

    final result = muxer.run(
      videoFile: videoFile,
      audioFile: audioFile,
      outputFile: outputFile,
      format: format,
      overwrite: overwrite,
    );

    switch (result) {
      case MuxerOK():
        print('Successfully muxed files to: $outputFile');
        break;
      case MuxerError():
        throw result;
    }
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
    exit(1);
  } on MuxerError catch (e) {
    // Assume the logger has already printed the error, unless level > SEVERE.
    if (Logger.root.level > Level.SEVERE) {
      print('A Muxer error occurred: $e');
    }
    exit(1);
  } catch (e, stack) {
    print('An error occurred: $e\n$stack');
    exit(1);
  }
}
