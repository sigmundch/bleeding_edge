// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class Printer implements NodeVisitor {
  final bool shouldCompressOutput;
  leg.Compiler compiler;
  var positionElement;
  leg.CodeBuffer outBuffer;
  int indentLevel = 0;
  bool inForInit = false;
  bool atStatementBegin = false;
  final DanglingElseVisitor danglingElseVisitor;

  Printer(leg.Compiler compiler, this.positionElement)
      : shouldCompressOutput = compiler.enableMinification,
        this.compiler = compiler,
        outBuffer = new leg.CodeBuffer(),
        danglingElseVisitor = new DanglingElseVisitor(compiler);

  void spaceOut() {
    if (!shouldCompressOutput) out(" ");
  }
  void lineOut() {
    if (!shouldCompressOutput) out("\n");
  }

  String lastAddedString = null;
  int get lastCharCode {
    if (lastAddedString == null) return 0;
    assert(lastAddedString.length != "");
    return lastAddedString.charCodeAt(lastAddedString.length - 1);
  }

  void out(String str) {
    if (str != "") {
      outBuffer.add(str);
      lastAddedString = str;
    }
  }

  void outLn(String str) {
    out(str);
    lineOut();
  }

  void outIndent(String str) { indent(); out(str); }
  void outIndentLn(String str) { indent(); outLn(str); }
  void indent() {
    if (!shouldCompressOutput) {
      for (int i = 0; i < indentLevel; i++) out("  ");
    }
  }

  void recordSourcePosition(var position) {
    if (position != null) {
      outBuffer.setSourceLocation(positionElement, position);
    }
  }

  visit(Node node) {
    recordSourcePosition(node.sourcePosition);
    node.accept(this);
    recordSourcePosition(node.endSourcePosition);
  }

  visitCommaSeparated(List<Node> nodes, int hasRequiredType,
                      [bool newInForInit, bool newAtStatementBegin]) {
    for (int i = 0; i < nodes.length; i++) {
      if (i != 0) {
        atStatementBegin = false;
        out(",");
        spaceOut();
      }
      visitNestedExpression(nodes[i], hasRequiredType,
                            newInForInit, newAtStatementBegin);
    }
  }

  visitAll(List<Node> nodes) {
    nodes.forEach(visit);
  }

  visitProgram(Program program) {
    visitAll(program.body);
  }

  bool blockBody(Node body, [bool needsSeparation, bool needsNewline]) {
    if (body is Block) {
      spaceOut();
      blockOut(body, false, needsNewline);
      return true;
    }
    if (shouldCompressOutput && needsSeparation) {
      // If [shouldCompressOutput] is false, then the 'lineOut' will insert
      // the separation.
      out(" ");
    } else {
      lineOut();
    }
    indentLevel++;
    visit(body);
    indentLevel--;
    return false;
  }

  void blockOutWithoutBraces(Node node) {
    if (node is Block) {
      node.statements.forEach(blockOutWithoutBraces);
    } else {
      visit(node);
    }
  }

  void blockOut(Block node, bool shouldIndent, bool needsNewline) {
    if (shouldIndent) indent();
    out("{");
    lineOut();
    indentLevel++;
    node.statements.forEach(blockOutWithoutBraces);
    indentLevel--;
    indent();
    out("}");
    if (needsNewline) lineOut();
  }

  visitBlock(Block block) {
    blockOut(block, true, true);
  }

  visitExpressionStatement(ExpressionStatement expressionStatement) {
    indent();
    visitNestedExpression(expressionStatement.expression, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: true);
    outLn(";");
  }

  visitEmptyStatement(EmptyStatement nop) {
    outIndentLn(";");
  }

  void ifOut(If node, bool shouldIndent) {
    Node then = node.then;
    Node elsePart = node.otherwise;
    bool hasElse = node.hasElse;

    // Handle dangling elses.
    if (hasElse) {
      bool needsBraces = node.then.accept(danglingElseVisitor);
      if (needsBraces) {
        then = new Block(<Statement>[then]);
      }
    }
    if (shouldIndent) indent();
    out("if");
    spaceOut();
    out("(");
    visitNestedExpression(node.condition, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: false);
    out(")");
    bool thenWasBlock =
        blockBody(then, needsSeparation: false, needsNewline: !hasElse);
    if (hasElse) {
      if (thenWasBlock) {
        spaceOut();
      } else {
        indent();
      }
      out("else");
      if (elsePart is If) {
        out(" ");
        ifOut(elsePart, false);
      } else {
        blockBody(elsePart, needsSeparation: true, needsNewline: true);
      }
    }
  }

  visitIf(If node) {
    ifOut(node, true);
  }

  visitFor(For loop) {
    outIndent("for");
    spaceOut();
    out("(");
    if (loop.init !== null) {
      visitNestedExpression(loop.init, EXPRESSION,
                            newInForInit: true, newAtStatementBegin: false);
    }
    out(";");
    if (loop.condition !== null) {
      spaceOut();
      visitNestedExpression(loop.condition, EXPRESSION,
                            newInForInit: false, newAtStatementBegin: false);
    }
    out(";");
    if (loop.update !== null) {
      spaceOut();
      visitNestedExpression(loop.update, EXPRESSION,
                            newInForInit: false, newAtStatementBegin: false);
    }
    out(")");
    blockBody(loop.body, needsSeparation: false, needsNewline: true);
  }

  visitForIn(ForIn loop) {
    outIndent("for");
    spaceOut();
    out("(");
    visitNestedExpression(loop.leftHandSide, EXPRESSION,
                          newInForInit: true, newAtStatementBegin: false);
    out(" in ");
    visitNestedExpression(loop.object, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: false);
    out(")");
    blockBody(loop.body, needsSeparation: false, needsNewline: true);
  }

  visitWhile(While loop) {
    outIndent("while");
    spaceOut();
    out("(");
    visitNestedExpression(loop.condition, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: false);
    out(")");
    blockBody(loop.body, needsSeparation: false, needsNewline: true);
  }

  visitDo(Do loop) {
    outIndent("do");
    if (blockBody(loop.body, needsSeparation: true, needsNewline: false)) {
      spaceOut();
    } else {
      indent();
    }
    out("while");
    spaceOut();
    out("(");
    visitNestedExpression(loop.condition, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: false);
    outLn(");");
  }

  visitContinue(Continue node) {
    if (node.targetLabel == null) {
      outIndentLn("continue;");
    } else {
      outIndentLn("continue ${node.targetLabel};");
    }
  }

  visitBreak(Break node) {
    if (node.targetLabel == null) {
      outIndentLn("break;");
    } else {
      outIndentLn("break ${node.targetLabel};");
    }
  }

  visitReturn(Return node) {
    if (node.value == null) {
      outIndentLn("return;");
    } else {
      outIndent("return ");
      visitNestedExpression(node.value, EXPRESSION,
                            newInForInit: false, newAtStatementBegin: false);
      outLn(";");
    }
  }

  visitThrow(Throw node) {
    outIndent("throw ");
    visitNestedExpression(node.expression, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: false);
    outLn(";");
  }

  visitTry(Try node) {
    outIndent("try");
    blockBody(node.body, needsSeparation: true, needsNewline: false);
    if (node.catchPart !== null) {
      visit(node.catchPart);
    }
    if (node.finallyPart !== null) {
      spaceOut();
      out("finally");
      blockBody(node.finallyPart, needsSeparation: true, needsNewline: true);
    } else {
      lineOut();
    }
  }

  visitCatch(Catch node) {
    spaceOut();
    out("catch");
    spaceOut();
    out("(");
    visitNestedExpression(node.declaration, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: false);
    out(")");
    blockBody(node.body, needsSeparation: false, needsNewline: true);
  }

  visitSwitch(Switch node) {
    outIndent("switch");
    spaceOut();
    out("(");
    visitNestedExpression(node.key, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: false);
    out(")");
    spaceOut();
    outLn("{");
    indentLevel++;
    visitAll(node.cases);
    indentLevel--;
    outIndentLn("}");
  }

  visitCase(Case node) {
    outIndent("case ");
    visitNestedExpression(node.expression, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: false);
    outLn(":");
    if (!node.body.statements.isEmpty()) {
      indentLevel++;
      blockOutWithoutBraces(node.body);
      indentLevel--;
    }
  }

  visitDefault(Default node) {
    outIndentLn("default:");
    if (!node.body.statements.isEmpty()) {
      indentLevel++;
      blockOutWithoutBraces(node.body);
      indentLevel--;
    }
  }

  visitLabeledStatement(LabeledStatement node) {
    outIndent("${node.label}:");
    blockBody(node.body, needsSeparation: false, needsNewline: true);
  }

  void functionOut(Fun fun, Node name) {
    out("function");
    if (name != null) {
      out(" ");
      // Name must be a [Decl]. Therefore only test for primary expressions.
      visitNestedExpression(name, PRIMARY,
                            newInForInit: false, newAtStatementBegin: false);
    }
    out("(");
    if (fun.params != null) {
      visitCommaSeparated(fun.params, PRIMARY,
                          newInForInit: false, newAtStatementBegin: false);
    }
    out(")");
    blockBody(fun.body, needsSeparation: false, needsNewline: false);
  }

  visitFunctionDeclaration(FunctionDeclaration declaration) {
    indent();
    functionOut(declaration.function, declaration.name);
    lineOut();
  }

  visitNestedExpression(Expression node, int requiredPrecedence,
                        [bool newInForInit, bool newAtStatementBegin]) {
    bool needsParentheses =
        // a - (b + c).
        (requiredPrecedence != EXPRESSION &&
         node.precedenceLevel < requiredPrecedence) ||
        // for (a = (x in o); ... ; ... ) { ... }
        (newInForInit && node is Binary && (node as Binary).op == "in") ||
        // (function() { ... })().
        // ({a: 2, b: 3}.toString()).
        (newAtStatementBegin && (node is NamedFunction ||
                                 node is Fun ||
                                 node is ObjectInitializer));
    if (needsParentheses) {
      inForInit = false;
      atStatementBegin = false;
      out("(");
      visit(node);
      out(")");
    } else {
      inForInit = newInForInit;
      atStatementBegin = newAtStatementBegin;
      visit(node);
    }
  }

  visitVariableDeclarationList(VariableDeclarationList list) {
    out("var ");
    visitCommaSeparated(list.declarations, ASSIGNMENT,
                        newInForInit: inForInit, newAtStatementBegin: false);
  }

  visitSequence(Sequence sequence) {
    // Note that we only require that the entries are expressions and not
    // assignments. This means that nested sequences are not put into
    // parenthesis.
    visitCommaSeparated(sequence.expressions, EXPRESSION,
                        newInForInit: false,
                        newAtStatementBegin: atStatementBegin);
  }

  visitAssignment(Assignment assignment) {
    visitNestedExpression(assignment.leftHandSide, LEFT_HAND_SIDE,
                          newInForInit: inForInit,
                          newAtStatementBegin: atStatementBegin);
    if (assignment.value !== null) {
      spaceOut();
      String op = assignment.op;
      if (op != null) out(op);
      out("=");
      spaceOut();
      visitNestedExpression(assignment.value, ASSIGNMENT,
                            newInForInit: inForInit,
                            newAtStatementBegin: false);
    }
  }

  visitVariableInitialization(VariableInitialization initialization) {
    visitAssignment(initialization);
  }

  visitConditional(Conditional cond) {
    visitNestedExpression(cond.condition, LOGICAL_OR,
                          newInForInit: inForInit,
                          newAtStatementBegin: atStatementBegin);
    spaceOut();
    out("?");
    spaceOut();
    // The then part is allowed to have an 'in'.
    visitNestedExpression(cond.then, ASSIGNMENT,
                          newInForInit: false, newAtStatementBegin: false);
    spaceOut();
    out(":");
    spaceOut();
    visitNestedExpression(cond.otherwise, ASSIGNMENT,
                          newInForInit: inForInit, newAtStatementBegin: false);
  }

  visitNew(New node) {
    out("new ");
    visitNestedExpression(node.target, CALL,
                          newInForInit: inForInit, newAtStatementBegin: false);
    out("(");
    visitCommaSeparated(node.arguments, ASSIGNMENT,
                        newInForInit: false, newAtStatementBegin: false);
    out(")");
  }

  visitCall(Call call) {
    visitNestedExpression(call.target, LEFT_HAND_SIDE,
                          newInForInit: inForInit,
                          newAtStatementBegin: atStatementBegin);
    out("(");
    visitCommaSeparated(call.arguments, ASSIGNMENT,
                        newInForInit: false, newAtStatementBegin: false);
    out(")");
  }

  visitBinary(Binary binary) {
    Expression left = binary.left;
    Expression right = binary.right;
    String op = binary.op;
    int leftPrecedenceRequirement;
    int rightPrecedenceRequirement;
    switch (op) {
      case "||":
        leftPrecedenceRequirement = LOGICAL_OR;
        // x || (y || z) <=> (x || y) || z.
        rightPrecedenceRequirement = LOGICAL_OR;
        break;
      case "&&":
        leftPrecedenceRequirement = LOGICAL_AND;
        // x && (y && z) <=> (x && y) && z.
        rightPrecedenceRequirement = LOGICAL_AND;
        break;
      case "|":
        leftPrecedenceRequirement = BIT_OR;
        // x | (y | z) <=> (x | y) | z.
        rightPrecedenceRequirement = BIT_OR;
        break;
      case "^":
        leftPrecedenceRequirement = BIT_XOR;
        // x ^ (y ^ z) <=> (x ^ y) ^ z.
        rightPrecedenceRequirement = BIT_XOR;
        break;
      case "&":
        leftPrecedenceRequirement = BIT_AND;
        // x & (y & z) <=> (x & y) & z.
        rightPrecedenceRequirement = BIT_AND;
        break;
      case "==":
      case "!=":
      case "===":
      case "!==":
        leftPrecedenceRequirement = EQUALITY;
        rightPrecedenceRequirement = RELATIONAL;
        break;
      case "<":
      case ">":
      case "<=":
      case ">=":
      case "instanceof":
      case "in":
        leftPrecedenceRequirement = RELATIONAL;
        rightPrecedenceRequirement = SHIFT;
        break;
      case ">>":
      case "<<":
      case ">>>":
        leftPrecedenceRequirement = SHIFT;
        rightPrecedenceRequirement = ADDITIVE;
        break;
      case "+":
      case "-":
        leftPrecedenceRequirement = ADDITIVE;
        // We cannot remove parenthesis for "+" because
        //   x + (y + z) <!=> (x + y) + z:
        // Example:
        //   "a" + (1 + 2) => "a3";
        //   ("a" + 1) + 2 => "a12";
        rightPrecedenceRequirement = MULTIPLICATIVE;
        break;
      case "*":
      case "/":
      case "%":
        leftPrecedenceRequirement = MULTIPLICATIVE;
        // We cannot remove parenthesis for "*" because of precision issues.
        rightPrecedenceRequirement = UNARY;
        break;
      default:
        compiler.internalError("Forgot operator: $op");
    }

    visitNestedExpression(left, leftPrecedenceRequirement,
                          newInForInit: inForInit,
                          newAtStatementBegin: atStatementBegin);

    if (op == "in" || op == "instanceof") {
      // There are cases where the space is not required but without further
      // analysis we cannot know.
      out(" ");
      out(op);
      out(" ");
    } else {
      spaceOut();
      out(op);
      spaceOut();
    }
    visitNestedExpression(right, rightPrecedenceRequirement,
                          newInForInit: inForInit,
                          newAtStatementBegin: false);
  }

  visitPrefix(Prefix unary) {
    String op = unary.op;
    switch (op) {
      case "delete":
      case "void":
      case "typeof":
        // There are cases where the space is not required but without further
        // analysis we cannot know.
        out(op);
        out(" ");
        break;
      case "+":
      case "++":
        if (lastCharCode == charCodes.$PLUS) out(" ");
        out(op);
        break;
      case "-":
      case "--":
        if (lastCharCode == charCodes.$MINUS) out(" ");
        out(op);
        break;
      default:
        out(op);
    }
    visitNestedExpression(unary.argument, UNARY,
                          newInForInit: inForInit, newAtStatementBegin: false);
  }

  visitPostfix(Postfix postfix) {
    visitNestedExpression(postfix.argument, LEFT_HAND_SIDE,
                          newInForInit: inForInit,
                          newAtStatementBegin: atStatementBegin);
    out(postfix.op);
  }

  visitVariableUse(VariableUse ref) {
    out(ref.name);
  }

  visitThis(This node) {
    out("this");
  }

  visitVariableDeclaration(VariableDeclaration decl) {
    out(decl.name);
  }

  visitParameter(Parameter param) {
    out(param.name);
  }

  bool isDigit(int charCode) {
    return charCodes.$0 <= charCode && charCode <= charCodes.$9;
  }

  bool isValidJavaScriptId(String field) {
    if (field.length < 3) return false;
    // Ignore the leading and trailing string-delimiter.
    for (int i = 1; i < field.length - 1; i++) {
      // TODO(floitsch): allow more characters.
      int charCode = field.charCodeAt(i);
      if (!(charCodes.$a <= charCode && charCode <= charCodes.$z ||
            charCodes.$A <= charCode && charCode <= charCodes.$Z ||
            charCode == charCodes.$$ ||
            charCode == charCodes.$_ ||
            i != 1 && isDigit(charCode))) {
        return false;
      }
    }
    // TODO(floitsch): normally we should also check that the field is not
    // a reserved word.
    return true;
  }

  visitAccess(PropertyAccess access) {
    visitNestedExpression(access.receiver, CALL,
                          newInForInit: inForInit,
                          newAtStatementBegin: atStatementBegin);
    Node selector = access.selector;
    if (selector is LiteralString) {
      LiteralString selectorString = selector;
      String fieldWithQuotes = selectorString.value;
      if (isValidJavaScriptId(fieldWithQuotes)) {
        if (access.receiver is LiteralNumber) out(" ");
        out(".");
        out(fieldWithQuotes.substring(1, fieldWithQuotes.length - 1));
        return;
      }
    }
    out("[");
    visitNestedExpression(selector, EXPRESSION,
                          newInForInit: false, newAtStatementBegin: false);
    out("]");
  }

  visitNamedFunction(NamedFunction namedFunction) {
    functionOut(namedFunction.function, namedFunction.name);
  }

  visitFun(Fun fun) {
    functionOut(fun, null);
  }

  visitLiteralBool(LiteralBool node) {
    out(node.value ? "true" : "false");
  }

  visitLiteralString(LiteralString node) {
    out(node.value);
  }

  visitLiteralNumber(LiteralNumber node) {
    int charCode = node.value.charCodeAt(0);
    if (charCode == charCodes.$MINUS && lastCharCode == charCodes.$MINUS) {
      out(" ");
    }
    out(node.value);
  }

  visitLiteralNull(LiteralNull node) {
    out("null");
  }

  visitArrayInitializer(ArrayInitializer node) {
    out("[");
    List<ArrayElement> elements = node.elements;
    int elementIndex = 0;
    for (int i = 0; i < node.length; i++) {
      if (elementIndex < elements.length &&
          elements[elementIndex].index == i) {
        visitNestedExpression(elements[elementIndex].value, ASSIGNMENT,
                              newInForInit: false, newAtStatementBegin: false);
        elementIndex++;
        // We can avoid a trailing "," if there was an element just before. So
        // `[1]` and `[1,]` are the same, but `[,]` and `[]` are not.
        if (i != node.length - 1) {
          out(",");
          spaceOut();
        }
      } else {
        out(",");
      }
    }
    out("]");
  }

  visitArrayElement(ArrayElement node) {
    throw "Unreachable";
  }

  visitObjectInitializer(ObjectInitializer node) {
    out("{");
    List<Property> properties = node.properties;
    for (int i = 0; i < properties.length; i++) {
      if (i != 0) {
        out(",");
        spaceOut();
      }
      visitProperty(properties[i]);
    }
    out("}");
  }

  visitProperty(Property node) {
    if (node.name is LiteralString) {
      LiteralString nameString = node.name;
      String name = nameString.value;
      if (isValidJavaScriptId(name)) {
        out(name.substring(1, name.length - 1));
      } else {
        out(name);
      }
    } else {
      assert(node.name is LiteralNumber);
      LiteralNumber nameNumber = node.name;
      out(nameNumber.value);
    }
    out(":");
    spaceOut();
    visitNestedExpression(node.value, ASSIGNMENT,
                          newInForInit: false, newAtStatementBegin: false);
  }

  visitRegExpLiteral(RegExpLiteral node) {
    out(node.pattern);
  }

  visitLiteralExpression(LiteralExpression node) {
    String template = node.template;
    List<Expression> inputs = node.inputs;

    List<String> parts = template.split('#');
    if (parts.length != inputs.length + 1) {
      compiler.internalError('Wrong number of arguments for JS: $template');
    }
    // Code that uses JS must take care of operator precedences, and
    // put parenthesis if needed.
    out(parts[0]);
    for (int i = 0; i < inputs.length; i++) {
      visit(inputs[i]);
      out(parts[i + 1]);
    }
  }

  visitLiteralStatement(LiteralStatement node) {
    outLn(node.code);
  }
}

/**
 * Returns true, if the given node must be wrapped into braces when used
 * as then-statement in an [If] that has an else branch.
 */
class DanglingElseVisitor extends BaseVisitor<bool> {
  leg.Compiler compiler;

  DanglingElseVisitor(this.compiler);

  bool visitProgram(Program node) => false;

  bool visitNode(Statement node) {
    compiler.internalError("Forgot node: $node");
  }

  bool visitBlock(Block node) => false;
  bool visitExpressionStatement(ExpressionStatement node) => false;
  bool visitEmptyStatement(EmptyStatement node) => false;
  bool visitIf(If node) {
    if (!node.hasElse) return true;
    return node.otherwise.accept(this);
  }
  bool visitFor(For node) => node.body.accept(this);
  bool visitForIn(ForIn node) => node.body.accept(this);
  bool visitWhile(While node) => node.body.accept(this);
  bool visitDo(Do node) => false;
  bool visitContinue(Continue node) => false;
  bool visitBreak(Break node) => false;
  bool visitReturn(Return node) => false;
  bool visitThrow(Throw node) => false;
  bool visitTry(Try node) {
    if (node.finallyPart != null) {
      return node.finallyPart.accept(this);
    } else {
      return node.catchPart.accept(this);
    }
  }
  bool visitCatch(Catch node) => node.body.accept(this);
  bool visitSwitch(Switch node) => false;
  bool visitCase(Case node) => false;
  bool visitDefault(Default node) => false;
  bool visitFunctionDeclaration(FunctionDeclaration node) => false;
  bool visitLabeledStatement(LabeledStatement node)
      => node.body.accept(this);
  bool visitLiteralStatement(LiteralStatement node) => true;

  bool visitExpression(Expression node) => false;
}


leg.CodeBuffer prettyPrint(Node node,
                           leg.Compiler compiler,
                           Dynamic positionElement) {
  Printer printer = new Printer(compiler, positionElement);
  printer.visit(node);
  return printer.outBuffer;
}
