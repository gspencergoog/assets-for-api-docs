// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show stderr, exitCode;

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';
import 'package:snippets/snippets.dart';

const LocalFileSystem filesystem = LocalFileSystem();

final Directory flutterSource = filesystem.directory(
  path.join(
    FlutterInformation.instance.getFlutterRoot().path,
    'packages',
    'flutter',
    'lib',
    'src',
  ),
);

final Directory exampleSource = filesystem.directory(
  path.join(
    FlutterInformation.instance.getFlutterRoot().path,
    'examples',
    'api',
    'lib',
  ),
);

// This uses the standard copyright notice for the Flutter repo, instead of the one
// for this repo, hence the difference in date.
const String _kCopyrightNotice = '''
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.''';

const String _kHelpOption = 'help';
const String _kModeOption = 'mode';
const String _kSourceOption = 'source';
const String _kExampleDirOption = 'example-dir';
const String _kExampleOption = 'example';
const String _kModeExtract = 'extract';
const String _kModeInsert = 'insert';
const String _kModeCompare = 'compare';
const Set<String> _kModes = <String>{_kModeInsert, _kModeExtract, _kModeCompare};

/// Extracts the samples from a source file to the given output directory, and
/// removes them from the original source files, replacing them with a pointer
/// to the new location.
Future<void> main(List<String> argList) async {
  final ArgParser parser = ArgParser();
  parser.addOption(
    _kExampleDirOption,
    defaultsTo: path.join(FlutterInformation.instance.getFlutterRoot().path, 'examples', 'api'),
    help: 'The output path for generated sample applications.',
  );
  parser.addOption(_kModeOption,
      allowed: _kModes,
      allowedHelp: <String, String>{
        _kModeExtract: 'Extract samples from the given --$_kSourceOption files, and place them '
            'into the --$_kExampleDirOption destination',
        _kModeInsert: 'Insert the examples from the given --$_kExampleOption files, and place '
            'them into the original source files that they came from.',
        _kModeCompare:
            'Compares the given examples with the examples in their corresponding source '
                'file, or all of the examples from a given source file with the source file, '
                'and if any relevant sections have changed, exits with a non-zero exit code',
      },
      mandatory: true,
      help: 'Whether to insert, extract, or compare samples from a source file or example file.');
  parser.addMultiOption(
    _kSourceOption,
    help: 'The input Flutter source file containing the sample code to extract. Only valid '
        'when the --$_kModeOption is "$_kModeExtract" or "$_kModeCompare".',
  );
  parser.addMultiOption(
    _kExampleOption,
    help: 'The input Flutter source file containing the sample code to reinsert '
        'into its corresponding source file. Only valid when the --$_kModeOption is '
        '"$_kModeInsert" or "$_kModeCompare"',
  );
  parser.addFlag(
    _kHelpOption,
    defaultsTo: false,
    negatable: false,
    help: 'Prints help documentation for this command',
  );

  final ArgResults args = parser.parse(argList);

  if (args[_kHelpOption] as bool) {
    stderr.writeln(parser.usage);
    exitCode = 0;
    return;
  }

  if ((args[_kSourceOption] as List<String>).isEmpty &&
      (args[_kExampleOption] as List<String>).isEmpty) {
    stderr.writeln(parser.usage);
    errorExit('At least one of --$_kSourceOption or --$_kExampleOption must be specified.');
  }

  if (args[_kExampleDirOption] == null || (args[_kExampleDirOption] as String).isEmpty) {
    stderr.writeln(parser.usage);
    errorExit('The --$_kExampleDirOption option must be specified, and not empty.');
  }

  final List<String> sources = <String>[];
  if ((args[_kSourceOption] as List<String>).isNotEmpty) {
    for (final String sourcePath in args[_kSourceOption] as List<String>) {
      final File source = filesystem.file(sourcePath).absolute;
      if (!source.existsSync()) {
        errorExit('The source file ${source.path} does not exist.');
      }

      if (!path.isWithin(flutterSource.path, source.path)) {
        errorExit('Input file must be under the $flutterSource directory: ${source.path} is not.');
      }
      sources
          .add(path.relative(source.path, from: FlutterInformation.instance.getFlutterRoot().path));
    }
  }

  final List<String> examples = <String>[];
  if ((args[_kExampleOption] as List<String>).isNotEmpty) {
    for (final String examplePath in args[_kExampleOption] as List<String>) {
      final File example = filesystem.file(examplePath).absolute;
      if (!example.existsSync()) {
        errorExit('The example file ${example.path} does not exist.');
      }

      if (!path.isWithin(exampleSource.path, example.path)) {
        errorExit('Input file must be under the $exampleSource directory: ${example.path} is not.');
      }
      examples.add(
          path.relative(example.path, from: FlutterInformation.instance.getFlutterRoot().path));
    }
  }

  final Map<String, Set<String>> sourcesToExamples = mapSourcesToExamples(examples, sources);

  exitCode = 0;
  final String mode = args[_kModeOption] as String;
  try {
    switch (mode) {
      case _kModeExtract:
        if (examples.isNotEmpty) {
          errorExit('--$_kExampleOption can only be specified when the --$_kModeOption is '
              '"$_kModeInsert" or "$_kModeCompare"');
        }
        if (sources.isNotEmpty) {
          await extractFromSources(sources);
        } else {
          errorExit('Must specify at least one --$_kExampleOption with '
              '--$_kModeOption=$_kModeExtract');
        }
        break;
      case _kModeInsert:
        if (sources.isNotEmpty) {
          errorExit('--$_kExampleOption can only be specified when the --$_kModeOption is '
              '"$_kModeExtract" or "$_kModeCompare"');
        }
        if (examples.isNotEmpty) {
          await reinsertIntoSources(sourcesToExamples);
        } else {
          errorExit(
              'Must specify at least one --$_kSourceOption with --$_kModeOption=$_kModeInsert');
        }
        break;
      case _kModeCompare:
        if (examples.isEmpty && sources.isEmpty) {
          errorExit('Must specify at least one of --$_kSourceOption or --$_kExampleOption with '
              '--$_kModeOption=$_kModeCompare');
        }
        if (examples.isNotEmpty) {
          if (await compareExamples(sourcesToExamples) != 0) {
            exitCode = 1;
          }
        }
        if (sources.isNotEmpty) {
          if (await compareSources(sources) != 0) {
            exitCode = 1;
          }
        }
        break;
      default:
        errorExit('Unknown --$_kModeOption argument $mode');
        break;
    }
  } on SnippetException catch (e, s) {
    print('Failed: $e\n$s');
    exitCode = 2;
  } on FileSystemException catch (e, s) {
    print('Failed with file system exception: $e\n$s');
    exitCode = 3;
  } catch (e, s) {
    print('Failed with exception: $e\n$s');
    exitCode = 4;
  }
}

Future<int> compareExamples(Map<String, Set<String>> sourcesToExamples) async {
  return 0;
}

Future<int> compareSources(List<String> sources) async {
  return 0;
}

// Make a map of all the examples given that go into each source file.
Map<String, Set<String>> mapSourcesToExamples(Iterable<String> examples, Iterable<String> sources) {
  final Map<String, Set<String>> sourceToExamples = <String, Set<String>>{};
  for (final String input in examples) {
    final String relativePath = path.relative(
      path.join(FlutterInformation.instance.getFlutterRoot().path, input),
      from: exampleSource.path,
    );
    final File sourceFile =
        filesystem.file('${path.dirname(path.join(flutterSource.path, relativePath))}.dart');
    final String sourceFilePath = path.relative(
      sourceFile.path,
      from: FlutterInformation.instance.getFlutterRoot().path,
    );
    sourceToExamples[sourceFilePath] ??= <String>{};
    sourceToExamples[sourceFilePath]!.add(input);
  }
  return sourceToExamples;
}

Future<void> extractFromSources(List<String> sources) async {
  for (final String input in sources) {
    await extractFromSource(
      filesystem.file(path.join(FlutterInformation.instance.getFlutterRoot().path, input)),
    );
  }
}

Future<void> extractFromSource(File input) async {
  final List<FlutterSampleLiberator> liberators = await createLiberators(input);
  final String srcPath = path.relative(input.path, from: flutterSource.path);
  final String dstPath = path.join(
    FlutterInformation.instance.getFlutterRoot().path,
    'examples',
    'api',
  );

  for (final FlutterSampleLiberator liberator in liberators) {
    final File outputFile = filesystem
        .file(
          path.joinAll(<String>[
            dstPath,
            'lib',
            path.withoutExtension(srcPath), // e.g. material/app_bar
            <String>[
              if (liberator.element.className.isNotEmpty) liberator.element.className.snakeCase,
              liberator.element.name.snakeCase,
              liberator.sample.index.toString(),
              'dart',
            ].join('.'),
          ]),
        )
        .absolute;
    await outputFile.parent.create(recursive: true);
    if (outputFile.existsSync()) {
      errorExit('File $outputFile already exists!');
    }
    if (!filesystem.file(path.join(dstPath, 'pubspec.yaml')).existsSync()) {
      print('Publishing ${outputFile.path}');
      await liberator.extract(overwrite: true, mainDart: outputFile, includeMobile: true);
    } else {
      await outputFile.writeAsString(liberator.sample.output);
    }
    await liberator.reinsertAsReference(outputFile);
    print('${outputFile.path}: ${getSampleStats(liberator.element)}');
  }
}

Future<List<FlutterSampleLiberator>> createLiberators(
  File input, {
  Set<String>? examples,
}) async {
  final Iterable<SourceElement> fileElements = getFileElements(input);
  final SnippetDartdocParser dartdocParser = SnippetDartdocParser(filesystem);
  final SnippetGenerator snippetGenerator = SnippetGenerator();
  dartdocParser.parseFromComments(fileElements);
  dartdocParser.parseAndAddAssumptions(fileElements, input, silent: true);

  final String dstPath = path.join(
    FlutterInformation.instance.getFlutterRoot().path,
    'examples',
    'api',
  );
  final List<FlutterSampleLiberator> liberators = <FlutterSampleLiberator>[];
  for (final SourceElement element in fileElements.where((SourceElement element) {
    return element.sampleCount > 0;
  })) {
    for (final CodeSample sample in element.samples) {
      // Ignore anything else, because those are not full apps.
      if (sample.type != 'dartpad' && sample.type != 'sample') {
        continue;
      }
      if (examples != null && examples.contains(sample.exampleFile!.path)) {
        sample.output = sample.exampleFile!.readAsStringSync();
      } else {
        snippetGenerator.generateCode(
          sample,
          includeAssumptions: false,
          addSectionMarkers: true,
          copyright: _kCopyrightNotice,
        );
      }
      liberators.add(FlutterSampleLiberator(
        element,
        sample,
        mainDart: sample.exampleFile,
        location: filesystem.directory(dstPath),
      ));
    }
  }
  return liberators;
}

Future<void> reinsertIntoSources(Map<String, Set<String>> examplesToSources) async {
  for (final String sourceFile in examplesToSources.keys) {
    await reinsertIntoSource(
      filesystem.file(sourceFile),
      examplesToSources[sourceFile]!,
    );
  }
}

Future<void> reinsertIntoSource(File sourceFile, Set<String> examples) async {
  final List<FlutterSampleLiberator> liberators = await createLiberators(sourceFile, examples: examples);
  for (final FlutterSampleLiberator liberator in liberators) {
    liberator.reinsert();
  }
}
