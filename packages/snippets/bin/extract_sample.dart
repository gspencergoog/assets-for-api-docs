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

const String _kCopyrightNotice = '''
// Copyright 2013 The Flutter Authors. All rights reserved.
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
  final FlutterInformation flutterInformation = FlutterInformation();
  final ArgParser parser = ArgParser();
  parser.addOption(
    _kExampleDirOption,
    defaultsTo: path.join(
        flutterInformation.getFlutterRoot().absolute.path, 'examples', 'api'),
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
    help:
    'Compares the given examples with the examples in their corresponding source '
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
      (args[_kExampleOption]  as List<String>).isEmpty) {
    stderr.writeln(parser.usage);
    errorExit('At least one of --$_kSourceOption or --$_kExampleOption must be specified.');
  }

  if (args[_kExampleDirOption] == null ||
      (args[_kExampleDirOption] as String).isEmpty) {
    stderr.writeln(parser.usage);
    errorExit('The --$_kExampleDirOption option must be specified, and not empty.');
  }

  final Directory flutterSource = filesystem.directory(path.join(
    flutterInformation.getFlutterRoot().absolute.path,
    'packages',
    'flutter',
    'lib',
    'src',
  ),);
  final List<File> sources = <File>[];
  if ((args[_kSourceOption] as List<String>).isNotEmpty) {
    for (final String sourcePath in args[_kSourceOption] as List<String>) {
      final File source = filesystem.file(sourcePath);
      if (!source.existsSync()) {
        errorExit('The source file ${source.absolute.path} does not exist.');
      }

      if (!path.isWithin(flutterSource.absolute.path, source.absolute.path)) {
        errorExit(
            'Input file must be under the $flutterSource directory: ${source.absolute.path} is not.');
      }
      sources.add(source);
    }
  }

  final Directory exampleSource = filesystem.directory(path.join(
    flutterInformation.getFlutterRoot().absolute.path,
    'examples',
    'api',
    'lib',
  ),);
  final List<File> examples = <File>[];
  if ((args[_kExampleOption] as List<String>).isNotEmpty) {
    for (final String examplePath in args[_kExampleOption] as List<String>) {
      final File example = filesystem.file(examplePath);
      if (!example.existsSync()) {
        errorExit('The example file ${example.absolute.path} does not exist.');
      }

      if (!path.isWithin(exampleSource.absolute.path, example.absolute.path)) {
        errorExit(
            'Input file must be under the $exampleSource directory: ${example.absolute.path} is not.');
      }
      examples.add(example);
    }
  }

  generateSources(sources, flutterInformation, flutterSource);
  exit(0);
}

Future<void> generateSources(List<File> sources, FlutterInformation flutterInformation, Directory flutterSource) async {
  for (final File input in sources) {
  try {
    final Iterable<SourceElement> fileElements = getFileElements(input);
    final SnippetDartdocParser dartdocParser = SnippetDartdocParser(filesystem);
    final SnippetGenerator snippetGenerator = SnippetGenerator();
    dartdocParser.parseFromComments(fileElements);
    dartdocParser.parseAndAddAssumptions(fileElements, input, silent: true);

    final String srcPath =
    path.relative(input.absolute.path, from: flutterSource.absolute.path);
    final String dstPath = path.join(
      flutterInformation.getFlutterRoot().absolute.path,
      'examples',
      'api',
    );
    for (final SourceElement element
    in fileElements.where((SourceElement element) {
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
        final File outputFile = filesystem.file(
          path.joinAll(<String>[
            dstPath,
            'lib',
            path.withoutExtension(srcPath), // e.g. material/app_bar
            <String>[
              if (element.className.isNotEmpty) element.className.snakeCase,
              element.name.snakeCase,
              sample.index.toString(),
              'dart',
            ].join('.'),
          ]),
        );
        await outputFile.absolute.parent.create(recursive: true);
        if (outputFile.existsSync()) {
          errorExit('File $outputFile already exists!');
        }
        final FlutterSampleLiberator liberator = FlutterSampleLiberator(
          element,
          sample,
          location: filesystem.directory(dstPath),
        );
        if (!filesystem.file(path.join(dstPath, 'pubspec.yaml')).existsSync()) {
          print('Publishing ${outputFile.absolute.path}');
          await liberator.extract(
              overwrite: true, mainDart: outputFile, includeMobile: true);
        } else {
          await outputFile.absolute.writeAsString(sample.output);
        }
        await liberator.reinsertAsReference(outputFile);
        print('${outputFile.path}: ${getSampleStats(element)}');
      }
    }
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
