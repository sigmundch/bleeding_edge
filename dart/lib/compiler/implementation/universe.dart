// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class Universe {
  Map<Element, CodeBuffer> generatedCode;
  Map<Element, CodeBuffer> generatedBailoutCode;
  final Set<ClassElement> instantiatedClasses;
  final Set<FunctionElement> staticFunctionsNeedingGetter;
  final Map<SourceString, Set<Selector>> invokedNames;
  final Map<SourceString, Set<Selector>> invokedGetters;
  final Map<SourceString, Set<Selector>> invokedSetters;
  final Map<SourceString, Set<Selector>> fieldGetters;
  final Map<SourceString, Set<Selector>> fieldSetters;
  final Set<DartType> isChecks;
  // TODO(karlklose): move this data to RuntimeTypeInformation.
  Set<Element> checkedClasses;
  final RuntimeTypeInformation rti;

  Universe() : generatedCode = new Map<Element, CodeBuffer>(),
               generatedBailoutCode = new Map<Element, CodeBuffer>(),
               instantiatedClasses = new Set<ClassElement>(),
               staticFunctionsNeedingGetter = new Set<FunctionElement>(),
               invokedNames = new Map<SourceString, Set<Selector>>(),
               invokedGetters = new Map<SourceString, Set<Selector>>(),
               invokedSetters = new Map<SourceString, Set<Selector>>(),
               fieldGetters = new Map<SourceString, Set<Selector>>(),
               fieldSetters = new Map<SourceString, Set<Selector>>(),
               isChecks = new Set<DartType>(),
               rti = new RuntimeTypeInformation();

  // TODO(karlklose): add the set of instantiatedtypes as second argument.
  void computeRequiredTypes(Set<DartType> isChecks) {
    assert(checkedClasses == null);
    checkedClasses = new Set<Element>();
    isChecks.forEach((DartType t) => checkedClasses.add(t.element));
  }

  void addGeneratedCode(WorkItem work, CodeBuffer codeBuffer) {
    generatedCode[work.element] = codeBuffer;
  }

  void addBailoutCode(WorkItem work, CodeBuffer codeBuffer) {
    generatedBailoutCode[work.element] = codeBuffer;
  }

  bool hasMatchingSelector(Set<Selector> selectors,
                           Element member,
                           Compiler compiler) {
    if (selectors === null) return false;
    for (Selector selector in selectors) {
      if (selector.applies(member, compiler)) return true;
    }
    return false;
  }

  bool hasInvocation(Element member, Compiler compiler) {
    return hasMatchingSelector(invokedNames[member.name], member, compiler);
  }

  bool hasInvokedGetter(Element member, Compiler compiler) {
    return hasMatchingSelector(invokedGetters[member.name], member, compiler);
  }

  bool hasInvokedSetter(Element member, Compiler compiler) {
    return hasMatchingSelector(invokedSetters[member.name], member, compiler);
  }

  bool hasFieldGetter(Element member, Compiler compiler) {
    return hasMatchingSelector(fieldGetters[member.name], member, compiler);
  }

  bool hasFieldSetter(Element member, Compiler compiler) {
    return hasMatchingSelector(fieldSetters[member.name], member, compiler);
  }
}

class SelectorKind {
  final String name;
  const SelectorKind(this.name);

  static const SelectorKind GETTER = const SelectorKind('getter');
  static const SelectorKind SETTER = const SelectorKind('setter');
  static const SelectorKind CALL = const SelectorKind('call');
  static const SelectorKind OPERATOR = const SelectorKind('operator');
  static const SelectorKind INDEX = const SelectorKind('index');

  toString() => name;
}

class Selector implements Hashable {
  final SelectorKind kind;
  final SourceString name;
  final LibraryElement library; // Library is null for non-private selectors.

  // The numbers of arguments of the selector. Includes named arguments.
  final int argumentCount;
  final List<SourceString> namedArguments;
  final List<SourceString> orderedNamedArguments;

  Selector(
      this.kind,
      SourceString name,
      LibraryElement library,
      this.argumentCount,
      [List<SourceString> namedArguments = const <SourceString>[]])
    : this.name = name,
      this.library = name.isPrivate() ? library : null,
      this.namedArguments = namedArguments,
      this.orderedNamedArguments = namedArguments.isEmpty()
          ? namedArguments
          : <SourceString>[] {
    assert(!name.isPrivate() || library != null);
  }

  Selector.getter(SourceString name, LibraryElement library)
      : this(SelectorKind.GETTER, name, library, 0);

  Selector.getterFrom(Selector selector)
      : this(SelectorKind.GETTER, selector.name, selector.library, 0);

  Selector.setter(SourceString name, LibraryElement library)
      : this(SelectorKind.SETTER, name, library, 1);

  Selector.unaryOperator(SourceString name)
      : this(SelectorKind.OPERATOR,
             Elements.constructOperatorName(name, true),
             null, 0);

  Selector.binaryOperator(SourceString name)
      : this(SelectorKind.OPERATOR,
             Elements.constructOperatorName(name, false),
             null, 1);

  Selector.index()
      : this(SelectorKind.INDEX,
             Elements.constructOperatorName(const SourceString("[]"), false),
             null, 1);

  Selector.indexSet()
      : this(SelectorKind.INDEX,
             Elements.constructOperatorName(const SourceString("[]="), false),
             null, 2);

  Selector.call(SourceString name,
                LibraryElement library,
                int arity,
                [List<SourceString> named = const []])
      : this(SelectorKind.CALL, name, library, arity, named);

  Selector.callClosure(int arity, [List<SourceString> named = const []])
      : this(SelectorKind.CALL, Compiler.CALL_OPERATOR_NAME, null,
             arity, named);

  Selector.callClosureFrom(Selector selector)
      : this(SelectorKind.CALL, Compiler.CALL_OPERATOR_NAME, null,
             selector.argumentCount, selector.namedArguments);

  // TODO(kasperl): This belongs somewhere else.
  Selector.noSuchMethod()
      : this(SelectorKind.CALL, Compiler.NO_SUCH_METHOD, null, 2);

  bool isGetter() => kind === SelectorKind.GETTER;
  bool isSetter() => kind === SelectorKind.SETTER;
  bool isCall() => kind === SelectorKind.CALL;

  bool isIndex() => kind === SelectorKind.INDEX && argumentCount == 1;
  bool isIndexSet() => kind === SelectorKind.INDEX && argumentCount == 2;

  bool isOperator() => kind === SelectorKind.OPERATOR;
  bool isUnaryOperator() => isOperator() && argumentCount == 0;
  bool isBinaryOperator() => isOperator() && argumentCount == 1;

  /** Check whether this is a call to 'assert' with one positional parameter. */
  bool isAssertSyntax() {
    return (isCall() &&
            name.stringValue === "assert" &&
            argumentCount == 1 &&
            namedArgumentCount == 0);
  }

  int hashCode() => argumentCount + 1000 * namedArguments.length;
  int get namedArgumentCount => namedArguments.length;
  int get positionalArgumentCount => argumentCount - namedArgumentCount;
  DartType get receiverType => null;

  bool applies(Element element, Compiler compiler)
      => appliesUntyped(element, compiler);

  bool appliesUntyped(Element element, Compiler compiler) {
    if (element.isSetter()) return isSetter();
    if (element.isGetter()) return isGetter() || isCall();
    if (element.isField()) return isGetter() || isSetter() || isCall();
    if (isGetter()) return true;

    FunctionElement function = element;
    FunctionSignature parameters = function.computeSignature(compiler);
    if (argumentCount > parameters.parameterCount) return false;
    int requiredParameterCount = parameters.requiredParameterCount;
    int optionalParameterCount = parameters.optionalParameterCount;
    if (positionalArgumentCount < requiredParameterCount) return false;

    bool hasOptionalParameters = !parameters.optionalParameters.isEmpty();
    if (namedArguments.isEmpty()) {
      if (!hasOptionalParameters) {
        return requiredParameterCount == argumentCount;
      } else {
        return argumentCount >= requiredParameterCount &&
            argumentCount <= requiredParameterCount + optionalParameterCount;
      }
    } else {
      if (!hasOptionalParameters) return false;
      Link<Element> remainingNamedParameters = parameters.optionalParameters;
      for (int i = requiredParameterCount; i < positionalArgumentCount; i++) {
        remainingNamedParameters = remainingNamedParameters.tail;
      }
      Set<SourceString> nameSet = new Set<SourceString>();
      for (;
           !remainingNamedParameters.isEmpty();
           remainingNamedParameters = remainingNamedParameters.tail) {
        nameSet.add(remainingNamedParameters.head.name);
      }

      for (SourceString name in namedArguments) {
        if (!nameSet.contains(name)) {
          return false;
        }
        nameSet.remove(name);
      }
      return true;
    }
  }

  /**
   * Returns [:true:] if the selector and the [element] match; [:false:]
   * otherwise.
   */
  bool addArgumentsToList(Link<Node> arguments,
                          List list,
                          FunctionElement element,
                          compileArgument(Node argument),
                          compileConstant(Element element),
                          Compiler compiler) {
    if (!this.applies(element, compiler)) return false;

    void addMatchingArgumentsToList(Link<Node> link) {}

    FunctionSignature parameters = element.computeSignature(compiler);
    if (this.positionalArgumentCount == parameters.parameterCount) {
      for (Link<Node> link = arguments; !link.isEmpty(); link = link.tail) {
        list.add(compileArgument(link.head));
      }
      return true;
    }

    // If there are named arguments, provide them in the order
    // expected by the called function, which is the source order.

    // Visit positional arguments and add them to the list.
    int positionalArgumentCount = this.positionalArgumentCount;
    for (int i = 0;
         i < positionalArgumentCount;
         arguments = arguments.tail, i++) {
      list.add(compileArgument(arguments.head));
    }

    // Visit named arguments and add them into a temporary list.
    List compiledNamedArguments = [];
    for (; !arguments.isEmpty(); arguments = arguments.tail) {
      NamedArgument namedArgument = arguments.head;
      compiledNamedArguments.add(compileArgument(namedArgument.expression));
    }

    Link<Element> remainingNamedParameters = parameters.optionalParameters;
    // Skip the optional parameters that have been given in the
    // positional arguments.
    for (int i = parameters.requiredParameterCount;
         i < positionalArgumentCount;
         i++) {
      remainingNamedParameters = remainingNamedParameters.tail;
    }

    // Loop over the remaining named parameters, and try to find
    // their values: either in the temporary list or using the
    // default value.
    for (;
         !remainingNamedParameters.isEmpty();
         remainingNamedParameters = remainingNamedParameters.tail) {
      Element parameter = remainingNamedParameters.head;
      int foundIndex = -1;
      for (int i = 0; i < namedArguments.length; i++) {
        SourceString name = namedArguments[i];
        if (name == parameter.name) {
          foundIndex = i;
          break;
        }
      }
      if (foundIndex != -1) {
        list.add(compiledNamedArguments[foundIndex]);
      } else {
        list.add(compileConstant(parameter));
      }
    }
    return true;
  }

  static bool sameNames(List<SourceString> first, List<SourceString> second) {
    for (int i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  bool operator ==(other) {
    if (other is !Selector) return false;
    return receiverType === other.receiverType
        && equalsUntyped(other);
  }

  bool equalsUntyped(Selector other) {
    return name == other.name
           && library === other.library
           && argumentCount == other.argumentCount
           && namedArguments.length == other.namedArguments.length
           && sameNames(namedArguments, other.namedArguments);
  }

  List<SourceString> getOrderedNamedArguments() {
    if (namedArguments.isEmpty()) return namedArguments;
    if (!orderedNamedArguments.isEmpty()) return orderedNamedArguments;

    orderedNamedArguments.addAll(namedArguments);
    orderedNamedArguments.sort((SourceString first, SourceString second) {
      return first.slowToString().compareTo(second.slowToString());
    });
    return orderedNamedArguments;
  }

  String namedArgumentsToString() {
    if (namedArgumentCount > 0) {
      StringBuffer result = new StringBuffer();
      for (int i = 0; i < namedArgumentCount; i++) {
        if (i != 0) result.add(', ');
        result.add(namedArguments[i].slowToString());
      }
      return "[$result]";
    }
    return '';
  }

  String toString() {
    String named = '';
    String type = '';
    if (namedArgumentCount > 0) named = ', named=${namedArgumentsToString()}';
    if (receiverType != null) type = ', type=$receiverType';
    return 'Selector($kind, ${name.slowToString()}, '
           'arity=$argumentCount$named$type)';
  }
}

class TypedSelector extends Selector {
  /**
   * The type of the receiver. Any subtype of that type can be the
   * target of the invocation.
   */
  final DartType receiverType;

  TypedSelector(this.receiverType, Selector selector)
    : super(selector.kind,
            selector.name,
            selector.library,
            selector.argumentCount,
            selector.namedArguments);

  /**
   * Check if [element] will be the one used at runtime when being
   * invoked on an instance of [cls].
   */
  bool hasElementIn(ClassElement cls, Element element) {
    Element resolved = cls.lookupMember(element.name);
    if (resolved === element) return true;
    if (resolved === null) return false;
    if (resolved.kind === ElementKind.ABSTRACT_FIELD) {
      AbstractFieldElement field = resolved;
      if (element === field.getter || element === field.setter) {
        return true;
      } else {
        ClassElement otherCls = field.getEnclosingClass();
        // We have not found a match, but another class higher in the
        // hierarchy may define the getter or the setter.
        return hasElementIn(otherCls.superclass, element);
      }
    }
    return false;
  }

  bool applies(Element element, Compiler compiler) {
    if (!element.isMember()) return false;

    // A closure can be called through any typed selector:
    // class A {
    //   get foo => () => 42;
    //   bar() => foo(); // The call to 'foo' is a typed selector.
    // }
    ClassElement other = element.getEnclosingClass();
    if (other.superclass === compiler.closureClass) {
      return appliesUntyped(element, compiler);
    }

    ClassElement self = receiverType.element;
    if (other.implementsInterface(self) || other.isSubclassOf(self)) {
      return appliesUntyped(element, compiler);
    }

    if (!self.isInterface() && self.isSubclassOf(other)) {
      // Resolve an invocation of [element.name] on [self]. If it
      // is found, this selector is a candidate.
      return hasElementIn(self, element) && appliesUntyped(element, compiler);
    }

    return false;
  }
}
