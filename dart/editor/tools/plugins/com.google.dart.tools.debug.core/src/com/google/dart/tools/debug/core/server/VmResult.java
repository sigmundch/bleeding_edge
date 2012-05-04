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

import org.json.JSONException;
import org.json.JSONObject;

/**
 * A VM command result.
 */
public class VmResult<T> {

  static <T> VmResult<T> createFrom(JSONObject params) throws JSONException {
    VmResult<T> result = new VmResult<T>();

    if (params.has("error")) {
      result.setError(params.get("error"));
    }

    return result;
  }

  private Object error;
  private T result;

  VmResult() {

  }

  public Object getError() {
    return error;
  }

  public T getResult() {
    return result;
  }

  public boolean isError() {
    return error != null;
  }

  @Override
  public String toString() {
    if (error != null) {
      return error.toString();
    } else if (result != null) {
      return result.toString();
    } else {
      return super.toString();
    }
  }

  void setError(Object error) {
    this.error = error;
  }

  void setResult(T result) {
    this.result = result;
  }

}