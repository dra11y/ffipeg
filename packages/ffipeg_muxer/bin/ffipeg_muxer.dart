import 'dart:ffi';
import 'dart:io';

import 'package:args/args.dart';
import 'package:ffipeg_muxer/ffipeg_muxer.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

const String version = '0.0.1';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addFlag(
      'version',
      negatable: false,
      help: 'Print the tool version.',
    );
}

const positionalArgs = <String>[
  'video_file',
  'audio_file',
  'muxed_output_file'
];

String scriptName() {
  final executable = path.split(Platform.executable).last;
  final script = Platform.script.pathSegments.last;
  return executable == script ? script : '$executable $script';
}

void printUsage(ArgParser argParser) {
  print('Usage: ${scriptName()} ${positionalArgs.join(' ')}');
  print(argParser.usage);
}

void main(List<String> arguments) {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    bool verbose = false;

    // Process the parsed arguments.
    if (results.wasParsed('help')) {
      printUsage(argParser);
      return;
    }
    if (results.wasParsed('version')) {
      print('ffipeg_muxer version: $version');
      return;
    }
    if (results.wasParsed('verbose')) {
      verbose = true;
    }

    if (results.rest.length < 3) {
      final missingArgs = positionalArgs.sublist(results.rest.length).join(' ');
      throw FormatException(
          'Missing required positional arguments: $missingArgs');
    } else if (results.rest.length > 3) {
      throw FormatException('Too many positional arguments provided.');
    }

    final [videoFile, audioFile, outputFile] = results.rest;

    final ffmpegPath = Platform.environment['FFMPEG_PATH'] ??
        Process.runSync('which', ['ffmpeg']).stdout.toString().trim();
    if (ffmpegPath.isEmpty) {
      throw Exception(
          'FFmpeg not found. Please ensure it is in your PATH, or set the FFMPEG_PATH environment variable.');
    }

    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      print('${record.level.name}: ${record.message}');
    });

    final muxer = Muxer(DynamicLibrary.open(ffmpegPath));

    final result = muxer.run(
        videoFile: videoFile, audioFile: audioFile, outputFile: outputFile);

    if (result is MuxerOK) {
      print('Successfully muxed files to: ${result.outputFile}');
      return;
    } else {
      throw result;
    }
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
    exit(1);
  } on MuxerError catch (e) {
    print('A Muxer error occurred: $e');
    exit(1);
  } catch (e) {
    print('An error occurred: $e');
    exit(1);
  }
}
