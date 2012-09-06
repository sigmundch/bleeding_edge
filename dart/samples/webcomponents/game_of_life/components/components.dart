// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

typedef void Ping();

// We've done things this way because we can't have default values for fields
// inside a web component right now (see bug 4957).

/** How should the (square) board be by default? Measured in cells/side. */
final int DEFAULT_GAME_SIZE = 40;

/**
 * How many pixels long is the side of a cell by default?
 * (Note: must match the CSS!)
 */
final int DEFAULT_CELL_SIZE = 20;

/** How many pixels from the game should the control panel be by default? */
final int DEFAULT_PANEL_OFFSET = 20;

/** How many milliseconds between steps by default? */
final int DEFAULT_STEP_TIME = 100;

/**
 * A single cell in the Game Of Life. Listens to a GameOfLife parent component
 * to get a clock tick, and interacts on its neighbors on every tick to move the
 * game one step forward.
 */
class Cell extends DivElementImpl implements WebComponent, Hashable {
  Collection<Cell> neighbors;
  ShadowRoot _root;
  GameOfLife game;
  bool aliveThisStep;
  bool aliveNextStep;

  // BEGIN AUTOGENERATED CODE
  static WebComponentFactory _$constr;
  factory Cell.component() {
    if(_$constr == null) {
      _$constr = () => new Cell._internal();
    }
    var t1 = new DivElement();
    t1.attributes['is'] = 'x-cell';
    rewirePrototypeChain(t1, _$constr, 'Cell');
    return t1;
  }

  factory Cell() {
    return manager.expandHtml('<div is="x-cell"></div>');
  }

  Cell._internal();
  // END AUTOGENERATED CODE

  void created(ShadowRoot root) {
    _root = root;
    neighbors = <Cell>[];
    classes.add('cell');

    // Cells start dead.
    aliveThisStep = false;
  }

  void inserted() { }

  /**
   * Set up event listeners and populate [neighbors] by querying [game] for this
   * cell's neighbors. Event listeners can be done here rather than dealt with
   * in [inserted] and [removed] because cells will always be gc'd if removed
   * from the DOM.
   */
  void bound() {
    on.click.add((event) {
      classes.toggle('alive');
      aliveThisStep = !aliveThisStep;
    });

    game.on.step.add(step);
    game.on.resolve.add(resolve);

    // find neighbors
    var parsedCoordinates = this.id.substring(1).split('y');
    var x = Math.parseInt(parsedCoordinates[0]);
    var y = Math.parseInt(parsedCoordinates[1]);
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        if (game.inGrid(x + dx, y + dy) && !(dx == 0 && dy == 0)) {
          var neighbor = game._query('#x${x + dx}y${y + dy}');
          neighbors.add(neighbor);
        }
      }
    }
  }

  
  void attributeChanged(String name, String oldValue, String newValue) { }

  void removed() { }

  /**
   * Each turn of the game is broken into a step and a resolve. On a step, the
   * cell queries its neighbors current states and decides whether or not will
   * be alive or dead next turn.
   */
  void step() {
    var numAlive = neighbors.filter((n) => n.aliveThisStep).length;
    // We could compress this into one line, but it's clearer this way.
    aliveNextStep = false;
    if (aliveThisStep) {
      if (numAlive == 2 || numAlive == 3) {
        aliveNextStep = true;
      }
    } else {
      if (numAlive == 3) {
        aliveNextStep = true;
      }
    }
  }

  /**
   * Each turn of the game is broken in a step and a resolve. On a resolve, the
   * cell uses the information collected in the step phase to update its state
   * and appearance -- black if alive this turn, white if dead this turn.
   */
  void resolve() {
    if (aliveNextStep) {
      classes.add('alive');
    } else {
      classes.remove('alive');
    }
    aliveThisStep = aliveNextStep;
  }
}

/** 
 * A control panel for the Game of Life. Has start, stop, and step buttons which
 * start the game, stop the game, and move the game one turn forward,
 * respectively.
 */
class ControlPanel extends DivElementImpl implements WebComponent {
  ShadowRoot _root;
  GameOfLife game;

  // BEGIN AUTOGENERATED CODE
  static WebComponentFactory _$constr;
  factory ControlPanel.component() {
    if(_$constr == null) {
      _$constr = () => new ControlPanel._internal();
    }
    var t1 = new DivElement();
    t1.attributes['is'] = 'x-control-panel';
    rewirePrototypeChain(t1, _$constr, 'ControlPanel');
    return t1;
  }

  factory ControlPanel() {
    return manager.expandHtml('<div is="x-control-panel"></div>');
  }

  ControlPanel._internal();
  // END AUTOGENERATED CODE

  void created(ShadowRoot root) {
    _root = root;
  }

  void inserted() { }

  /** 
   * Sets up event listeners for the buttons. This must be done here rather than
   * in [inserted] because the events must propogate up to [game].
   */
  void bound() { 
    _root.query('#start').on.click.add((e) => game.run());
    _root.query('#stop').on.click.add((e) => game.stop());
    _root.query('#step').on.click.add((e) => game.step());
  }

  void attributeChanged(String name, String oldValue, String newValue) { }

  void removed() { }
}

/** 
 * A Game of Life component, containing an interactive implementation of
 * Conway's Game of Life.
 */
class GameOfLife extends DivElementImpl implements WebComponent {

  // Implementation Notes: The game consists of a control panel and a board
  // composed of cells. Each cell is a web component, and the control panel is a
  // web component. The top-level widget populates the board with cells and
  // provides a clock tick to which the cells listen. It exposes API to stop and
  // start that tick, which the control panel binds to its buttons. Aside
  // from the tick, no state is maintained in the top level widget -- each cell
  // maintains its own state and talks to its neighbors to move the game
  // forward.

  // TODO(samhop): implement wraparound on the board.
  ShadowRoot _root;
  GameOfLifeEvents on;
  Timer timer;
  int lastRefresh;
  bool _stop;
  StyleElement computedStyles;

  // These cannot be initialized here right now -- see bug 4957.

  /** How should the (square) board be? Measured in cells/side. */
  int GAME_SIZE;

  /** How many pixels long is the side of a cell? (Note: must match the CSS!) */
  int CELL_SIZE;

  /** How many pixels from the game should the control panel be? */
  int PANEL_OFFSET;

  /** How many milliseconds between steps? */
  int _stepTime;

  void set stepTime(int time) => _stepTime = time;

  // BEGIN AUTOGENERATED CODE
  static WebComponentFactory _$constr;
  factory GameOfLife.component() {
    if(_$constr == null) {
      _$constr = () => new GameOfLife._internal();
    }
    var t1 = new DivElement();
    t1.attributes['is'] = 'x-game-of-life';
    rewirePrototypeChain(t1, _$constr, 'GameOfLife');
    return t1;
  }

  factory GameOfLife() {
    return manager.expandHtml('<div is="x-game-of-life"></div>');
  }

  GameOfLife._internal();
  // END AUTOGENERATED CODE

  /** On creation, initialize fields and then populate the game. */
  void created(ShadowRoot root) {
    _root = root;
    on = new GameOfLifeEvents();
    lastRefresh = 0;
    
    // At present we must do this initialization here -- see bug 4957.
    GAME_SIZE = DEFAULT_GAME_SIZE;
    CELL_SIZE = DEFAULT_CELL_SIZE;
    PANEL_OFFSET = DEFAULT_PANEL_OFFSET;
    _stepTime = DEFAULT_STEP_TIME;

    _populate();
  }

  void inserted() { }

  void attributeChanged(String name, String oldValue, String newValue) { }

  void removed() { }

  /** 
   * Returns the results of querying on [selector] beneath [_root]. Needed by
   * Cells to determine their neighbors.
   */
  _query(String selector) {
    return _root.query(selector);
  }

  /** Stop ticking. */
  void stop() {
    _stop = true;
  }

  /** 
   * Tick once, then if we haven't been told to stop, call set up a
   * requestAnimationFrame callback to tick again.
   */
  void _increment(int time) {
    if (new Date.now().millisecondsSinceEpoch - lastRefresh > _stepTime) {
      on.step.forEach((f) => f());
      on.resolve.forEach((f) => f());
      lastRefresh = new Date.now().millisecondsSinceEpoch;
    }
    if (!_stop) {
       window.requestAnimationFrame(_increment);
    }
  }

  /** Start the game. */
  void run() {
    _stop = false;
    window.requestAnimationFrame(_increment);
  }

  /** 
   * Move the game one step forward. If the game was running, stop the game
   * beforehand.
   */
  void step() {
    _stop = true;
    _increment(null);
  }

  /** 
   * Fill the game board with cells, position them appropriately, position the 
   * control panel, and bind all subcomponents.
   */
  void _populate() {
    // set up position styles
    computedStyles = new StyleElement();
    _root.nodes.add(computedStyles);
    var positionStyles = '';
    _forEachCell((i, j) => 
        positionStyles = _addPositionId(positionStyles, i, j));
    computedStyles.innerHTML = positionStyles;

    // add cells
    _forEachCell((i, j) {
      var cell = new Cell();
      cell.game = this;
      cell.id = 'x${i}y${j}';
      _root.nodes.add(cell);
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

    // bind the control panel
    var controlPanel = _root.query('div[is="x-control-panel"]');
    controlPanel.game = this;
    controlPanel.bound();

    // TODO(samhop): fix webcomponents.dart so that attributes are preserved.
    _root.query('div').id = 'panel';

    // TODO(samhop) fix webcomponents.dart so we don't have to do this
    _root.queryAll('.cell').forEach((cell) => cell.bound());
  }

  /** 
   * Calls f exactly once on all pairs (i, j) for ints i, j between 0 and
   * [GAME_SIZE] - 1, inclusive.
   */
  void _forEachCell(f) {
    for (var i = 0; i < GAME_SIZE; i++) {
      for (var j = 0; j < GAME_SIZE; j++) {
        f(i, j);
      }
    }
  }
  
  /**
   * Appends correct cell positioning information for cell ([i], [j]) to [curr].
   */
  String _addPositionId(String curr, int i, int j) =>
      '''
      $curr
      #x${i}y${j} {
        left: ${CELL_SIZE * i}px;
        top: ${CELL_SIZE * j}px;
      }
      ''';

  /** 
   * Is the coordinate ([x],[y]) in the game grid, given the current
   * [GAME_SIZE]?
   */
  bool inGrid(x, y) =>
    (x >=0 && y >=0 && x < GAME_SIZE && y < GAME_SIZE);
}

/** Events container for a GameOfLife. */
class GameOfLifeEvents implements Events {
  List<Ping> _step_list;
  List<Ping> _resolve_list;

  GameOfLifeEvents() 
      : _step_list = <Ping>[],
        _resolve_list = <Ping>[];

  List<Ping> get step => _step_list;
  List<Ping> get resolve => _resolve_list;
}
