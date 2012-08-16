// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Returns null if no need to rename a node.
typedef String Renamer(Node node);

class Unparser implements Visitor {
  Renamer rename;
  StringBuffer sb;

  Unparser() {
    // TODO(smok): Move this to initializer once dart2js stops complaining
    // about closures in initializers.
    rename = (Node node) => null;
  }
  Unparser.withRenamer(this.rename);

  String unparse(Node node) {
    sb = new StringBuffer();
    visit(node);
    return sb.toString();
  }

  void add(SourceString string) {
    string.printOn(sb);
  }

  void addToken(Token token) {
    if (token === null) return;
    add(token.value);
    if (token.kind === KEYWORD_TOKEN || token.kind === IDENTIFIER_TOKEN) {
      sb.add(' ');
    }
  }

  visit(Node node) {
    if (node === null) return;
    String renamed = rename(node);
    if (renamed !== null) {
      sb.add(renamed);
    } else {
      // Fallback.
      node.accept(this);
    }
  }

  visitBlock(Block node) {
    visit(node.statements);
  }

  visitCascade(Cascade node) {
    visit(node.expression);
  }

  visitCascadeReceiver(CascadeReceiver node) {
    visit(node.expression);
  }

  visitClassNode(ClassNode node) {
    addToken(node.beginToken);
    visit(node.name);
    sb.add(' ');
    if (node.extendsKeyword !== null) {
      addToken(node.extendsKeyword);
      visit(node.superclass);
      sb.add(' ');
    }
    visit(node.interfaces);
    if (node.defaultClause !== null) {
      visit(node.defaultClause);
      sb.add(' ');
    }
    sb.add('{\n');
    sb.add('}\n');
  }

  visitConditional(Conditional node) {
    visit(node.condition);
    add(node.questionToken.value);
    visit(node.thenExpression);
    add(node.colonToken.value);
    visit(node.elseExpression);
  }

  visitExpressionStatement(ExpressionStatement node) {
    visit(node.expression);
    add(node.endToken.value);
  }

  visitFor(For node) {
    add(node.forToken.value);
    sb.add('(');
    visit(node.initializer);
    if (node.initializer is !Statement) sb.add(';');
    visit(node.conditionStatement);
    visit(node.update);
    sb.add(')');
    visit(node.body);
  }

  visitFunctionDeclaration(FunctionDeclaration node) {
    visit(node.function);
  }

  visitFunctionExpression(FunctionExpression node) {
    // Check length to not print unnecessary whitespace.
    if (node.modifiers !== null && node.modifiers.nodes.length() > 0) {
      visit(node.modifiers);
      sb.add(' ');
    }
    if (node.returnType !== null) {
      visit(node.returnType);
      sb.add(' ');
    }
    if (node.getOrSet !== null) {
      add(node.getOrSet.value);
      sb.add(' ');
    }
    // TODO(antonm): that's a workaround as currently FunctionExpression
    // names are modelled with Send and it emits operator[] as only
    // operator, without [] which are expected to be emitted with
    // arguments.
    if (node.name is Send) {
      Send send = node.name;
      assert(send is !SendSet);
      if (!send.isOperator) {
        // Looks like a factory method.
        visit(send.receiver);
        sb.add('.');
      } else {
        visit(send.receiver);
        if (send.selector.asIdentifier().token.kind === KEYWORD_TOKEN) {
          sb.add(' ');
        }
      }
      visit(send.selector);
    } else {
      visit(node.name);
    }
    visit(node.parameters);
    visit(node.initializers);
    visit(node.body);
  }

  visitIdentifier(Identifier node) {
    add(node.token.value);
  }

  visitIf(If node) {
    add(node.ifToken.value);
    visit(node.condition);
    visit(node.thenPart);
    if (node.hasElsePart) {
      addToken(node.elseToken);
      visit(node.elsePart);
    }
  }

  visitLiteralBool(LiteralBool node) {
    add(node.token.value);
  }

  visitLiteralDouble(LiteralDouble node) {
    add(node.token.value);
    // -Lit is represented as a send.
    if (node.token.kind == PLUS_TOKEN) add(node.token.next.value);
  }

  visitLiteralInt(LiteralInt node) {
    add(node.token.value);
    // -Lit is represented as a send.
    if (node.token.kind == PLUS_TOKEN) add(node.token.next.value);
  }

  visitLiteralString(LiteralString node) {
    add(node.token.value);
  }

  visitStringJuxtaposition(StringJuxtaposition node) {
    visit(node.first);
    sb.add(" ");
    visit(node.second);
  }

  visitLiteralNull(LiteralNull node) {
    add(node.token.value);
  }

  visitNewExpression(NewExpression node) {
    addToken(node.newToken);
    visit(node.send);
  }

  visitLiteralList(LiteralList node) {
    addToken(node.constKeyword);
    if (node.type !== null) {
      sb.add('<');
      visit(node.type);
      sb.add('>');
    }
    visit(node.elements);
  }

  visitModifiers(Modifiers node) => node.visitChildren(this);

  /**
   * Unparses given NodeList starting from specific node.
   */
  unparseNodeListFrom(NodeList node, Link<Node> from) {
    if (from.isEmpty()) return;
    String delimiter = (node.delimiter === null) ? " " : "${node.delimiter}";
    visit(from.head);
    for (Link link = from.tail; !link.isEmpty(); link = link.tail) {
      sb.add(delimiter);
      visit(link.head);
    }
  }

  visitNodeList(NodeList node) {
    if (node.beginToken !== null) addToken(node.beginToken);
    if (node.nodes !== null) {
      unparseNodeListFrom(node, node.nodes);
    }
    if (node.endToken !== null) add(node.endToken.value);
  }

  visitOperator(Operator node) {
    visitIdentifier(node);
  }

  visitReturn(Return node) {
    add(node.beginToken.value);
    if (node.hasExpression) {
      sb.add(' ');
      visit(node.expression);
    }
    if (node.endToken !== null) add(node.endToken.value);
  }

  unparseSendReceiver(Send node, [bool spacesNeeded=false]) {
    // TODO(smok): Remove ugly hack for library preferences.
    // Check that renamer does not want to omit receiver at all,
    // in that case we don't need spaces or dot.
    if (node.receiver !== null && rename(node.receiver) != '') {
      visit(node.receiver);
      CascadeReceiver asCascadeReceiver = node.receiver.asCascadeReceiver();
      if (asCascadeReceiver !== null) {
        add(asCascadeReceiver.cascadeOperator.value);
      } else if (node.selector.asOperator() === null) {
        sb.add('.');
      } else if (spacesNeeded) {
        sb.add(' ');
      }
    }
  }

  visitSend(Send node) {
    Operator op = node.selector.asOperator();
    bool spacesNeeded = op !== null &&
        (op.source.stringValue === 'is' || op.source.stringValue == 'as');

    if (node.isPrefix) visit(node.selector);
    unparseSendReceiver(node, spacesNeeded: spacesNeeded);
    if (!node.isPrefix && !node.isIndex) visit(node.selector);
    if (spacesNeeded) sb.add(' ');
    visit(node.argumentsNode);
  }

  visitSendSet(SendSet node) {
    if (node.isPrefix) {
      sb.add(' ');
      visit(node.assignmentOperator);
    }
    unparseSendReceiver(node);
    if (node.isIndex) {
      sb.add('[');
      visit(node.arguments.head);
      sb.add(']');
      if (!node.isPrefix) visit(node.assignmentOperator);
      unparseNodeListFrom(node.argumentsNode, node.argumentsNode.nodes.tail);
    } else {
      visit(node.selector);
      if (!node.isPrefix) {
        visit(node.assignmentOperator);
        if (node.assignmentOperator.source.slowToString() != '=') sb.add(' ');
      }
      visit(node.argumentsNode);
    }
  }

  visitThrow(Throw node) {
    add(node.throwToken.value);
    if (node.expression !== null) {
      sb.add(' ');
      visit(node.expression);
    }
    node.endToken.value.printOn(sb);
  }

  visitTypeAnnotation(TypeAnnotation node) {
    visit(node.typeName);
    visit(node.typeArguments);
  }

  visitTypeVariable(TypeVariable node) {
    visit(node.name);
    if (node.bound !== null) {
      sb.add(' extends ');
      visit(node.bound);
    }
  }

  visitVariableDefinitions(VariableDefinitions node) {
    visit(node.modifiers);
    if (node.modifiers.nodes.length() > 0) {
      sb.add(' ');
    }
    if (node.type !== null) {
      visit(node.type);
      sb.add(' ');
    }
    visit(node.definitions);
    if (node.endToken.value == const SourceString(';')) {
      add(node.endToken.value);
    }
  }

  visitDoWhile(DoWhile node) {
    addToken(node.doKeyword);
    visit(node.body);
    sb.add(' ');
    addToken(node.whileKeyword);
    visit(node.condition);
    sb.add(node.endToken.value);
  }

  visitWhile(While node) {
    addToken(node.whileKeyword);
    visit(node.condition);
    sb.add(' ');
    visit(node.body);
  }

  visitParenthesizedExpression(ParenthesizedExpression node) {
    add(node.getBeginToken().value);
    visit(node.expression);
    add(node.getEndToken().value);
  }

  visitStringInterpolation(StringInterpolation node) {
    visit(node.string);
    visit(node.parts);
  }

  visitStringInterpolationPart(StringInterpolationPart node) {
    sb.add('\${'); // TODO(ahe): Preserve the real tokens.
    visit(node.expression);
    sb.add('}');
    visit(node.string);
  }

  visitEmptyStatement(EmptyStatement node) {
    add(node.semicolonToken.value);
  }

  visitGotoStatement(GotoStatement node) {
    add(node.keywordToken.value);
    if (node.target !== null) {
      sb.add(' ');
      visit(node.target);
    }
    add(node.semicolonToken.value);
  }

  visitBreakStatement(BreakStatement node) {
    visitGotoStatement(node);
  }

  visitContinueStatement(ContinueStatement node) {
    visitGotoStatement(node);
  }

  visitForIn(ForIn node) {
    add(node.forToken.value);
    sb.add(' (');
    visit(node.declaredIdentifier);
    sb.add(' ');
    addToken(node.inToken);
    visit(node.expression);
    sb.add(') ');
    visit(node.body);
  }

  visitLabel(Label node) {
    visit(node.identifier);
    add(node.colonToken.value);
   }

  visitLabeledStatement(LabeledStatement node) {
    visit(node.labels);
    visit(node.statement);
  }

  visitLiteralMap(LiteralMap node) {
    if (node.constKeyword !== null) {
      add(node.constKeyword.value);
    }
    if (node.typeArguments !== null) visit(node.typeArguments);
    visit(node.entries);
  }

  visitLiteralMapEntry(LiteralMapEntry node) {
    visit(node.key);
    add(node.colonToken.value);
    sb.add(' ');
    visit(node.value);
  }

  visitNamedArgument(NamedArgument node) {
    visit(node.name);
    add(node.colonToken.value);
    sb.add(' ');
    visit(node.expression);
  }

  visitSwitchStatement(SwitchStatement node) {
    addToken(node.switchKeyword);
    visit(node.parenthesizedExpression);
    sb.add(' ');
    visit(node.cases);
  }

  visitSwitchCase(SwitchCase node) {
    visit(node.labelsAndCases);
    if (node.isDefaultCase) {
      sb.add('default:');
    }
    visit(node.statements);
  }

  visitScriptTag(ScriptTag node) {
    add(node.beginToken.value);
    visit(node.tag);
    sb.add('(');
    visit(node.argument);
    if (node.prefixIdentifier !== null) {
      visit(node.prefixIdentifier);
      sb.add(': ');
      visit(node.prefix);
    }
    sb.add(')');
    add(node.endToken.value);
  }

  visitTryStatement(TryStatement node) {
    addToken(node.tryKeyword);
    visit(node.tryBlock);
    visit(node.catchBlocks);
    if (node.finallyKeyword !== null) {
      sb.add(' ');
      addToken(node.finallyKeyword);
      visit(node.finallyBlock);
    }
  }

  visitCaseMatch(CaseMatch node) {
    add(node.caseKeyword.value);
    sb.add(" ");
    visit(node.expression);
    add(node.colonToken.value);
  }

  visitCatchBlock(CatchBlock node) {
    addToken(node.onKeyword);
    visit(node.type);
    sb.add(' ');
    addToken(node.catchKeyword);
    visit(node.formals);
    sb.add(' ');
    visit(node.block);
  }

  visitTypedef(Typedef node) {
    addToken(node.typedefKeyword);
    if (node.returnType !== null) {
      visit(node.returnType);
      sb.add(' ');
    }
    visit(node.name);
    if (node.typeParameters !== null) {
      visit(node.typeParameters);
    }
    visit(node.formals);
    add(node.endToken.value);
  }
}
