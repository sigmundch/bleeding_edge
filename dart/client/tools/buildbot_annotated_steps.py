# Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

#!/usr/bin/python

# Copyright (c) 2011 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Dart client buildbot steps

Compiles dart client apps with dartc, and run the client tests both in headless
chromium and headless dartium.
"""

import os
import re
import socket
import subprocess
import sys
import shutil
import glob

BUILDER_NAME = 'BUILDBOT_BUILDERNAME'
BUILDER_CLOBBER = 'BUILDBOT_CLOBBER'
REVISION = 'BUILDBOT_REVISION'

# latest dartium location
DARTIUM_VERSION_FILE = 'client/tests/drt/LAST_VERSION'
DARTIUM_V_MATCHER = (
    'gs://dartium-archive/[^/]*/dartium-\w*-inc-([0-9]*).([0-9]*).zip')

def GetBuildInfo():
  """Returns a tuple (name, version, mode) where:
    - name: A name for the build - the buildbot host if a buildbot.
    - version: A version string corresponding to this build.
  """
  name = None
  version = None

  # Populate via builder environment variables.
  name = os.environ.get(BUILDER_NAME)
  version = os.environ.get(REVISION)

  # Fall back if not on builder.
  if not name:
    name = socket.gethostname().split('.')[0]
  if not version:
    # In Windows we need to run in the shell, so that we have all the
    # environment variables available.
    pipe = subprocess.Popen(
        ['svnversion', '-n'], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        shell=True)
    output = pipe.communicate()
    if pipe.returncode == 0:
      version = output[0]
    else:
      version = 'unknown'
  return (name, version)


def GetUtils():
  '''
  dynamically get the utils module
  We use a dynamic import for tools/util.py because we derive its location
  dynamically using sys.argv[0]. This allows us to run this script from
  different directories.

  args:
  '''
  sys.path.append(os.path.abspath(os.path.join('.', 'tools')))
  utils = __import__('utils')
  return utils

def GetOutDir(utils, mode):
  '''
  get the location to place the output

  args:
  utils - the tools/utils.py module
  mode - the mode release or debug
  '''
  return utils.GetBuildRoot(utils.GuessOS(), mode, utils.ARCH_GUESS)

def ProcessTools(mode, name, version):
  '''
  build and test the tools

  args:
  srcpath - the location of the source code to build
  mode - the mode release or debug
  version - the svn version of the currently checked out code
  '''
  print 'ProcessTools'

  toolsBuildScript = os.path.join('.', 'editor', 'build', 'build.py')

  #TODO: debug statements to be removed in the future.
  print "mode = " + mode
  print "name = " + name
  print "version = " + version
  print "toolsBuildScript = " + os.path.abspath(toolsBuildScript)

  utils = GetUtils()
  outdir = GetOutDir(utils, mode)
  cmds = [sys.executable, toolsBuildScript,
          '--mode=' + mode, '--revision=' + version,
          '--name=' + name, '--out=' + outdir]
  local_env = os.environ
  if 'linux' in name:
    javahome = os.path.join(os.path.expanduser('~'), 'jdk1.6.0_25')
    local_env['JAVA_HOME'] = javahome
    local_env['PATH'] = (os.path.join(javahome, 'bin') +
                         os.pathsep + local_env['PATH'])

  return subprocess.call(cmds, env=local_env)

def ProcessCompiler(name):
  '''
  build and test the compiler
  '''
  print 'ProcessCompiler'
  has_shell=False
  if 'windows' in name:
    # In Windows we need to run in the shell, so that we have all the
    # environment variables available.
    has_shell=True
  return subprocess.call([sys.executable,
      os.path.join('utils', 'compiler', 'buildbot.py')],
      env=os.environ, shell=has_shell)

def FixJavaHome():
  buildbot_javahome = os.getenv('BUILDBOT_JAVA_HOME')
  if buildbot_javahome:
    current_pwd = os.getenv('PWD')
    java_home = os.path.join(current_pwd, buildbot_javahome)
    os.environ['JAVA_HOME'] = java_home
    print 'Setting java home to'
    print java_home

def ClobberBuilder():
  """ Clobber the builder before we do the build.
  Args:
     - mode: either 'debug' or 'release'
  """
  cmd = [sys.executable,
         './tools/clean_output_directory.py']
  print 'Clobbering %s' % (' '.join(cmd))
  return subprocess.call(cmd)

def GetShouldClobber():
  return os.environ.get(BUILDER_CLOBBER) == "1"

def main():
  print 'main'
  if len(sys.argv) == 0:
    print 'Script pathname not known, giving up.'
    return 1

  scriptdir = os.path.dirname(sys.argv[0])
  # Get at the top-level directory. This script is in client/tools
  os.chdir(os.path.abspath(os.path.join(scriptdir, os.pardir, os.pardir)))

  if GetShouldClobber():
    print '@@@BUILD_STEP Clobber@@@'
    status = ClobberBuilder()
    if status != 0:
      print '@@@STEP_FAILURE@@@'
      return status


  #TODO(sigmund): remove this indirection once we update our bots
  (name, version) = GetBuildInfo()
  if name.startswith('dart-editor'):
    # TODO (danrubel) Fix dart-editor builds so that we can call FixJavaHome() before the build
    status = ProcessTools('release', name, version)
  else:
    # The buildbot will set a BUILDBOT_JAVA_HOME relative to the dart
    # root directory, set JAVA_HOME based on that.
    FixJavaHome()
    status = ProcessCompiler(name)

  if status:
    print '@@@STEP_FAILURE@@@'

  return status


if __name__ == '__main__':
  sys.exit(main())
