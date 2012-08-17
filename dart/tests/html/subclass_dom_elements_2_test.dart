// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('subclass_dom_elements_2_test');
#import('../../pkg/unittest/unittest.dart');
#import('../../pkg/unittest/html_config.dart');
#import('dart:html');


/** Test suite for advanced features of subclassing of native elements. */
main() {
  useHtmlConfiguration();

  group('multiple levels of inheritance', () {
    test('can instantiate transitive subclass of native', () {
      Bar bar = new Bar();
    });

    test('transitive subtype has native behavior', () {
      Bar bar = new Bar();
      bar.innerHTML = '<p>foo</p>';
      expect(bar.nodes.length, equals(1));
      // the test runners won't let us test document.body.innerHTML nicely,
      // so we use another div as a stand-in.
      var div = new DivElement();
      div.nodes.add(bar);
      expect(div.innerHTML, equals('<p><p>foo</p></p>'));
    });

    test('transitive subtype inherits from direct supertype', () {
      Bar bar = new Bar();
      expect(bar.razzle(), equals('razzle'));
      bar.foo = 2;
      expect(bar.foo, equals(2));
    });

    test('transitive subtype has correct custom members', () {
      Bar bar = new Bar();
      expect(bar.dazzle(), equals('dazzle'));
      bar.bar = 2;
      expect(bar.bar, equals(2));
    });

    test('transitive subtype passes appropriate is-checks', () {
      Bar bar = new Bar();
      expect(bar is Bar);
      expect(bar is Foo);
      expect(bar is ParagraphElement);
      expect(!(new Foo() is Bar));
    });

    test('transitive subtype can override direct subtype', () {
      Bar bar = new Bar();
      expect(bar.overrideMe, equals('overridden'));
    });
  });

  // TODO(samhop): Add a test for overriding members of the native element,
  // once we figure out what the semantics in that case are.
}

class Foo extends ParagraphElementImpl {
  int foo;
  String razzle() {
    return 'razzle';
  }

  String overrideMe() {
    return 'not overridden';
  }

  static var _$constructorThunk;
  Foo._internal();
  factory Foo() {
    if (_$constructorThunk == null) {
      _$constructorThunk = (() => new Foo._internal());
    }
    var paragraph = new ParagraphElement();
    rewirePrototypeChain(paragraph, _$constructorThunk);
    return paragraph;
  }
}

class Bar extends Foo {
  int bar;
  String dazzle() {
    return 'dazzle';
  }

  String overrideMe() {
    return 'overridden';
  }

  static var _$constructorThunk;
  Bar._internal() : super._internal();
  factory Bar() {
    if (_$constructorThunk == null) {
      _$constructorThunk = (() => new Bar._internal());
    }
    var paragraph = new ParagraphElement();
    rewirePrototypeChain(paragraph, _$constructorThunk);
    return paragraph;
  }
}
