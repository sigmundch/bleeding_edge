#!/usr/bin/python

# Copyright (c) 2011 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Dart2js buildbot steps

Runs tests for the  dart2js compiler.
"""

import platform
import optparse
import os
import re
import shutil
import subprocess
import sys

BUILDER_NAME = 'BUILDBOT_BUILDERNAME'
BUILDER_CLOBBER = 'BUILDBOT_CLOBBER'


DART_PATH = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DART2JS_BUILDER = (
    r'dart2js-(linux|mac|windows)-(debug|release)(-([a-z]+))?-?(\d*)-?(\d*)')
WEB_BUILDER = (
    r'web-(ie|ff|safari|chrome|opera)-(win7|win8|mac|linux)-?(\d*)-?(\d*)')

NO_COLOR_ENV = dict(os.environ)
NO_COLOR_ENV['TERM'] = 'nocolor'

def GetBuildInfo():
  """Returns a tuple (compiler, runtime, mode, system, option) where:
    - compiler: 'dart2js' or None when the builder has an incorrect name
    - runtime: 'd8', 'ie', 'ff', 'safari', 'chrome', 'opera'
    - mode: 'debug' or 'release'
    - system: 'linux', 'mac', or 'win7'
    - option: 'checked'
  """
  parser = optparse.OptionParser()
  parser.add_option('-n', '--name', dest='name', help='The name of the build'
      'bot you would like to emulate (ex: web-chrome-win7)', default=None)
  args, _ = parser.parse_args()

  compiler = None
  runtime = None
  mode = None
  system = None
  builder_name = os.environ.get(BUILDER_NAME)
  option = None
  shard_index = None
  total_shards = None
  is_buildbot = True
  if not builder_name:
    # We are not running on a buildbot.
    is_buildbot = False
    if args.name:
      builder_name = args.name
    else:
      print 'Use -n $BUILDBOT_NAME for the bot you would like to emulate.'
      sys.exit(1)

  if builder_name:
    dart2js_pattern = re.match(DART2JS_BUILDER, builder_name)
    web_pattern = re.match(WEB_BUILDER, builder_name)

    if dart2js_pattern:
      compiler = 'dart2js'
      runtime = 'd8'
      system = dart2js_pattern.group(1)
      mode = dart2js_pattern.group(2)
      option = dart2js_pattern.group(4)
      shard_index = dart2js_pattern.group(5)
      total_shards = dart2js_pattern.group(6)

    elif web_pattern:
      compiler = 'dart2js'
      runtime = web_pattern.group(1)
      system = web_pattern.group(2)
      mode = 'release'
      shard_index = web_pattern.group(3)
      total_shards = web_pattern.group(4)

  if system == 'windows':
    system = 'win7'

  if (system == 'win7' and platform.system() != 'Windows') or (
      system == 'mac' and platform.system() != 'Darwin') or (
      system == 'linux' and platform.system() != 'Linux'):
    print ('Error: You cannot emulate a buildbot with a platform different '
        'from your own.')
    sys.exit(1)
  return (compiler, runtime, mode, system, option, shard_index, total_shards,
          is_buildbot)


def NeedsXterm(compiler, runtime):
  return runtime in ['ie', 'chrome', 'safari', 'opera', 'ff', 'drt']

def TestStep(name, mode, system, compiler, runtime, targets, flags):
  print '@@@BUILD_STEP %s %s tests: %s %s@@@' % (name, compiler, runtime,
      ' '.join(flags))
  sys.stdout.flush()
  if NeedsXterm(compiler, runtime) and system == 'linux':
    cmd = ['xvfb-run', '-a']
  else:
    cmd = []

  user_test = os.environ.get('USER_TEST', 'no')

  cmd.extend([sys.executable,
              os.path.join(os.curdir, 'tools', 'test.py'),
              '--mode=' + mode,
              '--compiler=' + compiler,
              '--runtime=' + runtime,
              '--time',
              '--use-sdk',
              '--report'])

  if user_test == 'yes':
    cmd.append('--progress=color')
  else:
    cmd.extend(['--progress=buildbot', '-v'])

  if flags:
    cmd.extend(flags)
  cmd.extend(targets)

  print 'running %s' % (' '.join(cmd))
  exit_code = subprocess.call(cmd, env=NO_COLOR_ENV)
  if exit_code != 0:
    print '@@@STEP_FAILURE@@@'
  return exit_code


def BuildSDK(mode, system):
  """ build the SDK.
   Args:
     - mode: either 'debug' or 'release'
     - system: either 'linux', 'mac', or 'win7'
  """
  os.chdir(DART_PATH)

  args = [sys.executable, './tools/build.py', '--mode=' + mode, 'create_sdk']
  print 'running %s' % (' '.join(args))
  return subprocess.call(args, env=NO_COLOR_ENV)


def TestCompiler(runtime, mode, system, option, flags, is_buildbot):
  """ test the compiler.
   Args:
     - runtime: either 'd8', or one of the browsers, see GetBuildInfo
     - mode: either 'debug' or 'release'
     - system: either 'linux', 'mac', or 'win7'
     - option: 'checked'
     - flags: extra flags to pass to test.dart
     - is_buildbot: true if we are running on a real buildbot instead of
       emulating one.
  """

  # Make sure we are in the dart directory
  os.chdir(DART_PATH)

  if system.startswith('win') and runtime == 'ie':
    # We don't do proper sharding on the IE bots, since the runtime is
    # long for both. We have a "fast bot" and a "slow bot" that run specific
    # tests instead.
    for i in flags:
      if i.startswith('--shard='):
        bot_num = i.split('=')[1]
    # There should not be more than one InternetExplorerDriver instance
    # running at a time. For details, see
    # http://code.google.com/p/selenium/wiki/InternetExplorerDriver.
    flags = (filter(lambda(item): not item.startswith('--shard'), flags) +
        ['-j1'])

  def GetPath(runtime):
    """ Helper to get the path to the Chrome or Firefox executable for a
    particular platform on the buildbot. Throws a KeyError if runtime is not
    either 'chrome' or 'ff'."""
    if system == 'mac':
      partDict = {'chrome': 'Google\\ Chrome', 'ff': 'Firefox'}
      mac_path = '/Applications/%s.app/Contents/MacOS/%s'
      path_dict = {'chrome': mac_path % (partDict[runtime], partDict[runtime]),
          'ff': mac_path % (partDict[runtime], partDict[runtime].lower())}
    elif system == 'linux':
      path_dict = {'ff': 'firefox', 'chrome': 'google-chrome'}
    else:
      # Windows.
      path_dict = {'ff': os.path.join('C:/', 'Program Files (x86)',
          'Mozilla Firefox', 'firefox.exe'),
          'chrome': os.path.join('C:/', 'Users', 'chrome-bot', 'AppData',
          'Local', 'Google', 'Chrome', 'Application', 'chrome.exe')}
    return path_dict[runtime]

  if system == 'linux' and runtime == 'chrome':
    # TODO(ngeoffray): We should install selenium on the buildbot.
    runtime = 'drt'
  elif (runtime == 'ff' or runtime == 'chrome') and is_buildbot:
    # Print out browser version numbers if we're running on the buildbot (where
    # we know the paths to these browser installations).
    version_query_string = '"%s" --version' % GetPath(runtime)
    if runtime == 'ff' and system == 'win7':
      version_query_string += '| more'
    elif runtime == 'chrome' and system == 'win7':
      version_query_string = ('''reg query "HKCU\\Software\\Microsoft\\''' +
          '''Windows\\CurrentVersion\\Uninstall\\Google Chrome" /v Version''')
    p = subprocess.Popen(version_query_string,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    output, stderr = p.communicate()
    output = output.split()
    try:
      print 'Version of %s: %s' % (runtime, output[-1])
    except IndexError:
      # Failed to obtain version information. Continue running tests.
      pass

  if option == 'checked': flags = flags + ['--host-checked']

  if runtime == 'd8':
    # The dart2js compiler isn't self-hosted (yet) so we run its
    # unit tests on the VM. We avoid doing this on the builders
    # that run the browser tests to cut down on the cycle time.
    TestStep("dart2js_unit", mode, system, 'none', 'vm', ['dart2js'], flags)

  if not (system.startswith('win') and runtime == 'ie'):
    # Run the default set of test suites.
    TestStep("dart2js", mode, system, 'dart2js', runtime, [], flags)

    # TODO(kasperl): Consider running peg and css tests too.
    extras = ['dart2js_extra', 'dart2js_native']
    TestStep("dart2js_extra", mode, system, 'dart2js', runtime, extras, flags)
  else:
    if bot_num == '1':
      TestStep("dart2js", mode, system, 'dart2js', runtime, ['html'], flags)
    else:
      TestStep("dart2js", mode, system, 'dart2js', runtime, ['dartc',
          'samples', 'standalone', 'corelib', 'co19', 'language', 'isolate',
          'vm', 'json', 'benchmark_smoke', 'dartdoc', 'utils', 'pub', 'lib'],
          flags)
      extras = ['dart2js_extra', 'dart2js_native']
      TestStep("dart2js_extra", mode, system, 'dart2js', runtime, extras,
          flags)

  return 0

def _DeleteFirefoxProfiles(directory):
  """Find all the firefox profiles in a particular directory and delete them."""
  for f in os.listdir(directory):
    item = os.path.join(directory, f)
    if os.path.isdir(item) and f.startswith('tmp'):
      subprocess.Popen('rm -rf %s' % item, shell=True)

def CleanUpTemporaryFiles(system, browser):
  """For some browser (selenium) tests, the browser creates a temporary profile
  on each browser session start. On Windows, generally these files are
  automatically deleted when all python processes complete. However, since our
  buildbot slave script also runs on python, we never get the opportunity to
  clear out the temp files, so we do so explicitly here. Our batch browser
  testing will make this problem occur much less frequently, but will still
  happen eventually unless we do this.

  This problem also occurs with batch tests in Firefox. For some reason selenium
  automatically deletes the temporary profiles for Firefox for one browser,
  but not multiple ones when we have many open batch tasks running. This
  behavior has not been reproduced outside of the buildbots.

  Args:
     - system: either 'linux', 'mac', or 'win7'
     - browser: one of the browsers, see GetBuildInfo
  """
  if system == 'win7':
    shutil.rmtree('C:\\Users\\chrome-bot\\AppData\\Local\\Temp',
        ignore_errors=True)
  elif browser == 'ff':
    # Note: the buildbots run as root, so we can do this without requiring a
    # password. The command won't actually work on regular machines without
    # root permissions.
    _DeleteFirefoxProfiles('/tmp')
    _DeleteFirefoxProfiles('/var/tmp')

def ClobberBuilder(mode):
  """ Clobber the builder before we do the build.
  Args:
     - mode: either 'debug' or 'release'
  """
  cmd = [sys.executable,
         './tools/clean_output_directory.py',
         '--mode=' + mode]
  print 'Clobbering %s' % (' '.join(cmd))
  return subprocess.call(cmd, env=NO_COLOR_ENV)

def GetShouldClobber():
  return os.environ.get(BUILDER_CLOBBER) == "1"

def main():
  if len(sys.argv) == 0:
    print 'Script pathname not known, giving up.'
    return 1

  (compiler, runtime, mode, system, option, shard_index, total_shards,
      is_buildbot) = GetBuildInfo()
  shard_description = ""
  if shard_index:
    shard_description = " shard %s of %s" % (shard_index, total_shards)
  print "compiler: %s, runtime: %s mode: %s, system: %s, option: %s%s" % (
      compiler, runtime, mode, system, option, shard_description)
  if compiler is None:
    return 1

  if GetShouldClobber():
    print '@@@BUILD_STEP Clobber@@@'
    status = ClobberBuilder(mode)
    if status != 0:
      print '@@@STEP_FAILURE@@@'
      return status

  print '@@@BUILD_STEP build sdk@@@'
  status = BuildSDK(mode, system)
  if status != 0:
    print '@@@STEP_FAILURE@@@'
    return status

  test_flags = []
  if shard_index:
    test_flags = ['--shards=%s' % total_shards, '--shard=%s' % shard_index]

  # First we run all the regular tests.
  status = TestCompiler(runtime, mode, system, option, test_flags,
                        is_buildbot)

  # We only run checked mode tests when the host is not in checked mode.
  if status == 0 and option != 'checked' and runtime == 'd8':
    status = TestCompiler(runtime, mode, system, option,
                          test_flags + ['--checked'], is_buildbot)

  if runtime != 'd8': CleanUpTemporaryFiles(system, runtime)
  if status != 0: print '@@@STEP_FAILURE@@@'
  return status

if __name__ == '__main__':
  sys.exit(main())
