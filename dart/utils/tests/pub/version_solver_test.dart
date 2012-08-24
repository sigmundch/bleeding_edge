// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('pub_update_test');

#import('dart:io');
#import('dart:isolate');

#import('../../pub/lock_file.dart');
#import('../../pub/package.dart');
#import('../../pub/pubspec.dart');
#import('../../pub/source.dart');
#import('../../pub/source_registry.dart');
#import('../../pub/utils.dart');
#import('../../pub/version.dart');
#import('../../pub/version_solver.dart');
#import('../../../pkg/unittest/unittest.dart');

final noVersion = 'no version';
final disjointConstraint = 'disjoint';
final sourceMismatch = 'source mismatch';
final descriptionMismatch = 'description mismatch';
final couldNotSolve = 'unsolved';

Source source1;
Source source2;
Source versionlessSource;

main() {
  testResolve('no dependencies', {
    'myapp 0.0.0': {}
  }, result: {
    'myapp': '0.0.0'
  });

  testResolve('simple dependency tree', {
    'myapp 0.0.0': {
      'a': '1.0.0',
      'b': '1.0.0'
    },
    'a 1.0.0': {
      'aa': '1.0.0',
      'ab': '1.0.0'
    },
    'aa 1.0.0': {},
    'ab 1.0.0': {},
    'b 1.0.0': {
      'ba': '1.0.0',
      'bb': '1.0.0'
    },
    'ba 1.0.0': {},
    'bb 1.0.0': {}
  }, result: {
    'myapp': '0.0.0',
    'a': '1.0.0',
    'aa': '1.0.0',
    'ab': '1.0.0',
    'b': '1.0.0',
    'ba': '1.0.0',
    'bb': '1.0.0'
  });

  testResolve('shared dependency with overlapping constraints', {
    'myapp 0.0.0': {
      'a': '1.0.0',
      'b': '1.0.0'
    },
    'a 1.0.0': {
      'shared': '>=2.0.0 <4.0.0'
    },
    'b 1.0.0': {
      'shared': '>=3.0.0 <5.0.0'
    },
    'shared 2.0.0': {},
    'shared 3.0.0': {},
    'shared 3.6.9': {},
    'shared 4.0.0': {},
    'shared 5.0.0': {},
  }, result: {
    'myapp': '0.0.0',
    'a': '1.0.0',
    'b': '1.0.0',
    'shared': '3.6.9'
  });

  testResolve('shared dependency where dependent version in turn affects '
              'other dependencies', {
    'myapp 0.0.0': {
      'foo': '<=1.0.2',
      'bar': '1.0.0'
    },
    'foo 1.0.0': {},
    'foo 1.0.1': { 'bang': '1.0.0' },
    'foo 1.0.2': { 'whoop': '1.0.0' },
    'foo 1.0.3': { 'zoop': '1.0.0' },
    'bar 1.0.0': { 'foo': '<=1.0.1' },
    'bang 1.0.0': {},
    'whoop 1.0.0': {},
    'zoop 1.0.0': {}
  }, result: {
    'myapp': '0.0.0',
    'foo': '1.0.1',
    'bar': '1.0.0',
    'bang': '1.0.0'
  });

  testResolve('from versionless source', {
    'myapp 0.0.0': {
      'foo from versionless': 'any'
    },
    'foo 1.2.3 from versionless': {}
  }, result: {
    'myapp': '0.0.0',
    'foo': '1.2.3'
  });

  testResolve('transitively through versionless source', {
    'myapp 0.0.0': {
      'foo from versionless': 'any'
    },
    'foo 1.2.3 from versionless': {
      'bar': '>=1.0.0'
    },
    'bar 1.1.0': {}
  }, result: {
    'myapp': '0.0.0',
    'foo': '1.2.3',
    'bar': '1.1.0'
  });

  testResolve('with compatible locked dependency', {
    'myapp 0.0.0': {
      'foo': 'any'
    },
    'foo 1.0.0': { 'bar': '1.0.0' },
    'foo 1.0.1': { 'bar': '1.0.1' },
    'foo 1.0.2': { 'bar': '1.0.2' },
    'bar 1.0.0': {},
    'bar 1.0.1': {},
    'bar 1.0.2': {}
  }, lockfile: {
    'foo': '1.0.1'
  }, result: {
    'myapp': '0.0.0',
    'foo': '1.0.1',
    'bar': '1.0.1'
  });

  testResolve('with incompatible locked dependency', {
    'myapp 0.0.0': {
      'foo': '>1.0.1'
    },
    'foo 1.0.0': { 'bar': '1.0.0' },
    'foo 1.0.1': { 'bar': '1.0.1' },
    'foo 1.0.2': { 'bar': '1.0.2' },
    'bar 1.0.0': {},
    'bar 1.0.1': {},
    'bar 1.0.2': {}
  }, lockfile: {
    'foo': '1.0.1'
  }, result: {
    'myapp': '0.0.0',
    'foo': '1.0.2',
    'bar': '1.0.2'
  });

  testResolve('with unrelated locked dependency', {
    'myapp 0.0.0': {
      'foo': 'any'
    },
    'foo 1.0.0': { 'bar': '1.0.0' },
    'foo 1.0.1': { 'bar': '1.0.1' },
    'foo 1.0.2': { 'bar': '1.0.2' },
    'bar 1.0.0': {},
    'bar 1.0.1': {},
    'bar 1.0.2': {},
    'baz 1.0.0': {}
  }, lockfile: {
    'baz': '1.0.0'
  }, result: {
    'myapp': '0.0.0',
    'foo': '1.0.2',
    'bar': '1.0.2'
  });

  testResolve('dependency back onto root package', {
    'myapp 1.0.0': {
      'foo': '1.0.0'
    },
    'foo 1.0.0': {
      'myapp': '>=1.0.0'
    }
  }, error: sourceMismatch);

  testResolve('no version that matches requirement', {
    'myapp 0.0.0': {
      'foo': '>=1.0.0 <2.0.0'
    },
    'foo 2.0.0': {},
    'foo 2.1.3': {}
  }, error: noVersion);

  testResolve('no version that matches combined constraint', {
    'myapp 0.0.0': {
      'foo': '1.0.0',
      'bar': '1.0.0'
    },
    'foo 1.0.0': {
      'shared': '>=2.0.0 <3.0.0'
    },
    'bar 1.0.0': {
      'shared': '>=2.9.0 <4.0.0'
    },
    'shared 2.5.0': {},
    'shared 3.5.0': {}
  }, error: noVersion);

  testResolve('disjoint constraints', {
    'myapp 0.0.0': {
      'foo': '1.0.0',
      'bar': '1.0.0'
    },
    'foo 1.0.0': {
      'shared': '<=2.0.0'
    },
    'bar 1.0.0': {
      'shared': '>3.0.0'
    },
    'shared 2.0.0': {},
    'shared 4.0.0': {}
  }, error: disjointConstraint);

  testResolve('mismatched descriptions', {
    'myapp 0.0.0': {
      'foo': '1.0.0',
      'bar': '1.0.0'
    },
    'foo 1.0.0': {
      'shared-x': '1.0.0'
    },
    'bar 1.0.0': {
      'shared-y': '1.0.0'
    },
    'shared-x 1.0.0': {},
    'shared-y 1.0.0': {}
  }, error: descriptionMismatch);

  testResolve('mismatched sources', {
    'myapp 0.0.0': {
      'foo': '1.0.0',
      'bar': '1.0.0'
    },
    'foo 1.0.0': {
      'shared': '1.0.0'
    },
    'bar 1.0.0': {
      'shared from mock2': '1.0.0'
    },
    'shared 1.0.0': {},
    'shared 1.0.0 from mock2': {}
  }, error: sourceMismatch);

  testResolve('unstable dependency graph', {
    'myapp 0.0.0': {
      'a': '>=1.0.0'
    },
    'a 1.0.0': {},
    'a 2.0.0': {
      'b': '1.0.0'
    },
    'b 1.0.0': {
      'a': '1.0.0'
    }
  }, error: couldNotSolve);

// TODO(rnystrom): More stuff to test:
// - Two packages depend on the same package, but from different sources. Should
//   fail.
// - Depending on a non-existent package.
// - Test that only a certain number requests are sent to the mock source so we
//   can keep track of server traffic.
}

testResolve(description, packages, [lockfile, result, error]) {
  test(description, () {
    var sources = new SourceRegistry();
    source1 = new MockSource('mock1');
    source2 = new MockSource('mock2');
    versionlessSource = new MockVersionlessSource();
    sources.register(source1);
    sources.register(source2);
    sources.register(versionlessSource);
    sources.setDefault(source1.name);

    // Build the test package graph.
    var root;
    packages.forEach((nameVersion, dependencies) {
      var parsed = parseSource(nameVersion);
      nameVersion = parsed.first;
      var source = parsed.last;

      var parts = nameVersion.split(' ');
      var name = parts[0];
      var version = parts[1];

      var package = source1.mockPackage(name, version, dependencies);
      if (name == 'myapp') {
        // Don't add the root package to the server, so we can verify that Pub
        // doesn't try to look up information about the local package on the
        // remote server.
        root = package;
      } else {
        source.addPackage(package);
      }
    });

    // Clean up the expectation.
    if (result != null) {
      result.forEach((name, version) {
        result[name] = new Version.parse(version);
      });
    }

    var realLockFile = new LockFile.empty();
    if (lockfile != null) {
      lockfile.forEach((name, version) {
        version = new Version.parse(version);
        realLockFile.packages[name] = new PackageId(source1, version, name);
      });
    }

    // Resolve the versions.
    var future = resolveVersions(sources, root, realLockFile);

    if (result != null) {
      expect(future, completion(predicate((actualResult) {
        for (var id in actualResult) {
          if (!result.containsKey(id.description)) return false;
          if (id.version != result.remove(id.description)) return false;
        }
        return result.isEmpty();
      }, description: 'packages to match $result')));
    } else if (error == noVersion) {
      expect(future, throwsA(new isInstanceOf<NoVersionException>()));
    } else if (error == disjointConstraint) {
      expect(future, throwsA(new isInstanceOf<DisjointConstraintException>()));
    } else if (error == sourceMismatch) {
      expect(future, throwsA(new isInstanceOf<SourceMismatchException>()));
    } else if (error == descriptionMismatch) {
      expect(future, throwsA(new isInstanceOf<DescriptionMismatchException>()));
    } else if (error == couldNotSolve) {
      expect(future, throwsA(new isInstanceOf<CouldNotSolveException>()));
    } else {
      expect(future, throwsA(error));
    }

    // If we aren't expecting an error, print some debugging info if we get one.
    if (error == null) {
      future.handleException((ex) {
        print(ex);
        print(future.stackTrace);
        return true;
      });
    }
  });
}

/**
 * A source used for testing. This both creates mock package objects and acts as
 * a source for them.
 *
 * In order to support testing packages that have the same name but different
 * descriptions, a package's name is calculated by taking the description string
 * and stripping off any trailing hyphen followed by non-hyphen characters.
 */
class MockSource extends Source {
  final Map<String, Map<Version, Package>> _packages;

  final String name;
  bool get shouldCache => true;

  MockSource(this.name)
      : _packages = <String, Map<Version, Package>>{};

  Future<List<Version>> getVersions(String name) {
    return fakeAsync(() => _packages[name].getKeys());
  }

  Future<Pubspec> describe(PackageId id) {
    return fakeAsync(() {
      return _packages[id.name][id.version].pubspec;
    });
  }

  Future<bool> install(PackageId id, String path) {
    throw 'no';
  }

  Package mockPackage(String description, String version,
      Map dependencyStrings) {
    // Build the pubspec dependencies.
    var dependencies = <PackageRef>[];
    dependencyStrings.forEach((name, constraint) {
      var parsed = parseSource(name);
      dependencies.add(new PackageRef(
          parsed.last, new VersionConstraint.parse(constraint), parsed.first));
    });

    var pubspec = new Pubspec(
        description, new Version.parse(version), dependencies);
    return new Package.inMemory(pubspec);
  }

  void addPackage(Package package) {
    _packages.putIfAbsent(package.name, () => new Map<Version, Package>());
    _packages[package.name][package.version] = package;
  }

  String packageName(String description) =>
    description.replaceFirst(new RegExp(@"-[^-]+$"), "");
}

/**
 * A source used for testing that doesn't natively understand versioning,
 * similar to how the Git and SDK sources work.
 */
class MockVersionlessSource extends Source {
  final Map<String, Package> _packages;

  final String name = 'versionless';
  final bool shouldCache = false;

  MockVersionlessSource()
    : _packages = <String, Package>{};

  Future<bool> install(PackageId id, String path) {
    throw 'no';
  }

  Future<Pubspec> describe(PackageId id) {
    return new Future<Pubspec>.immediate(_packages[id.description].pubspec);
  }

  void addPackage(Package package) {
    _packages[package.name] = package;
  }
}

Future fakeAsync(callback()) {
  var completer = new Completer();
  new Timer(0, (_) {
    completer.complete(callback());
  });

  return completer.future;
}

Pair<String, Source> parseSource(String name) {
  var match = new RegExp(@"(.*) from (.*)").firstMatch(name);
  if (match == null) return new Pair<String, Source>(name, source1);
  switch (match[2]) {
  case 'mock1': return new Pair<String, Source>(match[1], source1);
  case 'mock2': return new Pair<String, Source>(match[1], source2);
  case 'versionless':
    return new Pair<String, Source>(match[1], versionlessSource);
  }
}
