// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

typedef void Recompile(Element element);

class ReturnInfo {
  HType returnType;
  List<Element> compiledFunctions;

  ReturnInfo(HType this.returnType)
      : compiledFunctions = new List<Element>();

  ReturnInfo.unknownType()
      : this.returnType = null,
        compiledFunctions = new List<Element>();

  void update(HType type, Recompile recompile) {
    HType newType = returnType != null ? returnType.union(type) : type;
    if (newType != returnType) {
      if (returnType == null && newType === HType.UNKNOWN) {
        // If the first actual piece of information is not providing any type
        // information there is no need to recompile callers.
        compiledFunctions.clear();
      }
      returnType = newType;
      if (recompile != null) {
        compiledFunctions.forEach(recompile);
      }
      compiledFunctions.clear();
    }
  }

  // Note that lazy initializers are treated like functions (but are not
  // of type [FunctionElement].
  addCompiledFunction(Element function) => compiledFunctions.add(function);
}

class OptionalParameterTypes {
  final List<SourceString> names;
  final List<HType> types;

  OptionalParameterTypes(int optionalArgumentsCount)
      : names = new List<SourceString>(optionalArgumentsCount),
        types = new List<HType>(optionalArgumentsCount);

  int get length => names.length;
  SourceString name(int index) => names[index];
  HType type(int index) => types[index];
  int indexOf(SourceString name) => names.indexOf(name);

  HType typeFor(SourceString name) {
    int index = indexOf(name);
    if (index == -1) return null;
    return type(index);
  }

  void update(int index, SourceString name, HType type) {
    names[index] = name;
    types[index] = type;
  }

  String toString() => "OptionalParameterTypes($names, $types)";
}

class HTypeList {
  final List<HType> types;
  final List<SourceString> namedArguments;

  HTypeList(int length)
      : types = new List<HType>(length),
        namedArguments = null;
  HTypeList.withNamedArguments(int length, this.namedArguments)
      : types = new List<HType>(length);
  const HTypeList.allUnknown()
      : types = null,
        namedArguments = null;

  factory HTypeList.fromStaticInvocation(HInvokeStatic node, HTypeMap types) {
    bool allUnknown = true;
    for (int i = 1; i < node.inputs.length; i++) {
      if (types[node.inputs[i]] != HType.UNKNOWN) {
        allUnknown = false;
        break;
      }
    }
    if (allUnknown) return HTypeList.ALL_UNKNOWN;

    HTypeList result = new HTypeList(node.inputs.length - 1);
    for (int i = 0; i < result.types.length; i++) {
      result.types[i] = types[node.inputs[i + 1]];
    }
    return result;
  }

  factory HTypeList.fromDynamicInvocation(HInvokeDynamic node,
                                          Selector selector,
                                          HTypeMap types) {
    HTypeList result;
    int argumentsCount = node.inputs.length - 1;
    if (selector.namedArgumentCount > 0) {
      result =
          new HTypeList.withNamedArguments(
              argumentsCount, selector.namedArguments);
    } else {
      result = new HTypeList(argumentsCount);
    }
    for (int i = 0; i < result.types.length; i++) {
      result.types[i] = types[node.inputs[i + 1]];
    }
    return result;
  }

  static const HTypeList ALL_UNKNOWN = const HTypeList.allUnknown();

  bool get allUnknown => types === null;
  bool get hasNamedArguments => namedArguments != null;
  int get length => types.length;
  HType operator[](int index) => types[index];

  HTypeList union(HTypeList other) {
    if (allUnknown) return this;
    if (other.allUnknown) return other;
    if (length != other.length) return HTypeList.ALL_UNKNOWN;
    bool onlyUnknown = true;
    HTypeList result = this;
    for (int i = 0; i < length; i++) {
      HType newType = this[i].union(other[i]);
      if (result == this && newType != this[i]) {
        // Create a new argument types object with the matching types copied.
        result = new HTypeList(length);
        result.types.setRange(0, i, this.types);
      }
      if (result != this) {
        result.types[i] = newType;
      }
      if (result[i] != HType.UNKNOWN) onlyUnknown = false;
    }
    return onlyUnknown ? HTypeList.ALL_UNKNOWN : result;
  }

  /**
   * Create the union of this [HTypeList] object with the types used by
   * the [node]. If the union results in exactly the same types the receiver
   * is returned. Otherwise a different [HTypeList] object is returned
   * with the type union information.
   */
  HTypeList unionWithInvoke(HInvoke node, HTypeMap types) {
    // Union an all unknown list with something stays all unknown.
    if (allUnknown) return this;

    bool allUnknown = true;
    if (length != node.inputs.length - 1) {
      return HTypeList.ALL_UNKNOWN;
    }

    bool onlyUnknown = true;
    HTypeList result = this;
    for (int i = 0; i < length; i++) {
      HType newType = this[i].union(types[node.inputs[i + 1]]);
      if (result == this && newType != this[i]) {
        // Create a new argument types object with the matching types copied.
        result = new HTypeList(length);
        result.types.setRange(0, i, this.types);
      }
      if (result != this) {
        result.types[i] = newType;
      }
      if (result[i] != HType.UNKNOWN) onlyUnknown = false;
    }
    return onlyUnknown ? HTypeList.ALL_UNKNOWN : result;
  }

  HTypeList unionWithOptionalParameters(
      Selector selector,
      FunctionSignature signature,
      OptionalParameterTypes defaultValueTypes) {
    assert(allUnknown || selector.argumentCount == this.length);
    // Create a new HTypeList for holding types for all parameters.
    HTypeList result = new HTypeList(signature.parameterCount);

    // First fill in the type of the positional arguments.
    int nextTypeIndex = -1;
    if (allUnknown) {
      for (int i = 0; i < selector.positionalArgumentCount; i++) {
        result.types[i] = HType.UNKNOWN;
      }
    } else {
      result.types.setRange(0, selector.positionalArgumentCount, this.types);
      nextTypeIndex = selector.positionalArgumentCount;
    }

    // Next fill the type of the optional arguments.
    // As the selector can pass optional arguments positionally some of the
    // optional arguments might already have a type set. We only need to look
    // at the optional arguments not passed positionally.
    // The variable 'index' is counting the signatures optional arguments, the
    // variable 'next' is set to the next optional arguments to look at and
    // is used to skip some optional arguments.
    int next = selector.positionalArgumentCount;
    int index = signature.requiredParameterCount;
    signature.forEachOptionalParameter((Element element) {
      // If some optional parameters were passed positionally these have
      // already been filled.
      if (index == next) {
        assert(result.types[index] === null);
        HType type = null;
        if (hasNamedArguments &&
            selector.namedArguments.indexOf(element.name) >= 0) {
          type = types[nextTypeIndex++];
        } else {
          type = defaultValueTypes.typeFor(element.name);
        }
        result.types[index] = type;
        next++;
      }
      index++;
    });
    return result;
  }

  String toString() =>
      allUnknown ? "HTypeList.ALL_UNKNOWN" : "HTypeList $types";
}

class ArgumentTypesRegistry {
  final JavaScriptBackend backend;
  final Map<Element, HTypeList> staticTypeMap;
  final Set<Element> optimizedStaticFunctions;
  final SelectorMap<HTypeList> selectorTypeMap;
  final FunctionSet optimizedFunctions;
  final Map<Element, HTypeList> optimizedTypes;
  final Map<Element, OptionalParameterTypes> optimizedDefaultValueTypes;

  ArgumentTypesRegistry(JavaScriptBackend backend)
      : staticTypeMap = new Map<Element, HTypeList>(),
        optimizedStaticFunctions = new Set<Element>(),
        selectorTypeMap = new SelectorMap<HTypeList>(backend.compiler),
        optimizedFunctions = new FunctionSet(backend.compiler),
        optimizedTypes = new Map<Element, HTypeList>(),
        optimizedDefaultValueTypes =
            new Map<Element, OptionalParameterTypes>(),
        this.backend = backend;

  Compiler get compiler => backend.compiler;

  void registerStaticInvocation(HInvokeStatic node, HTypeMap types) {
    Element element = node.element;
    HTypeList oldTypes = staticTypeMap[element];
    if (oldTypes == null) {
      staticTypeMap[element] = new HTypeList.fromStaticInvocation(node, types);
    } else {
      if (oldTypes.allUnknown) return;
      HTypeList newTypes = oldTypes.unionWithInvoke(node, types);
      if (newTypes === oldTypes) return;
      staticTypeMap[element] = newTypes;
      if (optimizedStaticFunctions.contains(element)) {
        backend.scheduleForRecompilation(element);
      }
    }
  }

  void registerNonCallStaticUse(HStatic node) {
    // When a static is used for anything else than a call target we cannot
    // infer anything about its parameter types.
    Element element = node.element;
    if (optimizedStaticFunctions.contains(element)) {
      backend.scheduleForRecompilation(element);
    }
    staticTypeMap[element] = HTypeList.ALL_UNKNOWN;
  }

  void registerDynamicInvocation(HInvokeDynamicMethod node,
                                 Selector selector,
                                 HTypeMap types) {
    // If there are any getters for this method we cannot know anything about
    // the types of the provided parameters. Use resolverWorld for now as that
    // information does not change during compilation.
    // TODO(sgjesse): These checks should use the codegenWorld and keep track
    // of changes to this information.
    Element element = node.element;
    Universe resolverWorld = compiler.resolverWorld;
    if (element != null &&
        (resolverWorld.hasFieldGetter(element, compiler) ||
         resolverWorld.hasInvokedGetter(element, compiler))) {
      return;
    }

    HTypeList providedTypes =
        new HTypeList.fromDynamicInvocation(node, selector, types);
    if (!selectorTypeMap.containsKey(selector)) {
      selectorTypeMap[selector] = providedTypes;
    } else {
      HTypeList oldTypes = selectorTypeMap[selector];
      HTypeList newTypes = oldTypes.unionWithInvoke(node, types);
      if (newTypes === oldTypes) return;
      selectorTypeMap[selector] = newTypes;
    }

    // If we're not compiling, we don't have to do anything.
    if (compiler.phase != Compiler.PHASE_COMPILING) return;

    // Run through all optimized functions and figure out if they need
    // to be recompiled because of this new invocation.
    optimizedFunctions.filterBySelector(selector).forEach((Element element) {
      // TODO(kasperl): Maybe check if the element is already marked for
      // recompilation? Could be pretty cheap compared to computing
      // union types.
      HTypeList newTypes =
          parameterTypes(element, optimizedDefaultValueTypes[element]);
      bool recompile = false;
      if (newTypes.allUnknown) {
        recompile = true;
      } else {
        HTypeList oldTypes = optimizedTypes[element];
        assert(newTypes.length == oldTypes.length);
        for (int i = 0; i < oldTypes.length; i++) {
          if (newTypes[i] != oldTypes[i]) {
            recompile = true;
            break;
          }
        }
      }
      if (recompile) backend.scheduleForRecompilation(element);
    });
  }

  HTypeList parameterTypes(FunctionElement element,
                           OptionalParameterTypes defaultValueTypes) {
    // Handle static functions separately.
    if (Elements.isStaticOrTopLevelFunction(element)) {
      HTypeList types = staticTypeMap[element];
      if (types !== null) {
        if (!optimizedStaticFunctions.contains(element)) {
          optimizedStaticFunctions.add(element);
        }
        return types;
      } else {
        return HTypeList.ALL_UNKNOWN;
      }
    }

    // Getters have no parameters.
    if (element.isGetter()) return HTypeList.ALL_UNKNOWN;

    // TODO(kasperl): What kind of non-members do we get here?
    if (!element.isMember()) return HTypeList.ALL_UNKNOWN;

    FunctionSignature signature = element.computeSignature(compiler);
    HTypeList found = null;
    selectorTypeMap.visitMatching(element,
        (Selector selector, HTypeList types) {
      if (selector.argumentCount != signature.parameterCount ||
          selector.namedArgumentCount > 0) {
        types = types.unionWithOptionalParameters(selector,
                                                  signature,
                                                  defaultValueTypes);
      }
      assert(types.allUnknown || types.length == signature.parameterCount);
      found = (found === null) ? types : found.union(types);
      return !found.allUnknown;
    });
    return found !== null ? found : HTypeList.ALL_UNKNOWN;
  }

  void registerOptimization(Element element,
                            HTypeList parameterTypes,
                            OptionalParameterTypes defaultValueTypes) {
    if (Elements.isStaticOrTopLevelFunction(element)) {
      if (parameterTypes.allUnknown) {
        optimizedStaticFunctions.remove(element);
      } else {
        optimizedStaticFunctions.add(element);
      }
    }

    // TODO(kasperl): What kind of non-members do we get here?
    if (!element.isMember()) return;

    if (parameterTypes.allUnknown) {
      optimizedFunctions.remove(element);
      optimizedTypes.remove(element);
      optimizedDefaultValueTypes.remove(element);
    } else {
      optimizedFunctions.add(element);
      optimizedTypes[element] = parameterTypes;
      optimizedDefaultValueTypes[element] = defaultValueTypes;
    }
  }
}

class JavaScriptItemCompilationContext extends ItemCompilationContext {
  final HTypeMap types;

  JavaScriptItemCompilationContext() : types = new HTypeMap();
}

class JavaScriptBackend extends Backend {
  SsaBuilderTask builder;
  SsaOptimizerTask optimizer;
  SsaCodeGeneratorTask generator;
  CodeEmitterTask emitter;

  final Namer namer;

  /**
   * Interface used to determine if an object has the JavaScript
   * indexing behavior. The interface is only visible to specific
   * libraries.
   */
  ClassElement jsIndexingBehaviorInterface;

  final Map<Element, Map<Element, HType>> fieldInitializers;
  final Map<Element, Map<Element, HType>> fieldConstructorSetters;
  final Map<Element, Map<Element, HType>> fieldSettersType;

  final Map<Element, ReturnInfo> returnInfo;

  final List<Element> invalidateAfterCodegen;
  ArgumentTypesRegistry argumentTypes;

  List<CompilerTask> get tasks {
    return <CompilerTask>[builder, optimizer, generator, emitter];
  }

  JavaScriptBackend(Compiler compiler, bool generateSourceMap)
      : fieldInitializers = new Map<Element, Map<Element, HType>>(),
        fieldConstructorSetters = new Map<Element, Map<Element, HType>>(),
        fieldSettersType = new Map<Element, Map<Element, HType>>(),
        namer = new Namer(compiler),
        returnInfo = new Map<Element, ReturnInfo>(),
        invalidateAfterCodegen = new List<Element>(),
        super(compiler, constantSystem: JAVA_SCRIPT_CONSTANT_SYSTEM) {
    emitter = new CodeEmitterTask(compiler, namer, generateSourceMap);
    builder = new SsaBuilderTask(this);
    optimizer = new SsaOptimizerTask(this);
    generator = new SsaCodeGeneratorTask(this);
    argumentTypes = new ArgumentTypesRegistry(this);
  }

  Element get cyclicThrowHelper() {
    return compiler.findHelper(const SourceString("throwCyclicInit"));
  }

  JavaScriptItemCompilationContext createItemCompilationContext() {
    return new JavaScriptItemCompilationContext();
  }

  void enqueueHelpers(Enqueuer world) {
    enqueueAllTopLevelFunctions(compiler.jsHelperLibrary, world);
    enqueueAllTopLevelFunctions(compiler.interceptorsLibrary, world);

    jsIndexingBehaviorInterface =
        compiler.findHelper(const SourceString('JavaScriptIndexingBehavior'));
    if (jsIndexingBehaviorInterface != null) {
      world.registerIsCheck(jsIndexingBehaviorInterface.computeType(compiler));
    }

    for (var helper in [const SourceString('Closure'),
                        const SourceString('ConstantMap'),
                        const SourceString('ConstantProtoMap')]) {
      var e = compiler.findHelper(helper);
      if (e !== null) world.registerInstantiatedClass(e);
    }
  }

  void codegen(WorkItem work) {
    if (work.element.kind.category == ElementCategory.VARIABLE) {
      Constant initialValue = compiler.constantHandler.compileWorkItem(work);
      if (initialValue !== null) {
        return;
      } else {
        // If the constant-handler was not able to produce a result we have to
        // go through the builder (below) to generate the lazy initializer for
        // the static variable.
        // We also need to register the use of the cyclic-error helper.
        compiler.enqueuer.codegen.registerStaticUse(cyclicThrowHelper);
      }
    }

    HGraph graph = builder.build(work);
    optimizer.optimize(work, graph);
    if (work.allowSpeculativeOptimization
        && optimizer.trySpeculativeOptimizations(work, graph)) {
      CodeBuffer codeBuffer = generator.generateBailoutMethod(work, graph);
      compiler.codegenWorld.addBailoutCode(work, codeBuffer);
      optimizer.prepareForSpeculativeOptimizations(work, graph);
      optimizer.optimize(work, graph);
    }
    CodeBuffer codeBuffer = generator.generateCode(work, graph);
    compiler.codegenWorld.addGeneratedCode(work, codeBuffer);
    invalidateAfterCodegen.forEach(compiler.enqueuer.codegen.eagerRecompile);
    invalidateAfterCodegen.clear();
  }

  void processNativeClasses(Enqueuer world,
                            Collection<LibraryElement> libraries) {
    native.processNativeClasses(world, emitter, libraries);
  }

  void assembleProgram() {
    emitter.assembleProgram();
  }

  void updateFieldInitializers(Element field, HType propagatedType) {
    assert(field.isField());
    assert(field.isMember());
    Map<Element, HType> fields =
        fieldInitializers.putIfAbsent(
          field.getEnclosingClass(), () => new Map<Element, HType>());
    if (!fields.containsKey(field)) {
      fields[field] = propagatedType;
    } else {
      fields[field] = fields[field].union(propagatedType);
    }
  }

  HType typeFromInitializersSoFar(Element field) {
    assert(field.isField());
    assert(field.isMember());
    if (!fieldInitializers.containsKey(field.getEnclosingClass())) {
      return HType.CONFLICTING;
    }
    Map<Element, HType> fields = fieldInitializers[field.getEnclosingClass()];
    return fields[field];
  }

  void updateFieldConstructorSetters(Element field, HType type) {
    assert(field.isField());
    assert(field.isMember());
    Map<Element, HType> fields =
        fieldConstructorSetters.putIfAbsent(
            field.getEnclosingClass(), () => new Map<Element, HType>());
    if (!fields.containsKey(field)) {
      fields[field] = type;
    } else {
      fields[field] = fields[field].union(type);
    }
  }

  // Check if this field is set in the constructor body.
  bool hasConstructorBodyFieldSetter(Element field) {
    ClassElement enclosingClass = field.getEnclosingClass();
    if (!fieldConstructorSetters.containsKey(enclosingClass)) {
      return false;
    }
    return fieldConstructorSetters[enclosingClass][field] != null;
  }

  // Provide an optimistic estimate of the type of a field after construction.
  // If the constructor body has setters for fields returns HType.UNKNOWN.
  // This only takes the initializer lists and field assignments in the
  // constructor body into account. The constructor body might have method calls
  // that could alter the field.
  HType optimisticFieldTypeAfterConstruction(Element field) {
    assert(field.isField());
    assert(field.isMember());

    ClassElement classElement = field.getEnclosingClass();
    if (hasConstructorBodyFieldSetter(field)) {
      // If there are field setters but there is only constructor then the type
      // of the field is determined by the assignments in the constructor
      // body.
      var constructors = classElement.constructors;
      if (constructors.head !== null && constructors.tail.isEmpty()) {
        return fieldConstructorSetters[classElement][field];
      } else {
        return HType.UNKNOWN;
      }
    } else if (fieldInitializers.containsKey(classElement)) {
      HType type = fieldInitializers[classElement][field];
      return type == null ? HType.CONFLICTING : type;
    } else {
      return HType.CONFLICTING;
    }
  }

  void updateFieldSetters(Element field, HType type) {
    assert(field.isField());
    assert(field.isMember());
    Map<Element, HType> fields =
        fieldSettersType.putIfAbsent(
          field.getEnclosingClass(), () => new Map<Element, HType>());
    if (!fields.containsKey(field)) {
      fields[field] = type;
    } else {
      fields[field] = fields[field].union(type);
    }
  }

  // Returns the type that field setters are setting the field to based on what
  // have been seen during compilation so far.
  HType fieldSettersTypeSoFar(Element field) {
    assert(field.isField());
    assert(field.isMember());
    ClassElement enclosingClass = field.getEnclosingClass();
    if (!fieldSettersType.containsKey(enclosingClass)) {
      return HType.CONFLICTING;
    }
    Map<Element, HType> fields = fieldSettersType[enclosingClass];
    if (!fields.containsKey(field)) return HType.CONFLICTING;
    return fields[field];
  }

  void scheduleForRecompilation(Element element) {
    if (compiler.phase == Compiler.PHASE_COMPILING) {
      invalidateAfterCodegen.add(element);
    }
  }

  /**
   *  Register a dynamic invocation and collect the provided types for the
   *  named selector.
   */
  void registerDynamicInvocation(HInvokeDynamicMethod node,
                                 Selector selector,
                                 HTypeMap types) {
    argumentTypes.registerDynamicInvocation(node, selector, types);
  }

  /**
   *  Register a static invocation and collect the provided types for the
   *  named selector.
   */
  void registerStaticInvocation(HInvokeStatic node, HTypeMap types) {
    argumentTypes.registerStaticInvocation(node, types);
  }

  /**
   *  Register that a static is used for something else than a direct call
   *  target.
   */
  void registerNonCallStaticUse(HStatic node) {
    argumentTypes.registerNonCallStaticUse(node);
  }

  /**
   * Retrieve the types of the parameters used for calling the [element]
   * function. The types are optimistic in the sense as they are based on the
   * possible invocations of the function seen so far.
   */
  HTypeList optimisticParameterTypes(
      FunctionElement element,
      OptionalParameterTypes defaultValueTypes) {
    return argumentTypes.parameterTypes(element, defaultValueTypes);
  }

  /**
   * Register that the function [element] has been optimized under the
   * assumptions that the types [parameterType] will be used for calling it.
   * The passed [defaultValueTypes] holds the types of default values for
   * the optional parameters. If this assumption fail the function will be
   * scheduled for recompilation.
   */
  registerParameterTypesOptimization(
      FunctionElement element,
      HTypeList parameterTypes,
      OptionalParameterTypes defaultValueTypes) {
    argumentTypes.registerOptimization(
        element, parameterTypes, defaultValueTypes);
  }

  void registerReturnType(FunctionElement element, HType returnType) {
    ReturnInfo info = returnInfo[element];
    if (info != null) {
      info.update(returnType, scheduleForRecompilation);
    } else {
      returnInfo[element] = new ReturnInfo(returnType);
    }
  }

  /**
   * Retrieve the return type of the function [callee]. The type is optimistic
   * in the sense that is is based on the compilation of [callee]. If [callee]
   * is recompiled the return type might change to someting broader. For that
   * reason [caller] is registered for recompilation if this happens. If the
   * function [callee] has not yet been compiled the returned type is [null].
   */
  HType optimisticReturnTypesWithRecompilationOnTypeChange(
      Element caller, FunctionElement callee) {
    returnInfo.putIfAbsent(callee, () => new ReturnInfo.unknownType());
    ReturnInfo info = returnInfo[callee];
    if (info.returnType != HType.UNKNOWN && caller != null) {
      info.addCompiledFunction(caller);
    }
    return info.returnType;
  }

  SourceString getCheckedModeHelper(DartType type) {
    Element element = type.element;
    bool nativeCheck =
          emitter.nativeEmitter.requiresNativeIsCheck(element);
    if (element == compiler.stringClass) {
      return const SourceString('stringTypeCheck');
    } else if (element == compiler.doubleClass) {
      return const SourceString('doubleTypeCheck');
    } else if (element == compiler.numClass) {
      return const SourceString('numTypeCheck');
    } else if (element == compiler.boolClass) {
      return const SourceString('boolTypeCheck');
    } else if (element == compiler.functionClass || element.isTypedef()) {
      return const SourceString('functionTypeCheck');
    } else if (element == compiler.intClass) {
      return const SourceString('intTypeCheck');
    } else if (Elements.isStringSupertype(element, compiler)) {
      if (nativeCheck) {
        return const SourceString('stringSuperNativeTypeCheck');
      } else {
        return const SourceString('stringSuperTypeCheck');
      }
    } else if (element === compiler.listClass) {
      return const SourceString('listTypeCheck');
    } else {
      if (Elements.isListSupertype(element, compiler)) {
        if (nativeCheck) {
          return const SourceString('listSuperNativeTypeCheck');
        } else {
          return const SourceString('listSuperTypeCheck');
        }
      } else if (nativeCheck) {
        return const SourceString('callTypeCheck');
      } else {
        return const SourceString('propertyTypeCheck');
      }
    }
  }
}
