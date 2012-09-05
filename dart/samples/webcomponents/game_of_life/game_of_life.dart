// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('game_of_life');

#import('dart:html');
#import('dart:isolate');
#import('dart:math', prefix: 'Math');
#import('package:dart-web-components/webcomponents.dart');

#source('components/components.dart');

typedef void Ping();

/** How should the (square) board be? Measured in cells/side. */
int GAME_SIZE = 40;

/** How many pixels long is the side of a cell? (Note: must match the CSS!) */
int CELL_SIZE = 20;

/** How many pixels from the game should the control panel be? */
int PANEL_OFFSET = 20;

/** Singletons */
CellCoordinator get COORDINATOR {
  if (CellCoordinator._ONLY == null) {
    CellCoordinator._ONLY = new CellCoordinator._internal();
  }
  return CellCoordinator._ONLY;
}

void main() {
  _componentsSetup();

  // TODO(samhop): fix webcomponents.dart so that attributes are preserved.
  query('div').id = 'panel';

  COORDINATOR.populate();
}

void _componentsSetup() {
  Map<String, Function> map = {
    'x-cell' : () => new Cell.component(),
    'x-control-panel' : () => new ControlPanel.component()
  };
  initializeComponents((String name) => map[name], true);
}

class CellCoordinator {
  CellEvents on;
  Timer timer;
  int lastRefresh;
  bool _stop;
  StyleElement computedStyles;

  void stop() {
    _stop = true;
  }

  CellCoordinator._internal() 
    : on = new CellCoordinatorEvents(),
      lastRefresh = 0;

  void increment(int time) {
   // if (new Date.now().millisecondsSinceEpoch - lastRefresh > 200) {
      on.step.forEach((f) => f());
      on.resolve.forEach((f) => f());
      lastRefresh = new Date.now().millisecondsSinceEpoch;
    // }
    if (!_stop) {
       window.requestAnimationFrame(increment);
    }
  }

  void run() {
    _stop = false;
    window.requestAnimationFrame(increment);
  }

  void step() {
    _stop = true;
    increment(null);
  }

  void populate() {
    // set up position styles
    computedStyles = new StyleElement();
    document.body.nodes.add(computedStyles);
    var positionStyles = '';
    _forEachCell((i, j) => 
        positionStyles = _addPositionId(positionStyles, i, j));
    computedStyles.innerHTML = positionStyles;

    // add cells
    _forEachCell((i, j) {
      var cell = new Cell();
      cell.coordinator = this;
      cell.id = 'x${i}y${j}';
      document.body.nodes.add(cell);
    });

    // position the control panel
    var panelStyle = 
        '''
        #panel {
          top: ${CELL_SIZE * GAME_SIZE + PANEL_OFFSET}px;
          left: ${PANEL_OFFSET}px;
        }
        ''';
    computedStyles.innerHTML = '${computedStyles.innerHTML}\n$panelStyle';
    
    print(computedStyles.innerHTML);
    

    // TODO(samhop) fix webcomponents.dart so we don't have to do this
    queryAll('.cell').forEach((cell) => cell.bound());
  }

  static _forEachCell(f) {
    for (var i = 0; i < GAME_SIZE; i++) {
      for (var j = 0; j < GAME_SIZE; j++) {
        f(i, j);
      }
    }
  }
  
  // Singleton -- there is only one CellCoordinator
  static CellCoordinator _ONLY;

  static String _addPositionId(curr, i, j) =>
      '''
      $curr
      #x${i}y${j} {
        left: ${CELL_SIZE * i}px;
        top: ${CELL_SIZE * j}px;
      }
      ''';
}

class CellCoordinatorEvents implements Events {
  List<Ping> _step_list;
  List<Ping> _resolve_list;

  CellCoordinatorEvents() 
      : _step_list = <Ping>[],
        _resolve_list = <Ping>[];

  List<Ping> get step => _step_list;
  List<Ping> get resolve => _resolve_list;
}
