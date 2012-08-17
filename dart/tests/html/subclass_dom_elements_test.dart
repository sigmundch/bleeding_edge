// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('subclass_dom_elements_test');
#import('../../pkg/unittest/unittest.dart');
#import('../../pkg/unittest/html_config.dart');
#import('dart:html');


/** Test suite for subclassing of native elements. */
main() {
  useHtmlConfiguration();

  group('basic functionality', () {
    test('can construct instance of native subclass', () {
      CustomDiv mydiv = new CustomDiv();
    });

    test('instance of native subclass has custom behavior', () {
      CustomDiv mydiv = new CustomDiv();
      expect(mydiv.razzle(), equals('razzle'));
    });

    test('instance of native subclass has custom fields', () {
      CustomDiv mydiv = new CustomDiv();
      mydiv.foo = 2;
      expect(mydiv.foo, equals(2));
    });

    test('instance of native subclass has native behavior', () {
      CustomDiv mydiv = new CustomDiv();
      mydiv.innerHTML = '<p>foo</p>';
      expect(mydiv.nodes.length, equals(1));
      // the test runners won't let us test document.body.innerHTML nicely,
      // so we use another div as a stand-in.
      var normaldiv = new DivElement();
      normaldiv.nodes.add(mydiv);
      expect(normaldiv.innerHTML, equals('<div><p>foo</p></div>'));
    });

    test('custom elements behave well w.r.t. is-checks', () {
      CustomDiv mydiv = new CustomDiv();
      expect(mydiv is CustomDiv, isTrue);
      expect(mydiv is DivElement);
    });

    test('queries retrieve custom elements', () {
      CustomDiv mydiv = new CustomDiv();
      DivElement normaldiv = new DivElement();
      normaldiv.nodes.add(mydiv);
      expect(mydiv == normaldiv.query('div'));
    });
  });
}

class CustomDiv extends DivElementImpl {
  int foo;
  String razzle() {
    return 'razzle';
  }

  static var _$constructorThunk;
  CustomDiv._internal();
  factory CustomDiv() {
    if (_$constructorThunk == null) {
      _$constructorThunk = (() => new CustomDiv._internal());
    }
    var div = new DivElement();
    rewirePrototypeChain(div, _$constructorThunk);
    return div;
  }
}
