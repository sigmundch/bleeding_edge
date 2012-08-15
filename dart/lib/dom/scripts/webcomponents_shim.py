#!/usr/bin/python
# Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
#
# Script to modify html_dart2js.dart to expose Impl classes so that
# we can test native element subclassing implementation in dart2js.
# TODO(samhop): this is a temporary hack! Generate this code as part of the
# existing codegen.

import fileinput
import re
import sys

HTML_DART2JS_PATH = '../../html/dart2js/html_dart2js.dart'
EXTRA_CODE_PATH = '../../html/dart2js/webcomponents_shim.dart' 

def PublicizeDomImplementations():
  """
  Exposes private dom implementation classes by replacing
  all occurrences of [_FooImpl] by [FooImpl].
  """

  # matches if the private token is preceded by whitespace, '<', '(', or 
  # the beginning of the line
  private_impl_regex = '(^|[\s(<])_(\w+Impl)'
  for line in fileinput.input(HTML_DART2JS_PATH, inplace=1):
    newline = line
    for m in re.finditer(private_impl_regex, line):
      newline = newline.replace(m.group(0), m.group(1) + m.group(2))
    sys.stdout.write(newline)

def EmitPrototypeRewiring():
  """ Appends prototype rewiring code to the html_dart2js. """
  html_dart2js_handle = open(HTML_DART2JS_PATH, 'a')
  patch_handle = open(EXTRA_CODE_PATH, 'r')
  for line in patch_handle.readlines():
    html_dart2js_handle.write(line)

def main():
  PublicizeDomImplementations()
  EmitPrototypeRewiring()
  
if __name__ == '__main__':
  sys.exit(main())
