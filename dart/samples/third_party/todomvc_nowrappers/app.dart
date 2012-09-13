// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('todomvc');

#import('package:dart-web-components/lib/js_polyfill/web_components.dart');
#import('dart:html');

#source('scripts/components.dart');

final int ENTER_KEY = 13;

// hack to get unique todo id's.
int _todoId = 0;

typedef Dynamic TodoCallback(Todo todo);

void _componentsSetup() {
  // use mirrors when they become available.
  Map<String, Function> map = {
    'x-todo-list-element': () => new TodoListElement.component(),
    'x-todo-list': () => new TodoList.component(),
    'x-new-todo': () => new NewTodo.component(),
    'x-todo-footer': () => new TodoFooter.component(),
    'x-todo-header': () => new TodoHeader.component()
  };
  initializeComponents((String name) => map[name], true);
}

void main() {
  _componentsSetup();

  // wire everything up to the model
  var model = new Todos();
  var list = query('div[is=x-todo-list]');
  list.model = model;
  
  var header = query('div[is=x-todo-header]');
  header.model = model;
}

/** Global model for TodoMVC app */
class Todos {
  List<Todo> _todos;
  int remaining;
  TodoCallbacks on;
 
  Todos()
    : remaining = 0,
      _todos = <Todo>[],
      on = new TodoCallbacks();

  void addTodo(Todo todo) {
    _todos.add(todo);
    remaining++;
    on.added.forEach((c) => c(todo));
  }

  void removeTodo(Todo todo) {
    _todos.removeRange(_todos.indexOf(todo),1);
    if (!(todo.completed)) {
      remaining--;
    }
    on.removed.forEach((c) => c(todo));
  }

  void complete(Todo todo) {
    todo.completed = true;
    remaining--;
    on.completed.forEach((c) => c(todo));
  }

  void uncomplete(Todo todo) {
    todo.completed = false;
    remaining++;
    on.uncompleted.forEach((c) => c(todo));
  }

  void completeAll() => _todos.forEach((todo) => complete(todo));
  void uncompleteAll() => _todos.forEach((todo) => uncomplete(todo));

  void clearCompleted() {
    _todos.filter((t) => t.completed).forEach((t) => removeTodo(t));
  }
}

/** 
 * Wrapper for callbacks from the Todo model to the components.
 * This is separated into its own class so we can support the 
 * model.on.event.add(callback) style.
 */
class TodoCallbacks {
  List<TodoCallback> added;
  List<TodoCallback> removed;
  List<TodoCallback> completed;
  List<TodoCallback> uncompleted;

  TodoCallbacks()
    : added = <TodoCallback>[],
      removed = <TodoCallback>[],
      completed = <TodoCallback>[],
      uncompleted = <TodoCallback>[];
}

/** Wraps data for an individual todo */
class Todo {
  String value;
  bool completed;
  int _id;

  Todo._internal(this.value);

  factory Todo(String value) {
    var todo = new Todo._internal(value);
    todo._id = _todoId++;
    return todo;
  }

  operator ==(other) {
    return _id == other._id;
  }

  int hashCode() => _id;
}
