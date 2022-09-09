// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:wrangler/wrangler.dart';
import 'package:test/test.dart' hide TypeMatcher, isInstanceOf;

void main() {
  group('Configuration', () {
    final MemoryFileSystem memoryFileSystem = MemoryFileSystem();
    late SnippetConfiguration config;

    setUp(() {
      config = FlutterRepoSnippetConfiguration(
        flutterRoot: memoryFileSystem.directory('/flutter sdk'),
        filesystem: memoryFileSystem,
      );
    });
    test('config directory is correct', () async {
      expect(config.configDirectory.path,
          matches(RegExp(r'[/\\]flutter sdk[/\\]dev[/\\]wrangler[/\\]config')));
    });
    test('output directory is correct', () async {
      expect(
          config.outputDirectory.path,
          matches(RegExp(
              r'[/\\]flutter sdk[/\\]dev[/\\]docs[/\\]doc[/\\]wrangler')));
    });
    test('skeleton directory is correct', () async {
      expect(
          config.skeletonsDirectory.path,
          matches(RegExp(
              r'[/\\]flutter sdk[/\\]dev[/\\]wrangler[/\\]config[/\\]skeletons')));
    });
    test('templates directory is correct', () async {
      expect(
          config.templatesDirectory.path,
          matches(RegExp(
              r'[/\\]flutter sdk[/\\]dev[/\\]wrangler[/\\]config[/\\]templates')));
    });
    test('html skeleton file for sample is correct', () async {
      expect(
          config.getHtmlSkeletonFile('snippet').path,
          matches(RegExp(
              r'[/\\]flutter sdk[/\\]dev[/\\]wrangler[/\\]config[/\\]skeletons[/\\]wrangler.html')));
    });
    test('html skeleton file for app with no dartpad is correct', () async {
      expect(
          config.getHtmlSkeletonFile('sample').path,
          matches(RegExp(
              r'[/\\]flutter sdk[/\\]dev[/\\]wrangler[/\\]config[/\\]skeletons[/\\]sample.html')));
    });
    test('html skeleton file for app with dartpad is correct', () async {
      expect(
          config.getHtmlSkeletonFile('dartpad').path,
          matches(RegExp(
              r'[/\\]flutter sdk[/\\]dev[/\\]wrangler[/\\]config[/\\]skeletons[/\\]dartpad-sample.html')));
    });
  });
}
