// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Check that compile-time constants are correctly canonicalized.

main() {
  Expect.isTrue(const <num>[1,2] !== const <num>[1.0,2.0]);
}
