// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

const LocalFileSystem fs = LocalFileSystem();

/// The main app here.
Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser();
  parser.addFlag('help', help: 'Print help.');
  parser.addOption('output', abbr: 'o', help: 'Specify an output directory.');
  parser.addOption('input', abbr: 'i', help: 'Specify input directory path with both dart and whitespace files.');
  final ArgResults flags = parser.parse(arguments);

  if (flags['help'] as bool) {
    print('source_merge.dart [flags]');
    print(parser.usage);
    exit(0);
  }

  final Directory inputDir = fs.directory(flags['input']).absolute;
  final Directory outputDir = fs.directory(flags['output']).absolute;
  final List<File> tokenFiles = await inputDir
      .list(recursive: true)
      .where((FileSystemEntity entity) =>
          entity is File && (entity.path.endsWith('.dart')))
      .cast<File>()
      .map<File>(
        (File file) => fs.file(fs.path.relative(file.absolute.path, from: inputDir.path)),
      )
      .toList();

  final List<File> whitespaceFiles = tokenFiles.map<File>((File file) => fs.file('${file.path}.ws')).toList();
  assert(whitespaceFiles.length == tokenFiles.length);
  int count = 0;
  for (final File tokenRelative in tokenFiles) {
    final File token = fs.file(
      fs.path.join(inputDir.path, tokenRelative.path),
    );
    final File whitespace = fs.file(
      fs.path.join(inputDir.path, whitespaceFiles[count].path),
    );
    final File output = fs.file(
      fs.path.join(outputDir.path, tokenRelative.path),
    );
    await output.parent.create(recursive: true);
    await output.writeAsString(mergeFile(token, whitespace));
    count++;
  }
}

String mergeFile(File tokenFile, File whitespaceFile) {
  final String whitespace = whitespaceFile.readAsStringSync();
  final String tokens = tokenFile.readAsStringSync();

  final List<Split> merged = merge(whitespace.split('|'), tokens.split('\n'));

  final StringBuffer buffer = StringBuffer();
  for (final Split split in merged) {
    buffer.write(split.whitespace);
    buffer.write(split.token);
  }
  return buffer.toString();
}

class Split {
  const Split(this.whitespace, this.token);

  final String whitespace;
  final String token;
}

List<Split> merge(List<String> whitespace, List<String> tokens) {
  int wsIndex = 0;
  final List<Split> merged = <Split>[];
  for (final String token in tokens) {
    merged.add(Split(whitespace[wsIndex], token));
    wsIndex++;
  }
  return merged;
}
