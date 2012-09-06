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

package com.google.dart.tools.debug.core.server;

import com.google.dart.tools.debug.core.server.ServerDebugVariable.IValueRetriever;

import org.eclipse.debug.core.DebugException;
import org.eclipse.debug.core.model.IDebugTarget;
import org.eclipse.debug.core.model.IValue;
import org.eclipse.debug.core.model.IVariable;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;

/**
 * An IValue implementation for VM debugging.
 */
public class ServerDebugValue extends ServerDebugElement implements IValue {
  private VmValue value;
  private IValueRetriever valueRetriever;

  private List<IVariable> fields;

  public ServerDebugValue(IDebugTarget target, IValueRetriever valueRetriever) {
    super(target);

    this.valueRetriever = valueRetriever;
  }

  public ServerDebugValue(IDebugTarget target, VmValue value) {
    super(target);

    this.value = value;
  }

  public String getDisplayString() {
    fillInFields();

    if (value == null) {
      return getValueString();
    } else if (value.isString()) {
      return "\"" + getValueString() + "\"";
    } else if (value.isObject()) {
      try {
        return getReferenceTypeName();
      } catch (DebugException e) {

      }
    } else if (value.isList()) {
      return "List[" + getListLength() + "]";
    }

    return getValueString();
  }

  @Override
  public String getReferenceTypeName() throws DebugException {
    if (value == null) {
      return null;
    }

    if (value.isObject()) {
      getVariables();

      if (value.getVmObject() != null) {
        return getConnection().getClassNameSync(value.getVmObject());
      }
    }

    return value.getKind();
  }

  @Override
  public String getValueString() {
    if (valueRetriever != null) {
      return valueRetriever.getDisplayName();
    } else {
      return value.getText();
    }
  }

  @Override
  public IVariable[] getVariables() throws DebugException {
    fillInFields();

    return fields.toArray(new ServerDebugVariable[fields.size()]);
  }

  @Override
  public boolean hasVariables() throws DebugException {
    return getVariables().length > 0;
  }

  @Override
  public boolean isAllocated() throws DebugException {
    return true;
  }

  public boolean isListValue() {
    return value == null ? false : value.isList();
  }

  protected void fillInFieldsSync() {
    final CountDownLatch latch = new CountDownLatch(1);

    final List<IVariable> tempFields = new ArrayList<IVariable>();

    try {
      getConnection().getObjectProperties(value.getObjectId(), new VmCallback<VmObject>() {
        @Override
        public void handleResult(VmResult<VmObject> result) {
          if (!result.isError()) {
            value.setVmObject(result.getResult());

            tempFields.addAll(convert(result.getResult()));
          }

          fillInStaticFields(result.getResult().getClassId(), tempFields, latch);
        }
      });
    } catch (Exception e) {
      latch.countDown();
    }

    try {
      latch.await();

      fields = tempFields;
    } catch (InterruptedException e) {

    }
  }

  protected void fillInStaticFields(int classId, final List<IVariable> tempFields,
      final CountDownLatch latch) {
    try {
      getConnection().getClassProperties(classId, new VmCallback<VmClass>() {
        @Override
        public void handleResult(VmResult<VmClass> result) {
          if (!result.isError()) {
            tempFields.addAll(convert(result.getResult()));
          }
          latch.countDown();
        }
      });
    } catch (IOException e) {
      latch.countDown();
    }
  }

  protected boolean isValueRetriever() {
    return valueRetriever != null;
  }

  synchronized void fillInFields() {
    if (value == null) {
      fields = valueRetriever.getVariables();
    } else if (value.isObject()) {
      if (fields == null) {
        fillInFieldsSync();
      }
    } else if (value.isList()) {
      fields = new ArrayList<IVariable>();

      for (int i = 0; i < value.getLength(); i++) {
        fields.add(new ServerDebugVariable(getTarget(), VmVariable.createArrayEntry(
            getConnection(),
            value,
            i)));
      }
    } else {
      if (fields == null) {
        fields = Collections.emptyList();
      }
    }
  }

  private List<IVariable> convert(VmClass vmClass) {
    List<IVariable> vars = new ArrayList<IVariable>();

    // Add static fields.
    for (VmVariable vmVariable : vmClass.getFields()) {
      ServerDebugVariable variable = new ServerDebugVariable(getTarget(), vmVariable);

      variable.setIsStatic(true);

      vars.add(variable);
    }

    return vars;
  }

  private List<IVariable> convert(VmObject vmObject) {
    List<IVariable> vars = new ArrayList<IVariable>();

    // Add instance fields.
    for (VmVariable vmVariable : vmObject.getFields()) {
      vars.add(new ServerDebugVariable(getTarget(), vmVariable));
    }

    return vars;
  }

  private int getListLength() {
    return value.getLength();
  }

}
