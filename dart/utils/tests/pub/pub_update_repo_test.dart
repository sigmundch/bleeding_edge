// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('pub_tests');

#import('dart:io');

#import('test_pub.dart');
#import('../../../pkg/unittest/unittest.dart');

main() {
  test("updates one locked pub server package's dependencies if it's "
      "necessary", () {
    servePackages([
      package("foo", "1.0.0", [dependency("foo-dep")]),
      package("foo-dep", "1.0.0")
    ]);

    appDir([dependency("foo")]).scheduleCreate();

    schedulePub(args: ['install'],
        output: const RegExp(@"Dependencies installed!$"));

    packagesDir({
      "foo": "1.0.0",
      "foo-dep": "1.0.0"
    }).scheduleValidate();

    servePackages([
      package("foo", "2.0.0", [dependency("foo-dep", ">1.0.0")]),
      package("foo-dep", "2.0.0")
    ]);

    schedulePub(args: ['update', 'foo'],
        output: const RegExp(@"Dependencies updated!$"));

    packagesDir({
      "foo": "2.0.0",
      "foo-dep": "2.0.0"
    }).scheduleValidate();

    run();
  });

  test("updates a locked package's dependers in order to get it to max "
      "version", () {
    servePackages([
      package("foo", "1.0.0", [dependency("bar", "<2.0.0")]),
      package("bar", "1.0.0")
    ]);

    appDir([dependency("foo"), dependency("bar")]).scheduleCreate();

    schedulePub(args: ['install'],
        output: const RegExp(@"Dependencies installed!$"));

    packagesDir({
      "foo": "1.0.0",
      "bar": "1.0.0"
    }).scheduleValidate();

    servePackages([
      package("foo", "2.0.0", [dependency("bar", "<3.0.0")]),
      package("bar", "2.0.0")
    ]);

    schedulePub(args: ['update', 'bar'],
        output: const RegExp(@"Dependencies updated!$"));

    packagesDir({
      "foo": "2.0.0",
      "bar": "2.0.0"
    }).scheduleValidate();

    run();
  });

  test("removes a dependency that's been removed from the pubspec", () {
    servePackages([
      package("foo", "1.0.0"),
      package("bar", "1.0.0")
    ]);

    appDir([dependency("foo"), dependency("bar")]).scheduleCreate();

    schedulePub(args: ['update'],
        output: const RegExp(@"Dependencies updated!$"));

    packagesDir({
      "foo": "1.0.0",
      "bar": "1.0.0"
    }).scheduleValidate();

    appDir([dependency("foo")]).scheduleCreate();

    schedulePub(args: ['update'],
        output: const RegExp(@"Dependencies updated!$"));

    packagesDir({
      "foo": "1.0.0",
      "bar": null
    }).scheduleValidate();

    run();
  });

  test("removes a transitive dependency that's no longer depended on", () {
    servePackages([
      package("foo", "1.0.0", [dependency("shared-dep")]),
      package("bar", "1.0.0", [
        dependency("shared-dep"),
        dependency("bar-dep")
      ]),
      package("shared-dep", "1.0.0"),
      package("bar-dep", "1.0.0")
    ]);

    appDir([dependency("foo"), dependency("bar")]).scheduleCreate();

    schedulePub(args: ['update'],
        output: const RegExp(@"Dependencies updated!$"));

    packagesDir({
      "foo": "1.0.0",
      "bar": "1.0.0",
      "shared-dep": "1.0.0",
      "bar-dep": "1.0.0",
    }).scheduleValidate();

    appDir([dependency("foo")]).scheduleCreate();

    schedulePub(args: ['update'],
        output: const RegExp(@"Dependencies updated!$"));

    packagesDir({
      "foo": "1.0.0",
      "bar": null,
      "shared-dep": "1.0.0",
      "bar-dep": null,
    }).scheduleValidate();

    run();
  });

  test("updates dependencies whose constraints have been removed", () {
    servePackages([
      package("foo", "1.0.0", [dependency("shared-dep")]),
      package("bar", "1.0.0", [dependency("shared-dep", "<2.0.0")]),
      package("shared-dep", "1.0.0"),
      package("shared-dep", "2.0.0")
    ]);

    appDir([dependency("foo"), dependency("bar")]).scheduleCreate();

    schedulePub(args: ['update'],
        output: const RegExp(@"Dependencies updated!$"));

    packagesDir({
      "foo": "1.0.0",
      "bar": "1.0.0",
      "shared-dep": "1.0.0"
    }).scheduleValidate();

    appDir([dependency("foo")]).scheduleCreate();

    schedulePub(args: ['update'],
        output: const RegExp(@"Dependencies updated!$"));

    packagesDir({
      "foo": "1.0.0",
      "bar": null,
      "shared-dep": "2.0.0"
    }).scheduleValidate();

    run();
  });
}
