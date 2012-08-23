// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This is a temporary file in which to store code that gets patched in to
// html_dart2js in a post-processing step to enable webcomponents
// functionality.

/**
 * _ListMap class so that we have a dictionary usable with non-hashable keys.
 * Note: this class does NOT yet have full Map functionality
 */
class _ListMap<K, V> {

  List<_Pair<K, V>> _list;

  _ListMap()
    : _list = new List<_Pair<K, V>>() { }

  void operator []=(K key, V value) {
    for (var pair in _list) {
      if (pair._key == key) {
        pair._value = value;
        return;
      }
    }
    _list.add(new _Pair<K,V>(key, value));
  }

  V operator [](K key) {
    for (var pair in _list) {
      if (pair._key == key)
        return pair._value;
    }
    return null;
  }
}

class _Pair<K, V> {
  final K _key;
  V _value;

  _Pair(this._key, this._value);
}

// TODO(samhop): add some types

get _componentsMetadata() {
  if (JS('var', 'typeof(\$componentsMetadata)') === 'undefined') {
    _componentsMetadata = new _ListMap();
  }
  return JS('var', '\$componentsMetadata');
}

void set _componentsMetadata(m) {
  JS('void', '\$componentsMetadata = #', m);
}

/**
 * Takes [nativeElement] of type NativeType, and [closure], a thunk
 * returning a webcomponent of type T and does prototype
 * mangling to achieve the following inheritance hierarchy
 *
 * [nativeElement] is T <: *classes between T and NativeType* <: NativeType
 *
 * For optimal performance, each call with the same type T should pass the
 * same closure.
 */
void rewirePrototypeChain(nativeElement, closure) {
  // TODO(samhop): worry about field initialization
  // TODO(samhop): worry about perf -- should probably make componentsMetadata
  // a native type.
  // TODO(samhop): worry about IE9
  // TODO(samhop): worry about inheriting transitively from a native (may
  // currently work)
  // TODO(samhop): what happens if someone passes two different closures at
  // two different calls for the same type?
  var componentPrototype = _componentsMetadata[closure];
  if (componentPrototype == null) {
    var nonNativeElement = closure();
    componentPrototype = JS('var', 'Object.getPrototypeOf(#)',
        nonNativeElement);
    _componentsMetadata[closure] = componentPrototype;
    // We rely on the __proto__.__proto__ of a nonnative direct subtype of
    // a native type
    // being Object.prototype to detect whether or not we are at what should
    // be the native/non-native boundary and need to rewire.
    // TODO(samhop): consider the possibility of having different rewiring
    // functions for direct and transitive subtypes of native types.
    // Which to call will be known by the webcomponents compiler.
    var currProto = componentPrototype;
    // check that the browser supports __proto__ mangling and, if so,
    // have we already mangled this proto chain appropriately?
    if (_supportsProto && !(JS(
            'var', 'Object.isPrototypeOf.call(Object.getPrototypeOf(#), #)',
            nativeElement, nonNativeElement))) {
      // We haven't yet mangled this prototype chain appropriately, so
      // walk up to where we need to hook the nonnative chain up to the
      // native chain.
      // TODO(samhop): worry about handling of methods that might be living
      // on $.Object, which won't make it into this prototype chain.
      while(!(JS('var', 'Object.getPrototypeOf(#) === Object.prototype',
          currProto))) {
        currProto = JS('var', 'Object.getPrototypeOf(#)', currProto);
      }
      JS('void', '#.__proto__ = Object.getPrototypeOf(#)',
          currProto, nativeElement);
    }
  }
  if (_supportsProto) {
    JS('void', '#.__proto__ = #', nativeElement, componentPrototype);
  } else {
    // TODO(samhop): worry about multiple levels of inheritance.
    _copyProperties(componentPrototype, nativeElement);
  }
}

// TODO(samhop): This functionality is duplicated in
// compiler/implementation/js_backend/emitter.dart. There should
// be a way to refactor to get it into a shared library (although it will
// be tricky, since the functionality there is needed at initialization time).
// (See documentation in emitter.dart)
bool get _supportsProto() {
  var supportsProto = false;
  var tmp = new _ProtoTester();
  var tmpPrototype = JS('var', '#.constructor.prototype', tmp);
  var protoFieldExists = JS('var', '!!(#.__proto__)', tmpPrototype);
  if (protoFieldExists) {
    JS('void', '#.__proto__ = {}', tmpPrototype);
    var undefinedCheck = JS('var', 'typeof # === "undefined"', tmpPrototype.f);
    if (undefinedCheck) {
      supportsProto = true;
    }
  }
  return supportsProto;
}

class _ProtoTester {
  var f;
}

// see doc for _supportsProto
// TODO(samhop): migrate this to the JS compiler directive.
void _copyProperties(source, dest) native
'''
  for (var member in source) {
    if (member == '' || member == 'super') continue;
    if (hasOwnProperty.call(source, member)) {
      dest[member] = source[member];
    }
  }
'''
