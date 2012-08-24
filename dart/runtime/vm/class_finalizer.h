// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef VM_CLASS_FINALIZER_H_
#define VM_CLASS_FINALIZER_H_

#include "vm/allocation.h"
#include "vm/growable_array.h"

namespace dart {

class AbstractType;
class AbstractTypeArguments;
class Class;
class Error;
class Function;
class GrowableObjectArray;
class RawAbstractType;
class RawClass;
class RawType;
class Script;
class Type;
class UnresolvedClass;

// Traverses all pending, unfinalized classes, validates and marks them as
// finalized.
class ClassFinalizer : public AllStatic {
 public:
  // Modes for type resolution and finalization. The ordering is relevant.
  enum FinalizationKind {
    kIgnore,                 // Parsed type is ignored and replaced by Dynamic.
    kDoNotResolve,           // Type resolution is postponed.
    kTryResolve,             // Type resolution is attempted, but not required.
    kFinalize,               // Type resolution and type finalization are
                             // required; a malformed type is tolerated.
    kCanonicalize,           // Same as kFinalize, but with canonicalization.
    kCanonicalizeWellFormed  // Error-free resolution, finalization, and
                             // canonicalization are required; a malformed type
                             // is not tolerated.
  };

  // Finalize given type while parsing class cls.
  // Also canonicalize type if applicable.
  static RawAbstractType* FinalizeType(const Class& cls,
                                       const AbstractType& type,
                                       FinalizationKind finalization);

  // Replace the malformed type with Dynamic and, depending on the given type
  // finalization mode and execution mode, mark the type as malformed or report
  // a compile time error. Prepend prev_error if not null.
  static void FinalizeMalformedType(const Error& prev_error,
                                    const Class& cls,
                                    const Type& type,
                                    FinalizationKind finalization,
                                    const char* format, ...);

  // Return false if we still have classes pending to be finalized.
  static bool AllClassesFinalized();

  // Return whether class finalization failed.
  // The function returns true if the finalization was successful.
  // If finalization fails, an error message is set in the sticky error field
  // in the object store.
  static bool FinalizePendingClasses();


  // Verify that the classes have been properly prefinalized. This is
  // needed during bootstrapping where the classes have been preloaded.
  static void VerifyBootstrapClasses();

 private:
  static void FinalizeClass(const Class& cls);
  static bool IsSuperCycleFree(const Class& cls);
  static bool IsAliasCycleFree(const Class& cls,
                               GrowableArray<intptr_t>* visited);
  static void CheckForLegalConstClass(const Class& cls);
  static RawClass* ResolveClass(const Class& cls,
                                const UnresolvedClass& unresolved_class);
  static void ResolveSuperType(const Class& cls);
  static void ResolveFactoryClass(const Class& cls);
  static void ResolveInterfaces(const Class& cls,
                                GrowableArray<intptr_t>* visited);
  static void FinalizeTypeParameters(const Class& cls);
  static void FinalizeTypeArguments(const Class& cls,
                                    const AbstractTypeArguments& arguments,
                                    FinalizationKind finalization);
  static void ResolveType(const Class& cls,
                          const AbstractType& type,
                          FinalizationKind finalization);
  static void ResolveAndFinalizeUpperBounds(const Class& cls);
  static void ResolveAndFinalizeSignature(const Class& cls,
                                          const Function& function);
  static void ResolveAndFinalizeMemberTypes(const Class& cls);
  static void PrintClassInformation(const Class& cls);
  static void CollectInterfaces(const Class& cls,
                                const GrowableObjectArray& interfaces);
  static void ReportError(const Error& error);
  static void ReportError(const Script& script,
                          intptr_t token_index,
                          const char* format, ...);
  static void ReportError(const char* format, ...);
};

}  // namespace dart

#endif  // VM_CLASS_FINALIZER_H_
