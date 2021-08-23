// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show stderr, exit;

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';
import 'package:snippets/snippets.dart';

const LocalFileSystem filesystem = LocalFileSystem();
FlutterInformation flutterInformation = FlutterInformation();

final Directory flutterSource = filesystem.directory(
  path.join(
    flutterInformation.getFlutterRoot().path,
    'packages',
    'flutter',
    'lib',
    'src',
  ),
);

final Directory exampleSource = filesystem.directory(
  path.join(
    flutterInformation.getFlutterRoot().path,
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
const String _kSourceOption = 'source';
const String _kExampleDirOption = 'example-dir';
const String _kExampleOption = 'example';
const String _kCompareOption = 'compare';

/// Extracts the samples from a source file to the given output directory, and
/// removes them from the original source files, replacing them with a pointer
/// to the new location.
Future<void> main(List<String> argList) async {
  final ArgParser parser = ArgParser();
  parser.addOption(
    _kExampleDirOption,
    defaultsTo: path.join(flutterInformation.getFlutterRoot().path, 'examples', 'api'),
    help: 'The output path for generated sample applications.',
  );
  parser.addMultiOption(
    _kSourceOption,
    help: 'The input Flutter source file containing the sample code to extract.',
  );
  parser.addMultiOption(
    _kExampleOption,
    help: 'The input Flutter source file containing the sample code to reinsert '
        'into its corresponding source file.',
  );
  parser.addFlag(
    _kCompareOption,
    help: 'Compares the given examples with the examples in their corresponding source '
        'file, or all of the examples from a given source file with the source file, '
        'and if any relevant sections have changed, exits with a non-zero exit code',
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
    exit(0);
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
      sources.add(path.relative(source.path, from: flutterInformation.getFlutterRoot().path));
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
      examples.add(path.relative(example.path, from: flutterInformation.getFlutterRoot().path));
    }
  }

  final Map<String, Set<String>> examplesToSources = mapExamplesToSources(examples, sources);

  // Verify that we didn't try and re-insert a sample into a source file we're
  // extracting from.
  if (examples.isNotEmpty && sources.isNotEmpty) {
    final Set<String> forbiddenSources =
        sources.toSet().intersection(examplesToSources.keys.toSet());
    Set<String> forbiddenSamples = <String>{};
    if (forbiddenSources.isNotEmpty) {
      forbiddenSamples = <String>{
        for (final String file in forbiddenSources) ...examplesToSources[file]!,
      };
      forbiddenSamples = forbiddenSamples.intersection(examples.toSet());
    }
    if (forbiddenSamples.isNotEmpty) {
      errorExit('Sample${forbiddenSamples.length > 1 ? 's' : ''} supplied with --$_kExampleOption '
          '(${forbiddenSamples.join(', ')}) come${forbiddenSamples.length > 1 ? '' : 's'} from '
          "${forbiddenSources.length > 1 ? 'source files' : 'a source file'} supplied with "
          "--$_kSourceOption (${forbiddenSources.join(', ')}). Can't reinsert a sample into a "
          'source file that is also being extracted from.');
    }
  }

  if (sources.isNotEmpty) {
    extractFromSources(sources);
  }
  if (examples.isNotEmpty) {
    reinsertIntoSources(examplesToSources);
  }
  exit(0);
}

// Make a map of all the examples that go into each file.
Map<String, Set<String>> mapExamplesToSources(Iterable<String> examples, Iterable<String> sources) {
  final Map<String, Set<String>> sourceToSamples = <String, Set<String>>{};
  for (final String input in examples) {
    final String relativePath = path.relative(
      path.join(flutterInformation.getFlutterRoot().path, input),
      from: exampleSource.path,
    );
    final File sourceFile =
        filesystem.file('${path.dirname(path.join(flutterSource.path, relativePath))}.dart');
    final String sourceFilePath = path.relative(
      sourceFile.path,
      from: flutterInformation.getFlutterRoot().path,
    );
    sourceToSamples[sourceFilePath] ??= <String>{};
    sourceToSamples[sourceFilePath]!.add(input);
  }
  return sourceToSamples;
}

Future<void> extractFromSources(
  List<String> sources, {
  FlutterInformation? information,
}) async {
  information ??= flutterInformation;
  for (final String input in sources) {
    try {
      await extractFromSource(
        filesystem.file(path.join(flutterInformation.getFlutterRoot().path, input)),
        information: information,
      );
    } on SnippetException catch (e, s) {
      print('Failed: $e\n$s');
      exit(1);
    } on FileSystemException catch (e, s) {
      print('Failed with file system exception: $e\n$s');
      exit(2);
    } catch (e, s) {
      print('Failed with exception: $e\n$s');
      exit(2);
    }
  }
}

Future<void> extractFromSource(
  File input, {
  FlutterInformation? information,
}) async {
  information ??= flutterInformation;
  final List<FlutterSampleLiberator> liberators =
      await createLiberators(input, information: information);
  final String srcPath = path.relative(input.path, from: flutterSource.path);
  final String dstPath = path.join(
    information.getFlutterRoot().path,
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
  FlutterInformation? information,
}) async {
  information ??= flutterInformation;
  final Iterable<SourceElement> fileElements = getFileElements(input);
  final SnippetDartdocParser dartdocParser = SnippetDartdocParser(filesystem);
  final SnippetGenerator snippetGenerator = SnippetGenerator();
  dartdocParser.parseFromComments(fileElements);
  dartdocParser.parseAndAddAssumptions(fileElements, input, silent: true);

  final String dstPath = path.join(
    information.getFlutterRoot().path,
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
      snippetGenerator.generateCode(
        sample,
        includeAssumptions: false,
        addSectionMarkers: true,
        copyright: _kCopyrightNotice,
      );
      liberators.add(FlutterSampleLiberator(
        element,
        sample,
        location: filesystem.directory(dstPath),
      ));
    }
  }
  return liberators;
}

Future<void> reinsertIntoSources(
  Map<String, Set<String>> examplesToSources, {
  FlutterInformation? information,
}) async {
  information ??= flutterInformation;

  for (final String sourceFile in examplesToSources.keys) {
    try {
      await reinsertIntoSource(
        filesystem.file(sourceFile),
        examplesToSources[sourceFile]!.map<File>((String example) {
          return filesystem.file(path.join(flutterInformation.getFlutterRoot().path, example));
        }).toSet(),
      );
    } on SnippetException catch (e, s) {
      print('Failed: $e\n$s');
      exit(1);
    } on FileSystemException catch (e, s) {
      print('Failed with file system exception: $e\n$s');
      exit(2);
    } catch (e, s) {
      print('Failed with exception: $e\n$s');
      exit(2);
    }
  }
}

class ExampleInformation {
  const ExampleInformation(this.element, this.templateName);

  final SourceElement element;
  final String templateName;
}

Future<void> reinsertIntoSource(File sourceFile, Set<File> examples) async {
  final Iterable<SourceElement> fileElements = getFileElements(sourceFile);
  final Map<File, ExampleInformation> exampleElements = <File, ExampleInformation>{};
  // Collect the SourceElements that match the samples they contain, so we have an actual
  // destination for the sample code.
  for (final File example in examples) {
    final RegExp symbolRegex =
        RegExp(r'^// Flutter code sample for (?<symbol>.*)\s*$', multiLine: true);
    final RegExp templateRegex = RegExp(r'^// Template: (?<template>.*)\s*$', multiLine: true);
    final String exampleMain = example.readAsStringSync();
    final RegExpMatch? match = symbolRegex.firstMatch(exampleMain);
    final RegExpMatch? templateMatch = templateRegex.firstMatch(exampleMain);
    late String symbolName;
    SourceElement? foundElement;
    String? foundTemplate;
    if (match != null) {
      symbolName = match.namedGroup('symbol')!;
      print('Re-inserting $symbolName into ${sourceFile.path}');
    } else {
      throw SnippetException('Unable to find symbol name in ${example.path}');
    }
    foundTemplate = templateMatch?.namedGroup('template');
    print('Found template $foundTemplate');
    for (final SourceElement element in fileElements) {
      if (element.elementName == symbolName) {
        foundElement = element;
        break;
      }
    }
    if (foundElement == null) {
      throw SnippetException(
          'Unable to find symbol $symbolName (from ${example.path}) in ${sourceFile.path}');
    }
    if (foundTemplate == null) {
      throw SnippetException('Unable to find template name in ${example.path}');
    }
    exampleElements[example] = ExampleInformation(foundElement, foundTemplate);
  }

  for (final File example in exampleElements.keys) {
    CodeSample sample = CodeSample();
  }
}
