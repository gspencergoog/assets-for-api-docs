// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/file_system/file_system.dart' as afs;
import 'package:analyzer/file_system/physical_file_system.dart' as afs;
import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as path;

/// The main app here.
void main(List<String> arguments) {
  final ArgParser parser = ArgParser();
  parser.addFlag('help', help: 'Print help.');
  parser.addOption('output', abbr: 'o', help: 'Specify an output directory');
  parser.addOption('input',
      abbr: 'i', help: 'Specify a file with input files listed in it, one per line, absolute paths.');
  final ArgResults flags = parser.parse(arguments);

  if (flags['help'] as bool) {
    print('source_convert.dart [flags]');
    print(parser.usage);
    exit(0);
  }

  const LocalFileSystem fs = LocalFileSystem();

  final List<String> fileList = fs.file(flags['input']).readAsLinesSync();
  final Directory output = fs.directory(flags['output']);
  if (!output.existsSync()) {
    output.createSync(recursive: true);
  }
  for (final String fileStr in fileList) {
    final File inputFile = fs.file(fileStr).absolute;
    final List<Split> splits = tokenize(inputFile);
    final File whitespaceFile = output.childFile('${path.basenameWithoutExtension(inputFile.path)}.ws');
    final File outputFile = output.childFile('${path.basenameWithoutExtension(inputFile.path)}.in');
    final IOSink whitespaceSink = whitespaceFile.openWrite();
    final IOSink outputSink = outputFile.openWrite();
    for (final Split split in splits) {
      whitespaceSink.write('${split.whitespace}|');
      outputSink.write('${split.content}\n');
    }
    whitespaceSink.close();
    outputSink.close();
  }
}

class Split {
  const Split(this.whitespace, this.content);

  final String whitespace;
  final String content;
}

Iterable<Token> linearize({
  required Token? token,
  Token? endToken,
}) sync* {
  Token? current = token;
  while (current != endToken && current != null) {
    if (current.precedingComments != null) {
      yield* linearize(token: current.precedingComments, endToken: endToken);
    }
    yield current;
    current = current.next;
  }
}

List<Split> tokenizeBranch({
  required Iterable<Token> tokens,
  required String content,
}) {
  final List<Split> result = <Split>[];
  Token? previous;
  for (final Token current in tokens) {
    final int previousEnd = previous?.end ?? current.offset;
    final int currentStart = current.offset;
    result.add(Split(content.substring(previousEnd, currentStart), current.lexeme));
    previous = current;
  }
  return result;
}

// Convert input file into runs of spaces, newlines, and non-spaces. Output is
// all the non-space runs only. Quoted strings and blocks of comments count as
// "non-space" blocks.
List<Split> tokenize(File file, {afs.ResourceProvider? resourceProvider}) {
  resourceProvider ??= afs.PhysicalResourceProvider.INSTANCE;
  final ParseStringResult parseResult = parseFile(
      featureSet: FeatureSet.latestLanguageVersion(),
      path: file.absolute.path,
      resourceProvider: resourceProvider);
  final Token startingToken = parseResult.unit.beginToken;
  final Token endToken = parseResult.unit.endToken;
  final String content = parseResult.content;
  return tokenizeBranch(tokens: linearize(token: startingToken, endToken: endToken), content: content);
}
