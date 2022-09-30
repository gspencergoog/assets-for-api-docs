// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

/// The main app here.
void main(List<String> arguments) {
  final ArgParser parser = ArgParser();
  parser.addFlag('help', help: 'Print help.');
  parser.addOption('output', abbr: 'o', help: 'Specify an output file');
  parser.addOption('tokens',
      abbr: 't', help: 'Specify input file path with tokens.');
  parser.addOption('whitespace',
      abbr: 'w', help: 'Specify input file path with whitespace.');
  final ArgResults flags = parser.parse(arguments);

  if (flags['help'] as bool) {
    print('source_merge.dart [flags]');
    print(parser.usage);
    exit(0);
  }

  const LocalFileSystem fs = LocalFileSystem();


  final File whitespaceFile = fs.file(flags['whitespace']);
  final File tokenFile = fs.file(flags['tokens']);

  final String whitespace = whitespaceFile.readAsStringSync();
  final String tokens = tokenFile.readAsStringSync();

  final List<Split> merged = merge(whitespace.split('|'), tokens.split('\n'));

  final File output = fs.file(flags['output']);
  final IOSink outputSink = output.openWrite();
  for (final Split split in merged) {
    outputSink.write(split.whitespace);
    outputSink.write(split.token);
  }
  outputSink.close();
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