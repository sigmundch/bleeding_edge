// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('native');
#import('dart:uri');
#import('leg.dart');
#import('elements/elements.dart');
#import('js_backend/js_backend.dart');
#import('scanner/scannerlib.dart');
#import('ssa/ssa.dart');
#import('tree/tree.dart');
#import('util/util.dart');

void processNativeClasses(Enqueuer world,
                          CodeEmitterTask emitter,
                          Collection<LibraryElement> libraries) {
  for (LibraryElement library in libraries) {
    processNativeClassesInLibrary(world, emitter, library);
  }
}

void addSubtypes(ClassElement cls,
                 NativeEmitter emitter) {
  for (DartType type in cls.allSupertypes) {
    List<Element> subtypes = emitter.subtypes.putIfAbsent(
        type.element,
        () => <ClassElement>[]);
    subtypes.add(cls);
  }

  List<Element> directSubtypes = emitter.directSubtypes.putIfAbsent(
      cls.superclass,
      () => <ClassElement>[]);
  directSubtypes.add(cls);
}

void processNativeClassesInLibrary(Enqueuer world,
                                   CodeEmitterTask emitter,
                                   LibraryElement library) {
  bool hasNativeClass = false;
  final compiler = emitter.compiler;
  for (Link<Element> link = library.localMembers;
       !link.isEmpty(); link = link.tail) {
    Element element = link.head;
    if (element.kind == ElementKind.CLASS) {
      ClassElement classElement = element;
      // TODO(samhop): should we handle inheritsFromNative any differently
      // from isNative?
      if (classElement.isNative() || classElement.inheritsFromNative) {
        hasNativeClass = true;
        world.registerInstantiatedClass(classElement);
        // Also parse the node to know all its methods because
        // otherwise it will only be parsed if there is a call to
        // one of its constructor.
        classElement.parseNode(compiler);
        // Resolve to setup the inheritance.
        classElement.ensureResolved(compiler);
        // Add the information that this class is a subtype of
        // its supertypes. The code emitter and the ssa builder use that
        // information.
        addSubtypes(classElement, emitter.nativeEmitter);
      }
    }
  }
  if (hasNativeClass) {
    world.registerStaticUse(compiler.findHelper(
        const SourceString('dynamicFunction')));
    world.registerStaticUse(compiler.findHelper(
        const SourceString('dynamicSetMetadata')));
    world.registerStaticUse(compiler.findHelper(
        const SourceString('defineProperty')));
    world.registerStaticUse(compiler.findHelper(
        const SourceString('toStringForNativeObject')));
  }
}

void maybeEnableNative(Compiler compiler,
                       LibraryElement library,
                       Uri uri) {
  String libraryName = uri.toString();
  if (library.entryCompilationUnit.script.name.contains(
          'dart/tests/compiler/dart2js_native')
      || libraryName == 'dart:isolate'
      || libraryName == 'dart:html') {
    library.canUseNative = true;
  }
}

void checkAllowedLibrary(ElementListener listener, Token token) {
  LibraryElement currentLibrary = listener.compilationUnitElement.getLibrary();
  if (!currentLibrary.canUseNative) {
    listener.recoverableError("Unexpected token", token: token);
  }
}

Token handleNativeBlockToSkip(Listener listener, Token token) {
  checkAllowedLibrary(listener, token);
  token = token.next;
  if (token.kind === STRING_TOKEN) {
    token = token.next;
  }
  if (token.stringValue === '{') {
    BeginGroupToken beginGroupToken = token;
    token = beginGroupToken.endGroup;
  }
  return token;
}

Token handleNativeClassBodyToSkip(Listener listener, Token token) {
  checkAllowedLibrary(listener, token);
  listener.handleIdentifier(token);
  token = token.next;
  if (token.kind !== STRING_TOKEN) {
    return listener.unexpected(token);
  }
  token = token.next;
  if (token.stringValue !== '{') {
    return listener.unexpected(token);
  }
  BeginGroupToken beginGroupToken = token;
  token = beginGroupToken.endGroup;
  return token;
}

Token handleNativeClassBody(Listener listener, Token token) {
  checkAllowedLibrary(listener, token);
  token = token.next;
  if (token.kind !== STRING_TOKEN) {
    listener.unexpected(token);
  } else {
    token = token.next;
  }
  return token;
}

Token handleNativeFunctionBody(ElementListener listener, Token token) {
  checkAllowedLibrary(listener, token);
  Token begin = token;
  listener.beginReturnStatement(token);
  token = token.next;
  bool hasExpression = false;
  if (token.kind === STRING_TOKEN) {
    hasExpression = true;
    listener.beginLiteralString(token);
    listener.endLiteralString(0);
    token = token.next;
  }
  listener.endReturnStatement(hasExpression, begin, token);
  // TODO(ngeoffray): expect a ';'.
  // Currently there are method with both native marker and Dart body.
  return token.next;
}

SourceString checkForNativeClass(ElementListener listener) {
  SourceString nativeName;
  Node node = listener.nodes.head;
  if (node != null
      && node.asIdentifier() != null
      && node.asIdentifier().source.stringValue == 'native') {
    nativeName = node.asIdentifier().token.next.value;
    listener.popNode();
  }
  return nativeName;
}

bool isOverriddenMethod(FunctionElement element,
                        ClassElement cls,
                        NativeEmitter nativeEmitter) {
  List<ClassElement> subtypes = nativeEmitter.subtypes[cls];
  if (subtypes == null) return false;
  for (ClassElement subtype in subtypes) {
    if (subtype.lookupLocalMember(element.name) != null) return true;
  }
  return false;
}

void handleSsaNative(SsaBuilder builder, Expression nativeBody) {
  Compiler compiler = builder.compiler;
  FunctionElement element = builder.work.element;
  element.setNative();
  NativeEmitter nativeEmitter = builder.emitter.nativeEmitter;
  // If what we're compiling is a getter named 'typeName' and the native
  // class is named 'DOMType', we generate a call to the typeNameOf
  // function attached on the isolate.
  // The DOM classes assume that their 'typeName' property, which is
  // not a JS property on the DOM types, returns the type name.
  if (element.name == const SourceString('typeName')
      && element.isGetter()
      && nativeEmitter.toNativeName(element.getEnclosingClass()) == 'DOMType') {
    Element helper =
        compiler.findHelper(const SourceString('getTypeNameOf'));
    builder.pushInvokeHelper1(helper, builder.localsHandler.readThis());
    builder.close(new HReturn(builder.pop())).addSuccessor(builder.graph.exit);
  }

  HInstruction convertDartClosure(Element parameter, FunctionType type) {
    HInstruction local = builder.localsHandler.readLocal(parameter);
    Constant arityConstant =
        builder.constantSystem.createInt(type.computeArity());
    HInstruction arity = builder.graph.addConstant(arityConstant);
    // TODO(ngeoffray): For static methods, we could pass a method with a
    // defined arity.
    Element helper = builder.interceptors.getClosureConverter();
    builder.pushInvokeHelper2(helper, local, arity);
    HInstruction closure = builder.pop();
    return closure;
  }

  // Check which pattern this native method follows:
  // 1) foo() native; hasBody = false, isRedirecting = false
  // 2) foo() native "bar"; hasBody = false, isRedirecting = true
  // 3) foo() native "return 42"; hasBody = true, isRedirecting = false
  RegExp nativeRedirectionRegExp = const RegExp(@'^[a-zA-Z][a-zA-Z_$0-9]*$');
  bool hasBody = false;
  bool isRedirecting = false;
  String nativeMethodName = element.name.slowToString();
  if (nativeBody !== null) {
    LiteralString jsCode = nativeBody.asLiteralString();
    String str = jsCode.dartString.slowToString();
    if (nativeRedirectionRegExp.hasMatch(str)) {
      nativeMethodName = str;
      isRedirecting = true;
      nativeEmitter.addRedirectingMethod(element, nativeMethodName);
    } else {
      hasBody = true;
    }
  }

  if (!hasBody) {
    nativeEmitter.nativeMethods.add(element);
  }

  FunctionSignature parameters = element.computeSignature(builder.compiler);
  if (!hasBody) {
    List<String> arguments = <String>[];
    List<HInstruction> inputs = <HInstruction>[];
    String receiver = '';
    if (element.isInstanceMember()) {
      receiver = '#.';
      inputs.add(builder.localsHandler.readThis());
    }
    parameters.forEachParameter((Element parameter) {
      DartType type = parameter.computeType(compiler).unalias(compiler);
      HInstruction input = builder.localsHandler.readLocal(parameter);
      if (type is FunctionType) {
        // The parameter type is a function type either directly or through
        // typedef(s).
        input = convertDartClosure(parameter, type);
      }
      inputs.add(input);
      arguments.add('#');
    });

    String foreignParameters = Strings.join(arguments, ',');
    String nativeMethodCall;
    if (element.kind == ElementKind.FUNCTION) {
      nativeMethodCall = '$receiver$nativeMethodName($foreignParameters)';
    } else if (element.kind == ElementKind.GETTER) {
      nativeMethodCall = '$receiver$nativeMethodName';
    } else if (element.kind == ElementKind.SETTER) {
      nativeMethodCall = '$receiver$nativeMethodName = $foreignParameters';
    } else {
      builder.compiler.internalError('unexpected kind: "${element.kind}"',
                                     element: element);
    }

    DartString jsCode = new DartString.literal(nativeMethodCall);
    builder.push(
        new HForeign(jsCode, const LiteralDartString('Object'), inputs));
    builder.close(new HReturn(builder.pop())).addSuccessor(builder.graph.exit);
  } else {
    // This is JS code written in a Dart file with the construct
    // native """ ... """;. It does not work well with mangling,
    // but there should currently be no clash between leg mangling
    // and the library where this construct is being used. This
    // mangling problem will go away once we switch these libraries
    // to use Leg's 'JS' function.
    parameters.forEachParameter((Element parameter) {
      DartType type = parameter.computeType(compiler).unalias(compiler);
      if (type is FunctionType) {
        // The parameter type is a function type either directly or through
        // typedef(s).
        HInstruction jsClosure = convertDartClosure(parameter, type);
        // Because the JS code references the argument name directly,
        // we must keep the name and assign the JS closure to it.
        builder.add(new HForeign(
            new DartString.literal('${parameter.name.slowToString()} = #'),
            const LiteralDartString('void'),
            <HInstruction>[jsClosure]));
      }
    });
    LiteralString jsCode = nativeBody.asLiteralString();
    builder.push(new HForeign.statement(jsCode.dartString, <HInstruction>[]));
  }
}

void generateMethodWithPrototypeCheckForElement(Compiler compiler,
                                                StringBuffer buffer,
                                                FunctionElement element,
                                                String code,
                                                String parameters) {
  String methodName;
  JavaScriptBackend backend = compiler.backend;
  Namer namer = backend.namer;
  if (element.kind == ElementKind.FUNCTION) {
    methodName = namer.instanceMethodName(element);
  } else if (element.kind == ElementKind.GETTER) {
    methodName = namer.getterName(element.getLibrary(), element.name);
  } else if (element.kind == ElementKind.SETTER) {
    methodName = namer.setterName(element.getLibrary(), element.name);
  } else {
    compiler.internalError('unexpected kind: "${element.kind}"',
                           element: element);
  }

  generateMethodWithPrototypeCheck(
      compiler, buffer, methodName, code, parameters);
}


// If a method is overridden, we must check if the prototype of
// 'this' has the method available. Otherwise, we may end up
// calling the method from the super class. If the method is not
// available, we make a direct call to Object.prototype.$methodName.
// This method will patch the prototype of 'this' to the real method.
void generateMethodWithPrototypeCheck(Compiler compiler,
                                      StringBuffer buffer,
                                      String methodName,
                                      String code,
                                      String parameters) {
  buffer.add("  if (Object.getPrototypeOf(this).hasOwnProperty");
  buffer.add("('$methodName')) {\n");
  buffer.add("  $code");
  buffer.add("  } else {\n");
  buffer.add("    return Object.prototype.$methodName.call(this");
  buffer.add(parameters == '' ? '' : ', $parameters');
  buffer.add(");\n");
  buffer.add("  }\n");
}
