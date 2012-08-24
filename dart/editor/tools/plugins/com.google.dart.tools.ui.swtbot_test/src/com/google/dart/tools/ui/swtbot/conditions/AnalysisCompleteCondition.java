/*
 * Copyright 2012 Dart project authors.
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
package com.google.dart.tools.ui.swtbot.conditions;

import com.google.dart.tools.core.analysis.AnalysisServer;
import com.google.dart.tools.core.analysis.IdleListener;
import com.google.dart.tools.core.analysis.PerformanceListener;
import com.google.dart.tools.core.internal.model.PackageLibraryManagerProvider;
import com.google.dart.tools.ui.swtbot.performance.SwtBotPerformance;

import org.eclipse.swtbot.eclipse.finder.SWTWorkbenchBot;
import org.eclipse.swtbot.swt.finder.SWTBot;
import org.eclipse.swtbot.swt.finder.waits.ICondition;

import java.io.File;

public class AnalysisCompleteCondition implements ICondition {

  /**
   * Flag indicating whether the default analysis server is idle
   */
  private static boolean isIdle = true;

  /**
   * Start gathering performance information from {@link AnalysisServer}
   */
  public static void startListening() {
    AnalysisServer server = PackageLibraryManagerProvider.getDefaultAnalysisServer();
    AnalysisServer.setPerformanceListener(new PerformanceListener() {

      @Override
      public void analysisComplete(long start, File libraryFile) {
        SwtBotPerformance.ANALYZE.log(start, fileNameWithoutExtension(libraryFile.getName()));
      }

      private String fileNameWithoutExtension(String libName) {
        String simpleName = libName.substring(libName.lastIndexOf('/') + 1);
        if (simpleName.endsWith(".dart")) {
          simpleName = simpleName.substring(0, simpleName.length() - 5);
        }
        return simpleName;
      }
    });
    server.addIdleListener(new IdleListener() {

      @Override
      public void idle(boolean idle) {
        isIdle = idle;
      }
    });
  }

  public static void waitUntilWarmedUp(SWTWorkbenchBot bot) throws Exception {
    SwtBotPerformance.ANALYSIS_SERVER_WARMUP.log(bot, new AnalysisCompleteCondition());
  }

  @Override
  public String getFailureMessage() {
    return "Gave up waiting for AnalysisServer";
  }

  @Override
  public void init(SWTBot bot) {
  }

  @Override
  public boolean test() throws Exception {
    // Give the background analysis server thread a chance to execute
    Thread.yield();
    return isIdle;
  }
}
