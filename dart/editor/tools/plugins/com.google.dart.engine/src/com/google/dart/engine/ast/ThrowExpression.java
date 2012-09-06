/*
 * Copyright 2012, the Dart project authors.
 * 
 * Licensed under the Eclipse Public License v1.0 (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 * 
 * http://www.eclipse.org/legal/epl-v10.html
 * 
 * Unless required by applicable law or agreed to in writing, software distributed under the License
 * is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
 * or implied. See the License for the specific language governing permissions and limitations under
 * the License.
 */
package com.google.dart.engine.ast;

import com.google.dart.engine.scanner.Token;

/**
 * Instances of the class {@code ThrowExpression} represent a throw expression.
 * 
 * <pre>
 * throwExpression ::=
 *     'throw' {@link Expression expression}? ';'
 * </pre>
 */
public class ThrowExpression extends Expression {
  /**
   * The token representing the 'throw' keyword.
   */
  private Token keyword;

  /**
   * The expression computing the exception to be thrown, or {@code null} if the current exception
   * is to be re-thrown. (The latter case can only occur if the throw statement is inside a catch
   * clause.)
   */
  private Expression expression;

  /**
   * The semicolon terminating the expression. TODO(brianwilkerson) Remove this field if it is no
   * longer needed. (Waiting for response from Golad.)
   */
  private Token semicolon;

  /**
   * Initialize a newly created throw expression.
   */
  public ThrowExpression() {
  }

  /**
   * Initialize a newly created throw expression.
   * 
   * @param keyword the token representing the 'throw' keyword
   * @param expression the expression computing the exception to be thrown
   * @param semicolon the semicolon terminating the expression
   */
  public ThrowExpression(Token keyword, Expression expression, Token semicolon) {
    this.keyword = keyword;
    this.expression = becomeParentOf(expression);
    this.semicolon = semicolon;
  }

  @Override
  public <R> R accept(ASTVisitor<R> visitor) {
    return visitor.visitThrowExpression(this);
  }

  @Override
  public Token getBeginToken() {
    return keyword;
  }

  @Override
  public Token getEndToken() {
    return semicolon;
  }

  /**
   * Return the expression computing the exception to be thrown, or {@code null} if the current
   * exception is to be re-thrown. (The latter case can only occur if the throw statement is inside
   * a catch clause.)
   * 
   * @return the expression computing the exception to be thrown
   */
  public Expression getExpression() {
    return expression;
  }

  /**
   * Return the token representing the 'throw' keyword.
   * 
   * @return the token representing the 'throw' keyword
   */
  public Token getKeyword() {
    return keyword;
  }

  /**
   * Return the semicolon terminating the expression.
   * 
   * @return the semicolon terminating the expression
   */
  public Token getSemicolon() {
    return semicolon;
  }

  /**
   * Set the expression computing the exception to be thrown to the given expression.
   * 
   * @param expression the expression computing the exception to be thrown
   */
  public void setExpression(Expression expression) {
    this.expression = becomeParentOf(expression);
  }

  /**
   * Set the token representing the 'throw' keyword to the given token.
   * 
   * @param keyword the token representing the 'throw' keyword
   */
  public void setKeyword(Token keyword) {
    this.keyword = keyword;
  }

  /**
   * Set the semicolon terminating the expression to the given token.
   * 
   * @param semicolon the semicolon terminating the expression
   */
  public void setSemicolon(Token semicolon) {
    this.semicolon = semicolon;
  }

  @Override
  public void visitChildren(ASTVisitor<?> visitor) {
    safelyVisitChild(expression, visitor);
  }
}
