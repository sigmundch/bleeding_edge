// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('pub_tests');

#import('dart:io');

#import('test_pub.dart');
#import('../../../pkg/unittest/unittest.dart');

main() {
  group('requires', () {
    test('a pubspec', () {
      dir(appPath, []).scheduleCreate();

      schedulePub(args: ['update'],
          error: const RegExp(@'^Could not find a file named "pubspec.yaml"'),
          exitCode: 1);

      run();
    });

    test('a pubspec with a "name" key', () {
      dir(appPath, [
        pubspec({"dependencies": {"foo": null}})
      ]).scheduleCreate();

      schedulePub(args: ['update'],
          error: const RegExp(@'^"pubspec.yaml" is missing the required "name" '
              @'field \(e\.g\. "name: myapp"\)\.'),
          exitCode: 1);

      run();
    });
  });

  // TODO(rnystrom): Re-enable this when #4820 is fixed.
  /*
  test('creates a self-referential symlink', () {
    // The symlink should use the name in the pubspec, not the name of the
    // directory.
    dir(appPath, [
      pubspec({"name": "myapp_name"})
    ]).scheduleCreate();

    schedulePub(args: ['update'],
        output: const RegExp(@"Dependencies updated!$"));

    dir(packagesPath, [
      dir("myapp_name", [pubspec({"name": "myapp_name"})])
    ]).scheduleValidate();

    run();
  });
  */
}
