// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class LocalPlaceholder implements Hashable {
  final String identifier;
  final Set<Node> nodes;
  LocalPlaceholder(this.identifier) : nodes = new Set<Node>();
  int hashCode() => identifier.hashCode();
  String toString() =>
      'local_placeholder[id($identifier), nodes($nodes)]';
}

class FunctionScope {
  final Set<String> parameterIdentifiers;
  final Set<LocalPlaceholder> localPlaceholders;
  FunctionScope()
      : parameterIdentifiers = new Set<String>(),
      localPlaceholders = new Set<LocalPlaceholder>();
  void registerParameter(Identifier node) {
    parameterIdentifiers.add(node.source.slowToString());
  }
}

class DeclarationTypePlaceholder {
  final TypeAnnotation typeNode;
  final bool requiresVar;
  DeclarationTypePlaceholder(this.typeNode, this.requiresVar);
}

class SendVisitor extends ResolvedVisitor {
  final PlaceholderCollector collector;

  SendVisitor(this.collector, TreeElements elements) : super(elements);

  visitOperatorSend(Send node) {}
  visitForeignSend(Send node) {}

  visitSuperSend(Send node) {
    collector.tryMakeMemberPlaceholder(node.selector);
  }

  visitDynamicSend(Send node) {
    final element = elements[node];
    if (element === null || !element.isErroneous()) {
      collector.tryMakeMemberPlaceholder(node.selector);
    }
  }

  visitClosureSend(Send node) {
    final element = elements[node];
    if (element !== null) {
      collector.tryMakeLocalPlaceholder(element, node.selector);
    }
  }

  visitGetterSend(Send node) {
    final element = elements[node];
    // element === null means dynamic property access.
    if (element === null) {
      collector.tryMakeMemberPlaceholder(node.selector);
    } else if (element.isPrefix()) {
      // Node is prefix part in case of source 'lib.somesetter = 5;'
      collector.makeNullPlaceholder(node);
    } else if (Elements.isStaticOrTopLevel(element)) {
      // Unqualified or prefixed top level or static.
      collector.makeElementPlaceholder(node.selector, element);
    } else if (!element.isTopLevel()) {
      if (element.isInstanceMember()) {
        collector.tryMakeMemberPlaceholder(node.selector);
      } else {
        // May get FunctionExpression here in selector
        // in case of A(int this.f());
        if (node.selector is Identifier) {
          collector.tryMakeLocalPlaceholder(element, node.selector);
        } else {
          assert(node.selector is FunctionExpression);
        }
      }
    }
  }

  visitStaticSend(Send node) {
    final element = elements[node];
    if (element.isConstructor() || element.isFactoryConstructor()) {
      // Rename named constructor in redirection position:
      // class C { C.named(); C.redirecting() : this.named(); }
      if (node.receiver is Identifier
          && node.receiver.asIdentifier().isThis()) {
        assert(node.selector is Identifier);
        collector.tryMakeMemberPlaceholder(node.selector);
      }
      // Field names can be exposed as names of optional arguments, e.g.
      // class C {
      //   final field;
      //   C([this.field]);
      // }
      // Do not forget to rename them as well.
      FunctionElement functionElement = element;
      Link<Element> optionalParameters =
          functionElement.functionSignature.optionalParameters;
      for (final argument in node.argumentsNode) {
        NamedArgument named = argument.asNamedArgument();
        if (named === null) continue;
        Identifier name = named.name;
        String nameAsString = name.source.slowToString();
        for (final parameter in optionalParameters) {
          if (parameter.kind === ElementKind.FIELD_PARAMETER) {
            if (parameter.name.slowToString() == nameAsString) {
              collector.tryMakeMemberPlaceholder(name);
              break;
            }
          }
        }
      }
      return;
    }
    collector.makeElementPlaceholder(node.selector, element);
    // Another ugly case: <lib prefix>.<top level> is represented as
    // receiver: lib prefix, selector: top level.
    if (element.isTopLevel() && node.receiver !== null) {
      assert(elements[node.receiver].isPrefix());
      // Hack: putting null into map overrides receiver of original node.
      collector.makeNullPlaceholder(node.receiver);
    }
  }

  internalError(String reason, [Node node]) {
    collector.internalError(reason, node);
  }
}

class PlaceholderCollector extends AbstractVisitor {
  final Compiler compiler;
  final Set<String> fixedMemberNames; // member names which cannot be renamed.
  final Set<Node> nullNodes;  // Nodes that should not be in output.
  final Set<Identifier> unresolvedNodes;
  final Map<Element, Set<Node>> elementNodes;
  final Map<FunctionElement, FunctionScope> functionScopes;
  final Map<LibraryElement, Set<Identifier>> privateNodes;
  final List<DeclarationTypePlaceholder> declarationTypePlaceholders;
  final Map<String, Set<Identifier>> memberPlaceholders;
  Map<String, LocalPlaceholder> currentLocalPlaceholders;
  Element currentElement;
  TreeElements treeElements;

  LibraryElement get coreLibrary => compiler.coreLibrary;
  FunctionElement get entryFunction => compiler.mainApp.find(Compiler.MAIN);

  PlaceholderCollector(this.compiler, this.fixedMemberNames) :
      nullNodes = new Set<Node>(),
      unresolvedNodes = new Set<Identifier>(),
      elementNodes = new Map<Element, Set<Node>>(),
      functionScopes = new Map<FunctionElement, FunctionScope>(),
      privateNodes = new Map<LibraryElement, Set<Identifier>>(),
      declarationTypePlaceholders = new List<DeclarationTypePlaceholder>(),
      memberPlaceholders = new Map<String, Set<Identifier>>();

  void tryMakeConstructorNamePlaceholder(
      FunctionExpression constructor, ClassElement element) {
    Node nameNode = constructor.name;
    if (nameNode is Send) nameNode = nameNode.receiver;
    if (nameNode.asIdentifier().token.slowToString()
        == element.name.slowToString()) {
      makeElementPlaceholder(nameNode, element);
    }
  }

  void collectFunctionDeclarationPlaceholders(
      FunctionElement element, FunctionExpression node) {
    if (element.isGenerativeConstructor() || element.isFactoryConstructor()) {
      // Two complicated cases for class/interface renaming:
      // 1) class which implements constructors of other interfaces, but not
      //    implements interfaces themselves:
      //      0.dart: class C { I(); }
      //      1.dart and 2.dart: interface I default C { I(); }
      //    now we have to duplicate our I() constructor in C class with
      //    proper names.
      // 2) (even worse for us):
      //      0.dart: class C { C(); }
      //      1.dart: interface C default p0.C { C(); }
      //    the second case is just a bug now.
      tryMakeConstructorNamePlaceholder(node, element.getEnclosingClass());

      // If we have interface constructor, make sure that we put placeholder
      // for its default factory implementation.
      // Example:
      // interface I default C { I();}
      // class C { factory I() {} }
      // 2 cases:
      // Plain interface name. Rename it unless it is the default
      // constructor for enclosing class.
      // Example:
      // interface I { I(); }
      // class C implements I { C(); }  don't rename this case.
      // OR I.named() inside C, rename first part.
      if (element.defaultImplementation !== null
          && element.defaultImplementation !== element) {
        FunctionElement implementingFactory = element.defaultImplementation;
        tryMakeConstructorNamePlaceholder(implementingFactory.cachedNode,
            element.getEnclosingClass());
      }
    } else if (Elements.isStaticOrTopLevel(element)) {
      // Note: this code should only rename private identifiers for class'
      // fields/getters/setters/methods.  Top-level identifiers are renamed
      // just to escape conflicts and that should be enough as we shouldn't
      // be able to resolve private identifiers for other libraries.
      makeElementPlaceholder(node.name, element);
    } else if (element.isMember()) {
      if (node.name is Identifier) {
        tryMakeMemberPlaceholder(node.name);
      } else {
        assert(node.name.asSend().isOperator);
      }
    }
  }

  void collectFieldDeclarationPlaceholders(Element element, Node node) {
    Identifier name = node is Identifier ? node : node.asSend().selector;
    if (Elements.isStaticOrTopLevel(element)) {
      makeElementPlaceholder(name, element);
    } else if (Elements.isInstanceField(element)) {
      tryMakeMemberPlaceholder(name);
    }
  }

  void collect(Element element, TreeElements elements) {
    treeElements = elements;
    currentElement = element;
    Node elementNode = currentElement.parseNode(compiler);
    if (element is FunctionElement) {
      collectFunctionDeclarationPlaceholders(element, elementNode);
    } else if (element is VariableListElement) {
      VariableDefinitions definitions = elementNode;
      for (Node definition in definitions.definitions) {
        final definitionElement = elements[definition];
        // definitionElement === null if variable is actually unused.
        if (definitionElement === null) continue;
        collectFieldDeclarationPlaceholders(definitionElement, definition);
      }
      makeVarDeclarationTypePlaceholder(definitions);
    } else {
      assert(element is ClassElement || element is TypedefElement);
    }
    currentLocalPlaceholders = new Map<String, LocalPlaceholder>();
    compiler.withCurrentElement(element, () {
      elementNode.accept(this);
    });
  }

  void tryMakeLocalPlaceholder(Element element, Identifier node) {
    bool isOptionalParameter() {
      FunctionElement function = element.enclosingElement;
      for (Element parameter in function.functionSignature.optionalParameters) {
        if (parameter === element) return true;
      }
      return false;
    }

    // TODO(smok): Maybe we should rename privates as well, their privacy
    // should not matter if they are local vars.
    if (node.source.isPrivate()) return;
    if (element.isParameter() && isOptionalParameter()) {
      functionScopes.putIfAbsent(currentElement, () => new FunctionScope())
          .registerParameter(node);
    } else if (Elements.isLocal(element)) {
      makeLocalPlaceholder(node);
    }
  }

  void tryMakeMemberPlaceholder(Identifier node) {
    assert(node !== null);
    if (node.source.isPrivate()) return;
    if (node is Operator) return;
    final identifier = node.source.slowToString();
    if (fixedMemberNames.contains(identifier)) return;
    memberPlaceholders.putIfAbsent(
        identifier, () => new Set<Identifier>()).add(node);
  }

  void makeTypePlaceholder(Node node, DartType type) {
    makeElementPlaceholder(node, type.element);
  }

  void makeOmitDeclarationTypePlaceholder(TypeAnnotation type) {
    if (type === null) return;
    declarationTypePlaceholders.add(
        new DeclarationTypePlaceholder(type, false));
  }

  void makeVarDeclarationTypePlaceholder(VariableDefinitions node) {
    // TODO(smok): Maybe instead of calling this method and
    // makeDeclaratioTypePlaceholder have type declaration placeholder
    // collector logic in visitVariableDefinitions when resolver becomes better
    // and/or catch syntax changes.
    if (node.type === null) return;
    Element definitionElement = treeElements[node.definitions.nodes.head];
    bool requiresVar = !node.modifiers.isFinalOrConst();
    declarationTypePlaceholders.add(
        new DeclarationTypePlaceholder(node.type, requiresVar));
  }

  void makeNullPlaceholder(Node node) {
    assert(node is Identifier || node is Send);
    nullNodes.add(node);
  }

  void makeElementPlaceholder(Node node, Element element) {
    assert(element !== null);
    if (element === entryFunction) return;
    if (element.getLibrary() === coreLibrary) return;
    if (element.getLibrary().isPlatformLibrary && !element.isTopLevel()) {
      return;
    }
    if (element == compiler.types.dynamicType.element) {
      internalError(
          'Should never make element placeholder for dynamic type element',
          node);
    }
    elementNodes.putIfAbsent(element, () => new Set<Node>()).add(node);
  }

  void makePrivateIdentifier(Identifier node) {
    assert(node !== null);
    privateNodes.putIfAbsent(
        currentElement.getLibrary(), () => new Set<Identifier>()).add(node);
  }

  void makeUnresolvedPlaceholder(Node node) {
    unresolvedNodes.add(node);
  }

  void makeLocalPlaceholder(Identifier identifier) {
    LocalPlaceholder getLocalPlaceholder() {
      String name = identifier.source.slowToString();
      return currentLocalPlaceholders.putIfAbsent(name, () {
        LocalPlaceholder localPlaceholder = new LocalPlaceholder(name);
        functionScopes.putIfAbsent(currentElement, () => new FunctionScope())
            .localPlaceholders.add(localPlaceholder);
        return localPlaceholder;
      });
    }

    assert(currentElement is FunctionElement);
    getLocalPlaceholder().nodes.add(identifier);
  }

  void internalError(String reason, [Node node]) {
    compiler.cancel(reason: reason, node: node);
  }

  void unreachable() { internalError('Unreachable case'); }

  visit(Node node) => (node === null) ? null : node.accept(this);

  visitNode(Node node) { node.visitChildren(this); }  // We must go deeper.

  visitSend(Send send) {
    new SendVisitor(this, treeElements).visitSend(send);
    send.visitChildren(this);
  }

  visitSendSet(SendSet send) {
    final element = treeElements[send];
    if (element !== null) {
      if (Elements.isStaticOrTopLevel(element)) {
        assert(element is VariableElement || element.isSetter());
        makeElementPlaceholder(send.selector, element);
      } else {
        assert(send.selector is Identifier);
        if (Elements.isInstanceField(element)) {
          tryMakeMemberPlaceholder(send.selector);
        } else {
          tryMakeLocalPlaceholder(element, send.selector);
        }
      }
    } else {
      if (send.receiver !== null) {
        tryMakeMemberPlaceholder(send.selector);
      }
    }
    send.visitChildren(this);
  }

  visitIdentifier(Identifier identifier) {
    if (identifier.source.isPrivate()) makePrivateIdentifier(identifier);
  }

  static bool isPlainTypeName(TypeAnnotation typeAnnotation) {
    if (typeAnnotation.typeName is !Identifier) return false;
    if (typeAnnotation.typeArguments === null) return true;
    if (typeAnnotation.typeArguments.length === 0) return true;
    return false;
  }

  static bool isDynamicType(TypeAnnotation typeAnnotation) {
    if (!isPlainTypeName(typeAnnotation)) return false;
    String name = typeAnnotation.typeName.asIdentifier().source.slowToString();
    return name == 'Dynamic';
  }

  visitTypeAnnotation(TypeAnnotation node) {
    // Poor man generic variables resolution.
    // TODO(antonm): get rid of it once resolver can deal with it.
    TypeDeclarationElement typeDeclarationElement;
    if (currentElement is TypeDeclarationElement) {
      typeDeclarationElement = currentElement;
    } else {
      typeDeclarationElement = currentElement.getEnclosingClass();
    }
    if (typeDeclarationElement !== null && isPlainTypeName(node)
        && tryResolveAndCollectTypeVariable(
               typeDeclarationElement, node.typeName)) {
      return;
    }
    final type = compiler.resolveTypeAnnotation(currentElement, node);
    if (type is InterfaceType || type is TypedefType) {
      var target = node.typeName;
      if (node.typeName is Send) {
        final element = treeElements[node];
        if (element !== null) {
          final send = node.typeName.asSend();
          Identifier receiver = send.receiver;
          Identifier selector = send.selector;
          hasPrefix() {
            if (element is TypedefElement) return true;
            ClassElement classElement = element;
            final constructor = classElement.lookupConstructor(
                receiver.source, selector.source);
            return constructor === null;
          }
          if (!hasPrefix()) target = send.receiver;
        }
      }
      // TODO(antonm): is there a better way to detect unresolved types?
      if (type.element !== compiler.types.dynamicType.element) {
        makeTypePlaceholder(target, type);
      } else {
        if (!isDynamicType(node)) makeUnresolvedPlaceholder(target);
      }
    }
    node.visitChildren(this);
  }

  visitVariableDefinitions(VariableDefinitions node) {
    // Collect only local placeholders.
    if (currentElement is FunctionElement) {
      for (Node definition in node.definitions.nodes) {
        Element definitionElement = treeElements[definition];
        // definitionElement may be null if we're inside variable definitions
        // of a function that is a parameter of another function.
        // TODO(smok): Fix this when resolver correctly deals with
        // such cases.
        if (definitionElement === null) continue;
        if (definition is Send) {
          // May get FunctionExpression here in definition.selector
          // in case of A(int this.f());
          if (definition.selector is Identifier) {
            if (definitionElement.kind === ElementKind.FIELD_PARAMETER) {
              tryMakeMemberPlaceholder(definition.selector);
            } else {
              tryMakeLocalPlaceholder(definitionElement, definition.selector);
            }
          } else {
            assert(definition.selector is FunctionExpression);
            if (definitionElement.kind === ElementKind.FIELD_PARAMETER) {
              tryMakeMemberPlaceholder(
                  definition.selector.asFunctionExpression().name);
            }
          }
        } else if (definition is Identifier) {
          tryMakeLocalPlaceholder(definitionElement, definition);
        } else if (definition is FunctionExpression) {
          // Skip, it will be processed in visitFunctionExpression.
        } else {
          internalError('Unexpected definition structure $definition');
        }
      }
    }
    node.visitChildren(this);
  }

  visitFunctionExpression(FunctionExpression node) {
    Element element = treeElements[node];
    // May get null here in case of A(int this.f());
    if (element !== null) {
      // Rename only local functions.
      if (element !== currentElement) {
        if (node.name !== null) {
          assert(node.name is Identifier);
          tryMakeLocalPlaceholder(element, node.name);
        }
      }
    }
    node.visitChildren(this);
    makeOmitDeclarationTypePlaceholder(node.returnType);
    collectFunctionParameters(node.parameters);
  }

  void collectFunctionParameters(NodeList parameters) {
    if (parameters === null) return;
    for (Node parameter in parameters.nodes) {
      if (parameter is NodeList) {
        // Optional parameter list.
        collectFunctionParameters(parameter);
      } else {
        assert(parameter is VariableDefinitions);
        makeOmitDeclarationTypePlaceholder(
            parameter.asVariableDefinitions().type);
      }
    }
  }

  visitClassNode(ClassNode node) {
    ClassElement classElement = currentElement;
    makeElementPlaceholder(node.name, classElement);
    node.visitChildren(this);
    if (node.defaultClause !== null) {
      // Can't just visit class node's default clause because of the bug in the
      // resolver, it just crashes when it meets type variable.
      DartType defaultType = classElement.defaultClass;
      assert(defaultType !== null);
      makeTypePlaceholder(node.defaultClause.typeName, defaultType);
      visit(node.defaultClause.typeArguments);
    }
  }

  bool tryResolveAndCollectTypeVariable(
      TypeDeclarationElement typeDeclaration, Identifier name) {
    // Hack for case when interface and default class are in different
    // libraries, try to resolve type variable to default class type arg.
    // Example:
    // lib1: interface I<K> default C<K> {...}
    // lib2: class C<K> {...}
    if (typeDeclaration is ClassElement
        && (typeDeclaration as ClassElement).defaultClass !== null) {
      typeDeclaration = (typeDeclaration as ClassElement).defaultClass.element;
    }
    // Another poor man type resolution.
    // Find this variable in enclosing type declaration parameters.
    for (DartType type in typeDeclaration.typeVariables) {
      if (type.name.slowToString() == name.source.slowToString()) {
        makeTypePlaceholder(name, type);
        return true;
      }
    }
    return false;
  }

  visitTypeVariable(TypeVariable node) {
    assert(currentElement is TypedefElement || currentElement is ClassElement);
    tryResolveAndCollectTypeVariable(currentElement, node.name);
    node.visitChildren(this);
  }

  visitTypedef(Typedef node) {
    assert(currentElement is TypedefElement);
    makeElementPlaceholder(node.name, currentElement);
    node.visitChildren(this);
    makeOmitDeclarationTypePlaceholder(node.returnType);
    collectFunctionParameters(node.formals);
  }

  visitBlock(Block node) {
    for (Node statement in node.statements.nodes) {
      if (statement is VariableDefinitions) {
        makeVarDeclarationTypePlaceholder(statement);
      }
    }
    node.visitChildren(this);
  }
}
