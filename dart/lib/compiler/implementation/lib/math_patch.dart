// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Patch file for dart:math library.

// Imports checkNum etc. used below.
#import("js_helper.dart");

// TODO(lrn): Consider not using the JS function directly, but instead calling
// helper functions in the "js_helper" library. Then we can stop enabling JS
// in all patched library files.

patch int parseInt(str) {
  checkString(str);
  if (!JS('bool',
          @'/^\s*[+-]?(?:0[xX][abcdefABCDEF0-9]+|\d+)\s*$/.test(#)',
          str)) {
    throw new FormatException(str);
  }
  var trimmed = str.trim();
  var base = 10;
  if ((trimmed.length > 2 && (trimmed[1] == 'x' || trimmed[1] == 'X')) ||
    (trimmed.length > 3 && (trimmed[2] == 'x' || trimmed[2] == 'X'))) {
    base = 16;
  }
  var ret = JS('num', @'parseInt(#, #)', trimmed, base);
  if (ret.isNaN()) throw new FormatException(str);
  return ret;
}

patch double parseDouble(String str) {
  checkString(str);
  var ret = JS('num', @'parseFloat(#)', str);
  if (ret == 0 && (str.startsWith("0x") || str.startsWith("0X"))) {
    // TODO(ahe): This is unspecified, but tested by co19.
    ret = JS('num', @'parseInt(#)', str);
  }
  if (ret.isNaN() && str != 'NaN' && str != '-NaN') {
    throw new FormatException(str);
  }
  return ret;
}

patch double sqrt(num value)
  => JS('double', @'Math.sqrt(#)', checkNum(value));

patch double sin(num value)
  => JS('double', @'Math.sin(#)', checkNum(value));

patch double cos(num value)
  => JS('double', @'Math.cos(#)', checkNum(value));

patch double tan(num value)
  => JS('double', @'Math.tan(#)', checkNum(value));

patch double acos(num value)
  => JS('double', @'Math.acos(#)', checkNum(value));

patch double asin(num value)
  => JS('double', @'Math.asin(#)', checkNum(value));

patch double atan(num value)
  => JS('double', @'Math.atan(#)', checkNum(value));

patch double atan2(num a, num b)
  => JS('double', @'Math.atan2(#, #)', checkNum(a), checkNum(b));

patch double exp(num value)
  => JS('double', @'Math.exp(#)', checkNum(value));

patch double log(num value)
  => JS('double', @'Math.log(#)', checkNum(value));

patch num pow(num value, num exponent) {
  checkNum(value);
  checkNum(exponent);
  return JS('num', @'Math.pow(#, #)', value, exponent);
}

patch class Random {
  patch factory Random([int seed]) => const _Random();
}

class _Random implements Random {
  // The Dart2JS implementation of Random doesn't use a seed.
  _Random();

  int nextInt(int max) {
    if (max < 0) throw new IllegalArgumentException("negative max: $max");
    if (max > 0xFFFFFFFF) max = 0xFFFFFFFF;
    return JS("int", "(Math.random() * #) >>> 0", max);
  }

  /**
   * Generates a positive random floating point value uniformly distributed on
   * the range from 0.0, inclusive, to 1.0, exclusive.
   */
  double nextDouble() => JS("double", "Math.random()");

  /**
   * Generates a random boolean value.
   */
  bool nextBool() => JS("bool", "Math.random() < 0.5");
}
