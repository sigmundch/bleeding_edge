// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('game_of_life');

#import('dart:html');
#import('dart:isolate');
#import('dart:math', prefix: 'Math');
#import('package:dart-web-components/lib/js_polyfill/web_components.dart');

#source('components/components.dart');

void main() {
  _componentsSetup();
}

void _componentsSetup() {
  Map<String, Function> map = {
    'x-cell' : () => new Cell.component(),
    'x-control-panel' : () => new ControlPanel.component(),
    'x-game-of-life' : () => new GameOfLife.component()
  };
  initializeComponents((String name) => map[name], true);
}
