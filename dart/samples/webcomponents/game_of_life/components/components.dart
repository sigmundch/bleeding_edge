// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

typedef WebComponent ComponentConstructorThunk();

class Cell extends DivElementImpl implements WebComponent, Hashable {
  Collection<Cell> neighbors;
  ShadowRoot _root;
  CellCoordinator coordinator;
  bool aliveThisStep;
  bool aliveNextStep;

  bool get alive => this.classes.contains('alive');

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

  void resolve() {
    if (aliveNextStep) {
      classes.add('alive');
    } else {
      classes.remove('alive');
    }
    aliveThisStep = aliveNextStep;
  }

  static ComponentConstructorThunk _$constr;
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

  void created(ShadowRoot root) {
    _root = root;
    neighbors = <Cell>[];
    this.classes.add('cell');
  }

  void inserted() { }

  void bound() {
    on.click.add((event) {
      classes.toggle('alive');
      aliveThisStep = !aliveThisStep;
    });

    coordinator.on.step.add(step);
    coordinator.on.resolve.add(resolve);

    // find neighbors
    var parsedCoordinates = this.id.substring(1).split('y');
    var x = Math.parseInt(parsedCoordinates[0]);
    var y = Math.parseInt(parsedCoordinates[1]);
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        if (inGrid(x + dx, y + dy) && !(dx == 0 && dy == 0)) {
          var neighbor = query('#x${x + dx}y${y + dy}');
          neighbors.add(neighbor);
        }
      }
    }
  }

  static bool inGrid(x, y) =>
    (x >=0 && y >=0 && x < GAME_SIZE && y < GAME_SIZE);

  void attributeChanged(String name, String oldValue, String newValue) { }

  void removed() { }

}

class ControlPanel extends DivElementImpl implements WebComponent {
  ShadowRoot _root;
  CellCoordinator coordinator;

  static ComponentConstructorThunk _$constr;
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

  void created(ShadowRoot root) {
    _root = root;
  }

  void inserted() { 
    _root.query('#start').on.click.add((e) => COORDINATOR.run());
    _root.query('#stop').on.click.add((e) => COORDINATOR.stop());
    _root.query('#step').on.click.add((e) => COORDINATOR.step());
  }

  void attributeChanged(String name, String oldValue, String newValue) { }

  void removed() { }
}
