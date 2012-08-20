// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * The main entrypoint for the pub command line application.
 */
#library('pub');

#import('../../pkg/args/args.dart');
#import('dart:io');
#import('io.dart');
#import('command_help.dart');
#import('command_install.dart');
#import('command_list.dart');
#import('command_update.dart');
#import('command_version.dart');
#import('entrypoint.dart');
#import('git_source.dart');
#import('package.dart');
#import('pubspec.dart');
#import('repo_source.dart');
#import('sdk_source.dart');
#import('source.dart');
#import('source_registry.dart');
#import('system_cache.dart');
#import('utils.dart');
#import('version.dart');

Version get pubVersion() => new Version(0, 0, 0);

/**
 * The commands that Pub understands.
 */
Map<String, PubCommand> get pubCommands() => {
  'help': new HelpCommand(),
  'list': new ListCommand(),
  'install': new InstallCommand(),
  'update': new UpdateCommand(),
  'version': new VersionCommand()
};

/**
 * The parser for arguments that are global to Pub rather than specific to a
 * single command.
 */
ArgParser get pubArgParser() {
  var parser = new ArgParser();
  parser.addFlag('help', abbr: 'h', negatable: false,
    help: 'Prints this usage information');
  parser.addFlag('version', negatable: false,
    help: 'Prints the version of Pub');
  parser.addFlag('trace', help: 'Prints a stack trace when an error occurs');
  return parser;
}

main() {
  var globalOptions;
  try {
    globalOptions = pubArgParser.parse(new Options().arguments);
  } catch (FormatException e) {
    printUsage(description: e.message);
    return;
  }

  if (globalOptions['version']) {
    printVersion();
    return;
  }

  if (globalOptions['help'] || globalOptions.rest.isEmpty()) {
    printUsage();
    return;
  }

  // TODO(nweiz): Have a fallback for this this out automatically once 1145 is
  // fixed.
  var sdkDir = Platform.environment['DART_SDK'];
  var cacheDir;
  if (Platform.environment.containsKey('PUB_CACHE')) {
    cacheDir = Platform.environment['PUB_CACHE'];
  } else {
    // TODO(nweiz): Choose a better default for Windows.
    cacheDir = '${Platform.environment['HOME']}/.pub-cache';
  }

  var cache = new SystemCache(cacheDir);
  cache.register(new SdkSource(sdkDir));
  cache.register(new GitSource());
  cache.register(new RepoSource());
  // TODO(nweiz): Make 'repo' the default once pub.dartlang.org exists
  cache.sources.setDefault('sdk');

  // Select the command.
  var command = pubCommands[globalOptions.rest[0]];
  if (command == null) {
    printError('Unknown command "${globalOptions.rest[0]}".');
    printError('Run "pub help" to see available commands.');
    exit(64); // See http://www.freebsd.org/cgi/man.cgi?query=sysexits.
    return;
  }

  var commandArgs =
    globalOptions.rest.getRange(1, globalOptions.rest.length - 1);
  command.run(cache, globalOptions, commandArgs);
}

/** Displays usage information for the app. */
void printUsage([String description = 'Pub is a package manager for Dart.']) {
  print(description);
  print('');
  print('Usage: pub command [arguments]');
  print('');
  print('Global options:');
  print(pubArgParser.getUsage());
  print('');
  print('The commands are:');

  // Show the commands sorted.
  // TODO(rnystrom): A sorted map would be nice.
  int length = 0;
  var names = <String>[];
  for (var command in pubCommands.getKeys()) {
    length = Math.max(length, command.length);
    names.add(command);
  }

  names.sort((a, b) => a.compareTo(b));

  for (var name in names) {
    print('  ${padRight(name, length)}   ${pubCommands[name].description}');
  }

  print('');
  print('Use "pub help [command]" for more information about a command.');
}

void printVersion() {
  print('Pub $pubVersion');
}

class PubCommand {
  SystemCache cache;
  ArgResults globalOptions;
  ArgResults commandOptions;

  Entrypoint entrypoint;

  /**
   * A one-line description of this command.
   */
  abstract String get description();

  /**
   * How to invoke this command (e.g. `"pub install [package]"`).
   */
  abstract String get usage();

  /**
   * Override this to define command-specific options. The results will be made
   * available in [commandOptions].
   */
  ArgParser get commandParser() => new ArgParser();

  void run(SystemCache cache_, ArgResults globalOptions_,
      List<String> commandArgs) {
    cache = cache_;
    globalOptions = globalOptions_;

    try {
     commandOptions = commandParser.parse(commandArgs);
    } catch (FormatException e) {
      this.printUsage(description: e.message);
      return;
    }

    handleError(error, trace) {
      // This is basically the top-level exception handler so that we don't
      // spew a stack trace on our users.
      // TODO(rnystrom): Add --trace flag so stack traces can be enabled for
      // debugging.
      var message = error.toString();

      // TODO(rnystrom): The default exception implementation class puts
      // "Exception:" in the output, so strip that off.
      if (message.startsWith("Exception: ")) {
        message = message.substring("Exception: ".length);
      }

      printError(message);
      if (globalOptions['trace'] && trace != null) {
        printError(trace);
      }
      return true;
    }

    // TODO(rnystrom): Will eventually need better logic to walk up
    // subdirectories until we hit one that looks package-like. For now, just
    // assume the cwd is it.
    var future = Package.load(workingDir, cache.sources).chain((package) {
      entrypoint = new Entrypoint(package, cache);

      try {
        var commandFuture = onRun();
        if (commandFuture == null) return new Future.immediate(true);

        return commandFuture;
      } catch (var error, var trace) {
        handleError(error, trace);
        return new Future.immediate(null);
      }
    });
    future.handleException((e) => handleError(e, future.stackTrace));
  }

  /**
   * Override this to perform the specific command. Return a future that
   * completes when the command is done or fails if the command fails. If the
   * command is synchronous, it may return `null`.
   */
  abstract Future onRun();

  /** Displays usage information for this command. */
  void printUsage([String description]) {
    if (description == null) description = this.description;
    print(description);
    print('');
    print('Usage: $usage');

    var commandUsage = commandParser.getUsage();
    if (!commandUsage.isEmpty()) {
      print('');
      print(commandUsage);
    }
  }
}
