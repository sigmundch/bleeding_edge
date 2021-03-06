// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include <stdio.h>

#include "include/dart_api.h"

#include "bin/builtin.h"
#include "bin/dartutils.h"


Builtin::builtin_lib_props Builtin::builtin_libraries_[] = {
  /*      url_                    source_       has_natives_  */
  { DartUtils::kBuiltinLibURL, builtin_source_, true  },
  { DartUtils::kJsonLibURL,    json_source_,    false },
  { DartUtils::kUriLibURL,     uri_source_,     false },
  { DartUtils::kCryptoLibURL,  crypto_source_,  false },
  { DartUtils::kIOLibURL,      io_source_,      true  },
  { DartUtils::kUtfLibURL,     utf_source_,     false }
};


Dart_Handle Builtin::Source(BuiltinLibraryId id) {
  ASSERT((sizeof(builtin_libraries_) / sizeof(builtin_lib_props)) ==
         kInvalidLibrary);
  ASSERT(id >= kBuiltinLibrary && id < kInvalidLibrary);
  return Dart_NewString(builtin_libraries_[id].source_);
}


void Builtin::SetNativeResolver(BuiltinLibraryId id) {
  UNREACHABLE();
}


Dart_Handle Builtin::LoadAndCheckLibrary(BuiltinLibraryId id) {
  ASSERT((sizeof(builtin_libraries_) / sizeof(builtin_lib_props)) ==
         kInvalidLibrary);
  ASSERT(id >= kBuiltinLibrary && id < kInvalidLibrary);
  Dart_Handle url = Dart_NewString(builtin_libraries_[id].url_);
  Dart_Handle library = Dart_LookupLibrary(url);
  if (Dart_IsError(library)) {
    library = Dart_LoadLibrary(url, Source(id));
    if (!Dart_IsError(library) && (builtin_libraries_[id].has_natives_)) {
      // Setup the native resolver for built in library functions.
      DART_CHECK_VALID(Dart_SetNativeResolver(library, NativeLookup));
    }
  }
  DART_CHECK_VALID(library);
  return library;
}
