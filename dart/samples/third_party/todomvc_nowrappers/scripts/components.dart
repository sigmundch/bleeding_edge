// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

typedef WebComponent ComponentConstructorThunk();

/** Component representing one todo list element. */
class TodoListElement extends LIElementImpl implements WebComponent {
  final ShadowRoot _shadowRoot;
  Todo _todo;
  Todos model;
  InputElement _input;
  InputElement _toggle;
  ButtonElement _destroy;
  LabelElement _label;
  DivElement _nonEditingView;

  static ComponentConstructorThunk _$constr;
  factory TodoListElement.component() {
    if(_$constr == null) {
      _$constr = () => new TodoListElement._internal();
    }
    var t1 = new LIElement();
    t1.attributes['is'] = 'x-todo-list-element';
    rewirePrototypeChain(t1, _$constr, 'TodoListElement');
    return t1;
  }

  factory TodoListElement() {
    return manager.expandHtml('<li is="x-todo-list-element"></div>');
  }

  TodoListElement._internal();

  void set todo(t) {
    _todo = t;
    _render();
  }

  Todo get todo => _todo;

  // set appropriate classes to view mode
  void _render() {
    _label.innerHTML = todo.value;
    _input.attributes['value'] = todo.value;
    _nonEditingView.classes = ['view'];
    _input.classes.remove('todo-edit-editing');
    _input.classes.add('todo-edit-static');
  }

  void complete() {
    _label.classes.add('completed');
    _toggle.checked = true;
  }

  void uncomplete() {
    _label.classes.remove('completed');
    _toggle.checked = false;
  }

  void created(ShadowRoot shadowRoot) {
    _shadowRoot = shadowRoot;
    _input = _shadowRoot.query('.todo-edit');
    _label = _shadowRoot.query('label');
    _toggle = _shadowRoot.query('.todo-toggle');
    _nonEditingView = _shadowRoot.query('.view');
    _destroy = _shadowRoot.query('.todo-destroy');
  }

  void inserted() {
    _nonEditingView.on.doubleClick.add((event) {
      _nonEditingView.classes = ['editing'];
      _input.classes.remove('todo-edit-static');
      _input.classes.add('todo-edit-editing');
      _input.select();
    });
    _destroy.on.click.add((event) {
      model.removeTodo(todo);
    });
    _toggle.on.change.add((event) {
      if (_toggle.checked) {
        model.complete(todo);
      } else {
        model.uncomplete(todo);
      }
    });
    // TODO(samhop): This event listener should only be attached when the todo
    // is in editing mode.
    _input.on.keyPress.add((event) {
      if (event.keyCode == ENTER_KEY) { _saveTodo(); }
    });
    _input.on.blur.add((event) => _saveTodo());
    // TODO(samhop): These listeners should be detached when the component is
    // removed; otherwise presumably it won't get gc'd.
    model.on.completed.add((todo) {
      if (todo == this.todo) {
        complete();
      }
    });
    model.on.uncompleted.add((todo) {
      if (todo == this.todo) {
        uncomplete();
      }
    });
    model.on.removed.add((todo) {
      if (todo == this.todo) {
        this.remove();
      }
    });
  }

  void _saveTodo() {
    var trimmedText = _input.value.trim();
    if (trimmedText != '') {
      todo.value = trimmedText;
      _render();
    } else {
      model.removeTodo(todo);
    }
  }

  void attributeChanged(String name, String oldValue, String newValue) { }

  // We don't bother removing event listeners, since any todo that gets
  // removed should get gc'd.
  void removed() { }
}

/** Component representing a todo list app. */
class TodoList extends DivElementImpl implements WebComponent {
  ShadowRoot _shadowRoot;
  Todos _model;
  // dart:html has no FooterElement
  Element _footer;
  ButtonElement _clearCompleted;

  static ComponentConstructorThunk _$constr;
  factory TodoList.component() {
    if(_$constr == null) {
      _$constr = () => new TodoList._internal();
    }
    var t1 = new DivElement();
    t1.attributes['is'] = 'x-todo-list';
    rewirePrototypeChain(t1, _$constr, 'TodoList');
    return t1;
  }

  factory TodoList() {
    return manager.expandHtml('<div is="x-todo-list"></div>');
  }

  TodoList._internal();

  void addTodo(Todo todo) {
    // possible order of operations issue with the model binding/rendering
    var todoComponent = new TodoListElement();
    todoComponent.todo = todo;
    todoComponent.model = model;
    _shadowRoot.query('#todo-list').nodes.add(todoComponent);
  }

  void set model(Todos model) {
    this._model = model;
    model.on.added.addAll([addTodo, updateCount]);
    model.on.removed.add(updateCount);
    model.on.completed.add(updateCount);
    model.on.uncompleted.add(updateCount);
  }

  // We take a Todo argument so that updateCount can be a TodoCallback
  void updateCount(Todo todo) {
    // TODO(samhop): Not clear how to make this less hacky, since the
    // component doesn't have a lifecycle event for "model is hooked up"
    if (model == null || model._todos.length == 0) {
      _footer.classes.add('no-todos');
    } else {
      var uncomplete = model.remaining;
      _footer.classes.remove('no-todos');
      if (uncomplete == 1) {
        _footer.query('#todo-count').innerHTML =
            '<strong>1</strong> item left';
      } else {
        _footer.query('#todo-count').innerHTML =
            '<strong>$uncomplete</strong> items left';
      }
      _clearCompleted.innerHTML =
           'Clear completed '
           '(${model._todos.length - model.remaining})';
    }
  }

  Todos get model => _model;

  void created(ShadowRoot shadowRoot) {
    _shadowRoot = shadowRoot;
    _footer = _shadowRoot.query('#footer');
    _clearCompleted = _shadowRoot.query('#clear-completed');
  }

  void inserted() {
    updateCount(null);
    var toggleAll = _shadowRoot.query('#toggle-all');
    toggleAll.on.change.add((event) {
      if (toggleAll.checked) {
        model.completeAll();
      } else {
        model.uncompleteAll();
      }
    });
    _shadowRoot.query('#clear-completed').on.click.add((event) {
      model.clearCompleted();
    });
  }

  // TODO(samhop): Expose current todo list as a data attribute of the TodoList
  // component.
  void attributeChanged(String name, String oldValue, String newValue) { }

  void removed() { }
}

/** Component representing a todo input bar */
class NewTodo extends DivElementImpl implements WebComponent {
  ShadowRoot _shadowRoot;
  Todos model;


  static ComponentConstructorThunk _$constr;
  factory NewTodo.component() {
    if (_$constr == null) {
      _$constr = () => new NewTodo._internal();
    }
    var t1 = new DivElement();
    t1.attributes['is'] = 'x-new-todo';
    rewirePrototypeChain(t1, _$constr, 'NewTodo');
    return t1;
  }

  factory NewTodo() {
    return manager.expandHtml('<div is="x-new-todo"></div>');
  }

  NewTodo._internal();

  void created(ShadowRoot shadowRoot) {
    _shadowRoot = shadowRoot;
  }
  void inserted() {
    _shadowRoot.on.keyPress.add((event) {
      if (event.keyCode == ENTER_KEY) {
        var input = _shadowRoot.query('#new-todo');
        var trimmedStr = input.value.trim();
        if (trimmedStr != '') {
          model.addTodo(new Todo(trimmedStr));
          input.value = '';
        }
      }
    });
  }
  void attributeChanged(String name, String oldValue, String newValue) { }
  void removed() { }
}

/** Component representing a static info footer */
class TodoFooter extends DivElementImpl implements WebComponent {
  ShadowRoot _root;

  static ComponentConstructorThunk _$constr;
  factory TodoFooter.component() {
    if (_$constr == null) {
      _$constr = () => new TodoFooter._internal();
    }
    var t1 = new DivElement();
    t1.attributes['is'] = 'x-todo-footer';
    rewirePrototypeChain(t1, _$constr, 'TodoFooter');
    return t1;
  }

  factory TodoFooter() {
    return manager.expandHtml('<div is="x-todo-footer"></div>');
  }

  TodoFooter._internal();

  void created(ShadowRoot shadowRoot) {
    _root = shadowRoot;
    id = 'info';
  }

  void inserted() { }

  void attributeChanged(String name, String oldValue, String newValue) { }
  void removed() { }
}

/** Component representing a static info footer */
class TodoHeader extends DivElementImpl implements WebComponent {
  ShadowRoot _root;

  static ComponentConstructorThunk _$constr;
  factory TodoHeader.component() {
    if (_$constr == null) {
      _$constr = () => new TodoHeader._internal();
    }
    var t1 = new DivElement();
    t1.attributes['is'] = 'x-todo-header';
    rewirePrototypeChain(t1, _$constr, 'TodoHeader');
    return t1;
  }

  factory TodoHeader() {
    return manager.expandHtml('<div is="x-todo-header"></div>');
  }

  TodoHeader._internal();

  void created(ShadowRoot shadowRoot) {
    _root = shadowRoot;
    id = 'header';
  }

  void inserted() { }
  void attributeChanged(String name, String oldValue, String newValue) { }
  void removed() { }

  /** Pass the model down to subcomponents. */
  void set model(Todos model) {
    var newTodo = _root.query('div[is="x-new-todo"]');
    newTodo.model = model;
  }
}

