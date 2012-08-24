// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
package com.google.dart.compiler;

import java.io.File;
import java.net.URI;

/**
 * A {@link LibrarySource} backed by a URL.
 */
public class UrlLibrarySource extends UrlSource implements LibrarySource {
  public UrlLibrarySource(URI uri, PackageLibraryManager slm) {
    super(uri, slm);
  }

  public UrlLibrarySource(URI uri) {
    this(uri, null);
  }

  public UrlLibrarySource(File file) {
    super(file);
  }

  @Override
  public String getName() {
    return getUri().toString();
  }

  @Override
  public DartSource getSourceFor(final String relPath) {
    if (relPath == null || relPath.isEmpty()) {
      return null;
    }
    try {
      // Force the creation of an escaped relative URI to deal with spaces, etc.s
      URI uri = getUri().resolve(new URI(null, null, relPath, null, null)).normalize();
      return new UrlDartSource(uri, relPath, this, packageLibraryManager);
    } catch (Throwable e) {
      return null;
    }
  }

  @Override
  public LibrarySource getImportFor(String relPath) {
    if (relPath == null || relPath.isEmpty()) {
      return null;
    }
    try {
      // Force the creation of an escaped relative URI to deal with spaces, etc.
      URI uri = getUri().resolve(new URI(null, null, relPath, null, null)).normalize();
      String path = uri.getPath();
      // Resolve relative reference out of one system library into another
      if (PackageLibraryManager.isDartUri(uri)) {
        if(path != null && path.startsWith("/..")) {
          URI fileUri = packageLibraryManager.resolveDartUri(uri);
          URI shortUri = packageLibraryManager.getShortUri(fileUri);
          if (shortUri != null) {
            uri = shortUri;
          }
        }
      } else if (PackageLibraryManager.isPackageUri(uri)){
        URI fileUri = packageLibraryManager.resolveDartUri(uri);
        if (fileUri != null){
          uri = fileUri;
        }
      } else if (path != null && !(new File(path).exists())){
        // resolve against package root directories to find file
         uri = packageLibraryManager.findExistingFileInPackages(uri);
      }
     
      return new UrlLibrarySource(uri, packageLibraryManager);
    } catch (Throwable e) {
      return null;
    }
  }
}
