// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Check that function types are accepted for constructor arguments that
// initialize fields.

class A {
  Function f;
  A(int this.f());
}

main() {
  var a = new A(() => 499);
  Expect.equals(499, (a.f)());
}
