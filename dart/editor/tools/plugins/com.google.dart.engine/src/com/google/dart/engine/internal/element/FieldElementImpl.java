/*
 * Copyright (c) 2012, the Dart project authors.
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
package com.google.dart.engine.internal.element;

import com.google.dart.engine.ast.Identifier;
import com.google.dart.engine.element.ElementKind;
import com.google.dart.engine.element.FieldElement;
import com.google.dart.engine.element.PropertyAccessorElement;

/**
 * Instances of the class {@code FieldElementImpl} implement a {@code FieldElement}.
 */
public class FieldElementImpl extends VariableElementImpl implements FieldElement {
  /**
   * The getter associated with this field.
   */
  private PropertyAccessorElement getter;

  /**
   * The setter associated with this field, or {@code null} if the field is effectively
   * {@code final} and therefore does not have a setter associated with it.
   */
  private PropertyAccessorElement setter;

  /**
   * An empty array of field elements.
   */
  public static final FieldElement[] EMPTY_ARRAY = new FieldElement[0];

  /**
   * Initialize a newly created field element to have the given name.
   * 
   * @param name the name of this element
   */
  public FieldElementImpl(Identifier name) {
    super(name);
  }

  /**
   * Initialize a newly created synthetic field element to have the given name.
   * 
   * @param name the name of this element
   */
  public FieldElementImpl(String name) {
    super(name, -1);
    setSynthetic(true);
  }

  @Override
  public PropertyAccessorElement getGetter() {
    return getter;
  }

  @Override
  public ElementKind getKind() {
    return ElementKind.FIELD;
  }

  @Override
  public PropertyAccessorElement getSetter() {
    return setter;
  }

  @Override
  public boolean isStatic() {
    return hasModifier(Modifier.STATIC);
  }

  /**
   * Set the getter associated with this field to the given accessor.
   * 
   * @param getter the getter associated with this field
   */
  public void setGetter(PropertyAccessorElement getter) {
    this.getter = getter;
  }

  /**
   * Set the setter associated with this field to the given accessor.
   * 
   * @param setter the setter associated with this field
   */
  public void setSetter(PropertyAccessorElement setter) {
    this.setter = setter;
  }

  /**
   * Set whether this field is static to correspond to the given value.
   * 
   * @param isStatic {@code true} if the field is static
   */
  public void setStatic(boolean isStatic) {
    setModifier(Modifier.STATIC, isStatic);
  }
}
