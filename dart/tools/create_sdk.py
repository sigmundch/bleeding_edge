#!/usr/bin/env python
#
# Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
#
# A script which will be invoked from gyp to create an SDK.
#
# Usage: create_sdk.py sdk_directory
#
# The SDK will be used either from the command-line or from the editor.
# Top structure is
#
# ..dart-sdk/
# ....bin/
# ......dart or dart.exe (executable)
# ......dart.lib (import library for VM native extensions on Windows)
# ......dart2js
# ......dart_analyzer
# ......pub
# ....include/
# ......dart_api.h
# ......dart_debugger_api.h
# ....lib/
# ......_internal/
# ......compiler/
# ......core/
# ......coreimpl/
# ......crypto/
# ......html/
# ......io/
# ......isolate/
# ......json/
# ......math/
# ......mirrors/
# ......uri/
# ......utf/
# ....pkg/
# ......args/
# ......dartdoc/
#.......htmlescape/
# ......intl/
# ......logging/
# ......unittest/
# ......(more will come here)
# ....util/
# ......analyzer/
# ........dart_analyzer.jar
# ........(third-party libraries for dart_analyzer)
# ......pub/
# ......(more will come here)



import os
import re
import sys
import tempfile
import utils

# TODO(dgrove): Only import modules following Google style guide.
from os.path import basename, dirname, join, realpath, exists, isdir

# TODO(dgrove): Only import modules following Google style guide.
from shutil import copyfile, copymode, copytree, ignore_patterns, rmtree, move

def ReplaceInFiles(paths, subs):
  '''Reads a series of files, applies a series of substitutions to each, and
     saves them back out. subs should by a list of (pattern, replace) tuples.'''
  for path in paths:
    contents = open(path).read()
    for pattern, replace in subs:
      contents = re.sub(pattern, replace, contents)

    dest = open(path, 'w')
    dest.write(contents)
    dest.close()


def Copy(src, dest):
  copyfile(src, dest)
  copymode(src, dest)

# TODO(zundel): this excludes the analyzer from the sdk build until builders
# have all prerequisite software installed.  Also update dart.gyp.
def ShouldCopyAnalyzer():
  os = utils.GuessOS();
  return os == 'linux' or os == 'macos'


def CopyShellScript(src_file, dest_dir):
  '''Copies a shell/batch script to the given destination directory. Handles
     using the appropriate platform-specific file extension.'''
  file_extension = ''
  if utils.GuessOS() == 'win32':
    file_extension = '.bat'

  src = src_file + file_extension
  dest = join(dest_dir, basename(src_file) + file_extension)
  Copy(src, dest)


def CopyDart2Js(build_dir, sdk_root, revision):
  if revision:
    ReplaceInFiles([os.path.join(sdk_root, 'lib', 'compiler',
                                 'implementation', 'compiler.dart')],
                   [(r"BUILD_ID = 'build number could not be determined'",
                     r"BUILD_ID = '%s'" % revision)])
  if utils.GuessOS() == 'win32':
    dart2js = os.path.join(sdk_root, 'bin', 'dart2js.bat')
    Copy(os.path.join(build_dir, 'dart2js.bat'), dart2js)
    ReplaceInFiles([dart2js],
                   [(r'%SCRIPTPATH%\.\.\\lib',
                     r'%SCRIPTPATH%..\lib')])
    dartdoc = os.path.join(sdk_root, 'bin', 'dartdoc.bat')
    Copy(os.path.join(build_dir, 'dartdoc.bat'), dartdoc)
  else:
    dart2js = os.path.join(sdk_root, 'bin', 'dart2js')
    Copy(os.path.join(build_dir, 'dart2js'), dart2js)
    ReplaceInFiles([dart2js],
                   [(r'\$BIN_DIR/\.\./\.\./lib',
                     r'$BIN_DIR/../lib')])
    dartdoc = os.path.join(sdk_root, 'bin', 'dartdoc')
    Copy(os.path.join(build_dir, 'dartdoc'), dartdoc)


def Main(argv):
  # Pull in all of the gpyi files which will be munged into the sdk.
  io_runtime_sources = \
    (eval(open("runtime/bin/io_sources.gypi").read()))['sources']

  HOME = dirname(dirname(realpath(__file__)))

  SDK_tmp = tempfile.mkdtemp()
  SDK = argv[1]

  # TODO(dgrove) - deal with architectures that are not ia32.

  if exists(SDK):
    rmtree(SDK)

  # Create and populate sdk/bin.
  BIN = join(SDK_tmp, 'bin')
  os.makedirs(BIN)

  # Copy the Dart VM binary and the Windows Dart VM link library
  # into sdk/bin.
  #
  # TODO(dgrove) - deal with architectures that are not ia32.
  build_dir = os.path.dirname(argv[1])
  dart_file_extension = ''
  analyzer_file_extension = ''
  if utils.GuessOS() == 'win32':
    dart_file_extension = '.exe'
    analyzer_file_extension = '.bat'  # TODO(zundel): test on Windows
    dart_import_lib_src = join(HOME, build_dir, 'dart.lib')
    dart_import_lib_dest = join(BIN, 'dart.lib')
    copyfile(dart_import_lib_src, dart_import_lib_dest)
  dart_src_binary = join(HOME, build_dir, 'dart' + dart_file_extension)
  dart_dest_binary = join(BIN, 'dart' + dart_file_extension)
  copyfile(dart_src_binary, dart_dest_binary)
  copymode(dart_src_binary, dart_dest_binary)

  if ShouldCopyAnalyzer():
    # Copy analyzer into sdk/bin
    ANALYZER_HOME = join(HOME, build_dir, 'analyzer')
    dart_analyzer_src_binary = join(ANALYZER_HOME, 'bin', 'dart_analyzer')
    dart_analyzer_dest_binary = join(BIN,
        'dart_analyzer' + analyzer_file_extension)
    copyfile(dart_analyzer_src_binary, dart_analyzer_dest_binary)
    copymode(dart_analyzer_src_binary, dart_analyzer_dest_binary)

  # Create pub shell script.
  pub_src_script = join(HOME, 'utils', 'pub', 'sdk', 'pub')
  CopyShellScript(pub_src_script, BIN)

  #
  # Create and populate sdk/include.
  #
  INCLUDE = join(SDK_tmp, 'include')
  os.makedirs(INCLUDE)
  copyfile(join(HOME, 'runtime', 'include', 'dart_api.h'),
           join(INCLUDE, 'dart_api.h'))
  copyfile(join(HOME, 'runtime', 'include', 'dart_debugger_api.h'),
           join(INCLUDE, 'dart_debugger_api.h'))

  #
  # Create and populate sdk/lib.
  #

  LIB = join(SDK_tmp, 'lib')
  os.makedirs(LIB)

  #
  # Create and populate lib/io.
  #
  io_dest_dir = join(LIB, 'io')
  os.makedirs(io_dest_dir)
  os.makedirs(join(io_dest_dir, 'runtime'))
  for filename in io_runtime_sources:
    assert filename.endswith('.dart')
    if filename == 'io.dart':
      copyfile(join(HOME, 'runtime', 'bin', filename),
               join(io_dest_dir, 'io_runtime.dart'))
    else:
      copyfile(join(HOME, 'runtime', 'bin', filename),
               join(io_dest_dir, 'runtime', filename))

  # Construct lib/io/io_runtime.dart from whole cloth.
  dest_file = open(join(io_dest_dir, 'io_runtime.dart'), 'a')
  for filename in io_runtime_sources:
    assert filename.endswith('.dart')
    if filename == 'io.dart':
      continue
    dest_file.write('#source("runtime/' + filename + '");\n')
  dest_file.close()

  #
  # Create and populate lib/{core, crypto, isolate, json, uri, utf, ...}.
  #

  for library in ['_internal', 'compiler', 'html', 'core', 'coreimpl',
                  'crypto', 'isolate', 'json', 'math', 'mirrors', 'uri', 'utf']:
    copytree(join(HOME, 'lib', library), join(LIB, library),
             ignore=ignore_patterns('*.svn', 'doc', '*.py', '*.gypi', '*.sh'))

  # TODO(dgrove): fix this really ugly hack
  ReplaceInFiles(
        [join(LIB, 'compiler', 'implementation', 'lib', 'io.dart')],
        [('../../runtime/bin', '../io/runtime')])

  # Create and copy pkg.
  PKG = join(SDK_tmp, 'pkg')
  os.makedirs(PKG)

  #
  # Create and populate pkg/{args, intl, logging, unittest}
  #

  for library in ['args', 'htmlescape', 'dartdoc', 'intl', 'logging', 
                  'unittest']:
    copytree(join(HOME, 'pkg', library), join(PKG, library),
             ignore=ignore_patterns('*.svn', 'doc', 'docs',
                                    '*.py', '*.gypi', '*.sh'))

  # Fixup dartdoc
  ReplaceInFiles([
      join(PKG, 'dartdoc', 'dartdoc.dart'),
    ], [
      ("final bool IN_SDK = false;",
       "final bool IN_SDK = true;"),
    ])


  # Create and copy tools.
  UTIL = join(SDK_tmp, 'util')
  os.makedirs(UTIL)

  if ShouldCopyAnalyzer():
    # Create and copy Analyzer library into 'util'
    ANALYZER_DEST = join(UTIL, 'analyzer')
    os.makedirs(ANALYZER_DEST)

    analyzer_src_jar = join(ANALYZER_HOME, 'util', 'analyzer',
                            'dart_analyzer.jar')
    analyzer_dest_jar = join(ANALYZER_DEST, 'dart_analyzer.jar')
    copyfile(analyzer_src_jar, analyzer_dest_jar)

    jarsToCopy = [ join("args4j", "2.0.12", "args4j-2.0.12.jar"),
                   join("guava", "r09", "guava-r09.jar"),
                   join("json", "r2_20080312", "json.jar") ]
    for jarToCopy in jarsToCopy:
        dest_dir = join (ANALYZER_DEST, os.path.dirname(jarToCopy))
        os.makedirs(dest_dir)
        dest_file = join (ANALYZER_DEST, jarToCopy)
        src_file = join(ANALYZER_HOME, 'util', 'analyzer', jarToCopy)
        copyfile(src_file, dest_file)

  # Create and populate util/pub.
  copytree(join(HOME, 'utils', 'pub'), join(UTIL, 'pub'),
           ignore=ignore_patterns('.svn', 'sdk'))

  revision = utils.GetSVNRevision()

  # Copy dart2js.
  CopyDart2Js(build_dir, SDK_tmp, revision)

  # Write the 'revision' file
  if revision is not None:
    with open(os.path.join(SDK_tmp, 'revision'), 'w') as f:
      f.write(revision + '\n')
      f.close()

  move(SDK_tmp, SDK)
  utils.Touch(os.path.join(SDK, 'create.stamp'))

if __name__ == '__main__':
  sys.exit(Main(sys.argv))
