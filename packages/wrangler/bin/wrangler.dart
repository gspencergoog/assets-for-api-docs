// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show ProcessResult, exitCode, stderr;

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as path;
import 'package:platform/platform.dart';
import 'package:process/process.dart';
import 'package:wrangler/wrangler.dart';

const String _kHelpOption = 'help';
const String _kInputOption = 'input';
const String _kForceOption = 'force';

/// This is the GitStatusFailed class.
/// Refer to [gitResult].
class GitStatusFailed implements Exception {
  GitStatusFailed(this.gitResult);

  /// Refer to `gitResult` and [gitResult].
  final ProcessResult gitResult;

  @override
  String toString() {
    return 'git status exited with a non-zero exit code: '
        '${gitResult.exitCode}:\n${gitResult.stderr}\n${gitResult.stdout}';
  }
}

/// A singleton filesystem that can be set by tests to a memory filesystem.
FileSystem filesystem = const LocalFileSystem();

/// A singleton snippet generator that can be set by tests to a mock, so that
/// we can test the command line parsing.
SnippetGenerator snippetGenerator = SnippetGenerator();

/// A singleton platform that can be set by tests for use in testing command line
/// parsing.
Platform platform = const LocalPlatform();

/// Get the name of the channel these docs are from.
///
/// First check env variable LUCI_BRANCH, then refer to the currently
/// checked out git branch.
String getChannelName({
  Platform platform = const LocalPlatform(),
  ProcessManager processManager = const LocalProcessManager(),
}) {
  final String? envReleaseChannel = platform.environment['LUCI_BRANCH']?.trim();
  if (<String>['master', 'stable'].contains(envReleaseChannel)) {
    return envReleaseChannel!;
  }

  final RegExp gitBranchRegexp = RegExp(r'^## (?<branch>.*)');
  // Adding extra debugging output to help debug why git status inexplicably fails
  // (random non-zero error code) about 2% of the time.
  final ProcessResult gitResult = processManager.runSync(<String>['git', 'status', '-b', '--porcelain'],
      environment: <String, String>{'GIT_TRACE': '2', 'GIT_TRACE_SETUP': '2'});
  if (gitResult.exitCode != 0) {
    throw GitStatusFailed(gitResult);
  }

  final RegExpMatch? gitBranchMatch = gitBranchRegexp.firstMatch((gitResult.stdout as String).trim().split('\n').first);
  return gitBranchMatch == null ? '<unknown>' : gitBranchMatch.namedGroup('branch')!.split('...').first;
}

const List<String> sampleTypes = <String>[
  'snippet',
  'sample',
  'dartpad',
];

// This is a hack to workaround the fact that git status inexplicably fails
// (with random non-zero error code) about 2% of the time.
String getChannelNameWithRetries() {
  int retryCount = 0;

  while (retryCount < 2) {
    try {
      return getChannelName();
    } on GitStatusFailed catch (e) {
      retryCount += 1;
      stderr.write('git status failed, retrying ($retryCount)\nError report:\n$e');
    }
  }

  return getChannelName();
}

/// Generates snippet dartdoc output for a given input, and creates any sample
/// applications needed by the snippet.
void main(List<String> argList) {
  final Map<String, String> environment = platform.environment;
  final ArgParser parser = ArgParser();

  parser.addOption(
    _kInputOption,
    defaultsTo: environment['INPUT'],
    help: 'The input file containing the sample code to inject.',
  );
  parser.addFlag(
    _kForceOption,
    help: 'Forces the replacement to be applied to the input file.',
  );
  parser.addFlag(
    _kHelpOption,
    negatable: false,
    help: 'Prints help documentation for this command',
  );

  final ArgResults args = parser.parse(argList);

  if (args[_kHelpOption]! as bool) {
    stderr.writeln(parser.usage);
    exitCode = 0;
    return;
  }

  if (args[_kInputOption] == null) {
    stderr.writeln(parser.usage);
    errorExit('The --$_kInputOption option must be specified.');
    return;
  }

  final File input = filesystem.file(args['input']! as String);
  if (!input.existsSync()) {
    errorExit('The input file ${input.path} does not exist.');
    return;
  }

  final RegExp indentRe = RegExp(r'^[ ]*');
  final List<String> sourceLines = input.readAsLinesSync();
  final bool forceOption = args[_kForceOption]! as bool;
  final Iterable<SourceElement> elements = getFileCommentElements(input);
  for (final SourceElement element in elements) {
    final Iterable<List<SourceLine>> docLines = getDocumentationComments(<SourceElement>[element]);
    for (final List<SourceLine> lineBlock in docLines) {
      for (final SourceLine line in lineBlock) {
        final RegExp symbolRe = RegExp('`${element.name}`');
        // print('Matching `${element.name}` in ${line.text}');
        if (symbolRe.hasMatch(line.text)) {
          final String result = line.text.replaceAllMapped(symbolRe, (Match match) {
            return '[${element.name}]';
          });
          final String indent = indentRe.firstMatch(sourceLines[line.line])!.group(0)!;
          print('${line.file?.path}:${line.line}:$indent$result');
        }
      }
    }
  }
}
