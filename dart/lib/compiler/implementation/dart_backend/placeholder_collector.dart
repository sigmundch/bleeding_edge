// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class SendVisitor extends ResolvedVisitor {
  final PlaceholderCollector collector;

  SendVisitor(this.collector, TreeElements elements) : super(elements);

  visitSuperSend(Send node) {}
  visitOperatorSend(Send node) {}
  visitClosureSend(Send node) {}
  visitForeignSend(Send node) {}

  visitDynamicSend(Send node) {
    tryRenamePrivateSelector(node);
  }

  visitGetterSend(Send node) {
    final element = elements[node];
    // element === null means dynamic property access.
    if (element === null || element.isInstanceMember()) {
      tryRenamePrivateSelector(node);
      return;
    }
    // We don't want to rename non top-level element access.
    if (!element.isTopLevel()) return;
    // Unqualified <class> in static invocation, why it's not a type annotation?
    // Another option would be to process in visitStaticSend, NB:
    // those elements are not top-level.
    // OR: unqualified top level.
    collector.makeElementPlaceholder(node.selector, element);
    if (node.receiver !== null) {
      // <lib prefix>.<top level>.
      collector.makeNullPlaceholder(node.receiver);  // Cut library prefix.
    }
  }

  visitStaticSend(Send node) {
    final element = elements[node];
    if (!element.isTopLevel()) return;
    // Another ugly case: <lib prefix>.<top level> is represented as
    // receiver: lib prefix, selector: top level.
    collector.makeElementPlaceholder(node.selector, element);
    if (node.receiver !== null) {
      assert(elements[node.receiver].isPrefix());
      // Hack: putting null into map overrides receiver of original node.
      collector.makeNullPlaceholder(node.receiver);
    }
  }

  tryRenamePrivateSelector(Send node) {
    collector.tryMakePrivateIdentifier(node.selector.asIdentifier());
  }
}

class PlaceholderCollector extends AbstractVisitor {
  final Compiler compiler;
  final Map<Node, Placeholder> placeholders;
  Element currentElement;
  TreeElements treeElements;

  PlaceholderCollector(this.compiler) :
      placeholders = new Map<Node, Placeholder>();

  void collectFunctionDeclarationPlaceholders(
      FunctionElement element, Node node) {
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
      final enclosingClass = element.getEnclosingClass();
      Node nameNode = node.name;
      if (nameNode is Send) nameNode = nameNode.receiver;
      // For cases like class C implements I { I(); }
      if (nameNode.token.slowToString() == enclosingClass.name.slowToString()) {
        makeTypePlaceholder(nameNode, enclosingClass.type);
      }
      // Process Ctor(this._field) correctly.
      for (Node parameter in node.parameters) {
        VariableDefinitions definitions = parameter.asVariableDefinitions();
        if (definitions !== null) {
          for (Node definition in definitions.definitions) {
            Send send = definition.asSend();
            if (send !== null) {
              assert(send.receiver.isThis());
              tryMakePrivateIdentifier(send.selector.asIdentifier());
            } else {
              assert(definition is Identifier);
            }
          }
        } else {
          assert(parameter is NodeList);
          // We don't have to rename privates in optionals.
        }
      }
    } else if (element.isTopLevel()) {
      // Note: this code should only rename private identifiers for class'
      // fields/getters/setters/methods.  Top-level identifiers are renamed
      // just to escape conflicts and that should be enough as we shouldn't
      // be able to resolve private identifiers for other libraries.
      makeElementPlaceholder(node.name, element);
    } else {
      if (node.name !== null) {
        Identifier identifier = node.name.asIdentifier();
        // operator <blah> names shouldn't be renamed.
        if (identifier !== null) tryMakePrivateIdentifier(identifier);
      }
    }
  }

  void collectFieldDeclarationPlaceholders(Element element, Node node) {
    if (element.isInstanceMember()) {
      for (Node definition in node.definitions) {
        if (definition is Identifier) {
          tryMakePrivateIdentifier(definition.asIdentifier());
        } else if (definition is SendSet) {
          tryMakePrivateIdentifier(
              definition.asSendSet().selector.asIdentifier());
        } else {
          assert(false); // Unreachable.
        }
      }
    }
  }
  
  void collect(Element element, TreeElements elements) {
    treeElements = elements;
    Node elementNode;
    if (element is FunctionElement) {
      currentElement = element;
      elementNode = currentElement.parseNode(compiler);
      collectFunctionDeclarationPlaceholders(element, elementNode);
    } else if (element.isField()) {
      // TODO(smok): In the future make sure we don't process same
      // variable list element twice, better merge this with emitter logic.
      currentElement = element.variables;
      elementNode = currentElement.parseNode(compiler);
      collectFieldDeclarationPlaceholders(element, elementNode);
    } else {
      assert(false); // Unreachable.
    }
    elementNode.accept(this);
  }

  Type resolveType(TypeAnnotation typeAnnotation) {
    if (treeElements === null) return null;
    var result = treeElements.getType(typeAnnotation);
    // TODO: Have better type resolution.
    if (result === null) {
      result = compiler.resolveTypeAnnotation(currentElement, typeAnnotation);
    }
    return result;
  }

  tryMakePrivateIdentifier(Identifier identifier) {
    if (identifier.source.isPrivate()) makePrivateIdentifier(identifier);
  }

  void makeTypePlaceholder(Node node, Type type) {
    makeElementPlaceholder(node, type.element);
  }

  void makeNullPlaceholder(Node node) {
    placeholders[node] = new NullPlaceholder();
  }

  void makeElementPlaceholder(Node node, Element element) {
    assert(element !== null);
    placeholders[node] = new ElementPlaceholder(element);
  }

  void makePrivateIdentifier(Identifier node) {
    assert(node !== null);
    placeholders[node] =
        new PrivatePlaceholder(currentElement.getLibrary(), node);
  }

  void internalError(String reason, [Node node]) {
    compiler.cancel(reason: reason, node: node);
  }

  visit(Node node) => (node === null) ? null : node.accept(this);

  visitNode(Node node) { node.visitChildren(this); }  // We must go deeper.

  visitClassNode(ClassNode node) {
    internalError('Should never meet ClassNode', node);
  }

  visitSend(Send send) {
    new SendVisitor(this, treeElements).visitSend(send);
    send.visitChildren(this);
  }

  visitSendSet(SendSet send) {
    final element = treeElements[send];
    if (element !== null && element.isInstanceMember()) {
      tryMakePrivateIdentifier(send.selector.asIdentifier());
    }
    send.visitChildren(this);
  }

  visitTypeAnnotation(TypeAnnotation node) {
    final type = compiler.resolveTypeAnnotation(currentElement, node);
    if (type is !InterfaceType) return null;
    var target = node.typeName;
    if (node.typeName is Send) {
      final element = treeElements[node];
      if (element !== null) {
        final send = node.typeName.asSend();
        final hasPrefix = element.lookupConstructor(
          send.receiver.source, send.selector.source) === null;
        if (!hasPrefix) target = send.receiver;
      }
    }
    makeTypePlaceholder(target, type);
    node.visitChildren(this);
  }
}