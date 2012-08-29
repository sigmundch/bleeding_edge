// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('subclass_dom_elements_layout_test');

#import('dart:html');

/** 
 * Test that native functions called on instances of subclasses of native
 * classes result in the appropriate render tree.
 * Output should be two paragraphs, with contents 'foo' and 'bar'.
 *
 * This is just a sanity check, not a complete test suite.
 */
main() {
  var mydiv = new CustomDiv();
  document.body.nodes.add(mydiv);

  mydiv.innerHTML = '<p>foo</p>';
  mydiv.nodes.add(new Element.html('<p>bar</p>'));
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
    rewirePrototypeChain(div, _$constructorThunk, 'CustomDiv');
    return div;
  }
}
