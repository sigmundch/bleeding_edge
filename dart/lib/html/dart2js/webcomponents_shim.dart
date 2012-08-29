// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This is a temporary file in which to store code that gets patched in to
// html_dart2js in a post-processing step to enable webcomponents
// functionality.

get _componentsMetadata {
  if (JS('var', 'typeof(\$componentsMetadata)') === 'undefined') {
    _componentsMetadata = JS('var', 'Object.create(null)');
  }
  return JS('var', '\$componentsMetadata');
}

void set _componentsMetadata(m) {
 JS('void', '\$componentsMetadata = #', m);
}

/**
 * Takes [nativeElement] of type NativeType, [closure], a thunk returning a
 * webcomponent of type T, and a string [name], the name of type T, and does
 * prototype mangling to achieve the following inheritance hierarchy
 *
 * [nativeElement] is T <: *classes between T and NativeType* <: NativeType
 */
void rewirePrototypeChain(nativeElement, closure, String name) {
  // TODO(samhop): worry about field initialization
  // TODO(samhop): worry about perf -- should probably make componentsMetadata
  // a native type.
  // TODO(samhop): what happens if someone passes two different closures at
  // two different calls for the same type?
  var componentPrototype = JS('var', '#[#]', _componentsMetadata, name);
  if (componentPrototype == null) {
    var nonNativeElement = closure();
    componentPrototype = JS('var', 'Object.getPrototypeOf(#)',
        nonNativeElement);
    JS('void', '#[#] = #', _componentsMetadata, name, componentPrototype);
    // We rely on the __proto__.__proto__ of a nonnative direct subtype of
    // a native type
    // being Object.prototype to detect whether or not we are at what should
    // be the native/non-native boundary and need to rewire.
    // TODO(samhop): consider the possibility of having different rewiring
    // functions for direct and transitive subtypes of native types.
    // Which to call will be known by the webcomponents compiler.
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
      var currProto = componentPrototype;
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
    _copyProperties(componentPrototype, nativeElement, override: false);
  }
}

// TODO(samhop): This functionality is duplicated in
// compiler/implementation/js_backend/emitter.dart. There should
// be a way to refactor to get it into a shared library (although it will
// be tricky, since the functionality there is needed at initialization time).
// (See documentation in emitter.dart)

// Singleton
bool _supportsProtoCache;
bool get _supportsProto() {
  if (_supportsProtoCache == null) {
    var supportsProto = false;
    var tmp = new _ProtoTester();
    var tmpPrototype = JS('var', '#.constructor.prototype', tmp);
    var protoFieldExists = JS('var', '!!(#.__proto__)', tmpPrototype);
    if (protoFieldExists) {
      JS('void', '#.__proto__ = {}', tmpPrototype);
      var undefinedCheck = 
          JS('var', 'typeof # === "undefined"', tmpPrototype.f);
      if (undefinedCheck) {
        supportsProto = true;
      }
    }
    _supportsProtoCache = supportsProto;
  }
  return _supportsProtoCache;
}

class _ProtoTester {
  var f;
}

// see doc for _supportsProto
// TODO(samhop): migrate this to the JS compiler directive.
/**
 * Copies all members of [source] (and its prototype chain) that are not defined
 * only on Object to [dest]. If [override] is true, does not
 * copy members already defined on [dest]. Does not copy empty members or the
 * 'super' member.
 */
void _copyProperties(source, dest, [override = true]) native
'''
  for (var member in source) {
    var hasOwnProperty = Object.hasOwnProperty;
    if (member == '' || member == 'super') continue;
    if (!(Object.prototype[member] === source[member])
        && !(!override && hasOwnProperty.call(dest, member))) {
      dest[member] = source[member];
    }
  }
'''
