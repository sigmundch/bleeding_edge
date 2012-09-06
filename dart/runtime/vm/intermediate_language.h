// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef VM_INTERMEDIATE_LANGUAGE_H_
#define VM_INTERMEDIATE_LANGUAGE_H_

#include "vm/allocation.h"
#include "vm/ast.h"
#include "vm/growable_array.h"
#include "vm/handles_impl.h"
#include "vm/locations.h"
#include "vm/object.h"

namespace dart {

class BitVector;
class BlockEntryInstr;
class BufferFormatter;
class ComparisonInstr;
class ControlInstruction;
class Definition;
class Environment;
class FlowGraphCompiler;
class FlowGraphVisitor;
class Instruction;
class LocalVariable;


// TODO(srdjan): Add _ByteArrayBase, get:length.

#define RECOGNIZED_LIST(V)                                                     \
  V(ObjectArray, get:length, ObjectArrayLength)                                \
  V(ImmutableArray, get:length, ImmutableArrayLength)                          \
  V(GrowableObjectArray, get:length, GrowableArrayLength)                      \
  V(StringBase, get:length, StringBaseLength)                                  \
  V(IntegerImplementation, toDouble, IntegerToDouble)                          \
  V(Double, toDouble, DoubleToDouble)                                          \
  V(::, sqrt, MathSqrt)                                                        \

// Class that recognizes the name and owner of a function and returns the
// corresponding enum. See RECOGNIZED_LIST above for list of recognizable
// functions.
class MethodRecognizer : public AllStatic {
 public:
  enum Kind {
    kUnknown,
#define DEFINE_ENUM_LIST(class_name, function_name, enum_name) k##enum_name,
RECOGNIZED_LIST(DEFINE_ENUM_LIST)
#undef DEFINE_ENUM_LIST
  };

  static Kind RecognizeKind(const Function& function);
  static const char* KindToCString(Kind kind);
};


class Value : public ZoneAllocated {
 public:
  explicit Value(Definition* definition)
      : definition_(definition),
        next_use_(NULL),
        instruction_(NULL),
        use_index_(-1) { }

  Definition* definition() const { return definition_; }
  void set_definition(Definition* definition) { definition_ = definition; }

  Value* next_use() const { return next_use_; }
  void set_next_use(Value* next) { next_use_ = next; }

  Instruction* instruction() const { return instruction_; }
  void set_instruction(Instruction* instruction) { instruction_ = instruction; }

  intptr_t use_index() const { return use_index_; }
  void set_use_index(intptr_t index) { use_index_ = index; }

  void AddToInputUseList();
  void AddToEnvUseList();

  Value* Copy() { return new Value(definition_); }

  RawAbstractType* CompileType() const;
  intptr_t ResultCid() const;

  void PrintTo(BufferFormatter* f) const;

  const char* DebugName() const { return "Value"; }

  // Returns true if the value represents a constant.
  bool BindsToConstant() const;

  // Returns true if the value represents the constant null.
  bool BindsToConstantNull() const;

  // Assert if BindsToConstant() is false, otherwise returns the constant value.
  const Object& BoundConstant() const;

  // Reminder: The type of the constant null is the bottom type, which is more
  // specific than any type.
  bool CompileTypeIsMoreSpecificThan(const AbstractType& dst_type) const;

  // Compile time constants, Bool, Smi and Nulls do not need to update
  // the store buffer.
  bool NeedsStoreBuffer() const;

  bool Equals(Value* other) const;

 private:
  Definition* definition_;
  Value* next_use_;
  Instruction* instruction_;
  intptr_t use_index_;

  DISALLOW_COPY_AND_ASSIGN(Value);
};


enum Representation {
  kTagged, kUnboxedDouble
};


// An embedded container with N elements of type T.  Used (with partial
// specialization for N=0) because embedded arrays cannot have size 0.
template<typename T, intptr_t N>
class EmbeddedArray {
 public:
  EmbeddedArray() {
    for (intptr_t i = 0; i < N; i++) elements_[i] = NULL;
  }

  intptr_t length() const { return N; }

  const T& operator[](intptr_t i) const {
    ASSERT(i < length());
    return elements_[i];
  }

  T& operator[](intptr_t i) {
    ASSERT(i < length());
    return elements_[i];
  }

  const T& At(intptr_t i) const {
    return (*this)[i];
  }

  void SetAt(intptr_t i, const T& val) {
    (*this)[i] = val;
  }

 private:
  T elements_[N];
};


template<typename T>
class EmbeddedArray<T, 0> {
 public:
  intptr_t length() const { return 0; }
  const T& operator[](intptr_t i) const {
    UNREACHABLE();
    static T sentinel = 0;
    return sentinel;
  }
  T& operator[](intptr_t i) {
    UNREACHABLE();
    static T sentinel = 0;
    return sentinel;
  }
};


// Instructions.

// M is a single argument macro.  It is applied to each concrete instruction
// type name.  The concrete instruction classes are the name with Instr
// concatenated.
#define FOR_EACH_INSTRUCTION(M)                                                \
  M(GraphEntry)                                                                \
  M(JoinEntry)                                                                 \
  M(TargetEntry)                                                               \
  M(Phi)                                                                       \
  M(Parameter)                                                                 \
  M(ParallelMove)                                                              \
  M(PushArgument)                                                              \
  M(Return)                                                                    \
  M(Throw)                                                                     \
  M(ReThrow)                                                                   \
  M(Goto)                                                                      \
  M(Branch)                                                                    \
  M(AssertAssignable)                                                          \
  M(AssertBoolean)                                                             \
  M(ArgumentDefinitionTest)                                                    \
  M(CurrentContext)                                                            \
  M(StoreContext)                                                              \
  M(ClosureCall)                                                               \
  M(InstanceCall)                                                              \
  M(PolymorphicInstanceCall)                                                   \
  M(StaticCall)                                                                \
  M(LoadLocal)                                                                 \
  M(StoreLocal)                                                                \
  M(StrictCompare)                                                             \
  M(EqualityCompare)                                                           \
  M(RelationalOp)                                                              \
  M(NativeCall)                                                                \
  M(LoadIndexed)                                                               \
  M(StoreIndexed)                                                              \
  M(LoadInstanceField)                                                         \
  M(StoreInstanceField)                                                        \
  M(LoadStaticField)                                                           \
  M(StoreStaticField)                                                          \
  M(BooleanNegate)                                                             \
  M(InstanceOf)                                                                \
  M(CreateArray)                                                               \
  M(CreateClosure)                                                             \
  M(AllocateObject)                                                            \
  M(AllocateObjectWithBoundsCheck)                                             \
  M(LoadVMField)                                                               \
  M(StoreVMField)                                                              \
  M(InstantiateTypeArguments)                                                  \
  M(ExtractConstructorTypeArguments)                                           \
  M(ExtractConstructorInstantiator)                                            \
  M(AllocateContext)                                                           \
  M(ChainContext)                                                              \
  M(CloneContext)                                                              \
  M(CatchEntry)                                                                \
  M(BinarySmiOp)                                                               \
  M(BinaryMintOp)                                                              \
  M(UnarySmiOp)                                                                \
  M(NumberNegate)                                                              \
  M(CheckStackOverflow)                                                        \
  M(DoubleToDouble)                                                            \
  M(SmiToDouble)                                                               \
  M(CheckClass)                                                                \
  M(CheckSmi)                                                                  \
  M(Constant)                                                                  \
  M(CheckEitherNonSmi)                                                         \
  M(UnboxedDoubleBinaryOp)                                                     \
  M(UnboxDouble)                                                               \
  M(BoxDouble)                                                                 \
  M(CheckArrayBound)                                                           \


#define FORWARD_DECLARATION(type) class type##Instr;
FOR_EACH_INSTRUCTION(FORWARD_DECLARATION)
#undef FORWARD_DECLARATION


// Functions required in all concrete instruction classes.
#define DECLARE_INSTRUCTION(type)                                              \
  virtual Tag tag() const { return k##type; }                                  \
  virtual void Accept(FlowGraphVisitor* visitor);                              \
  virtual type##Instr* As##type() { return this; }                             \
  virtual const char* DebugName() const { return #type; }                      \
  virtual LocationSummary* MakeLocationSummary() const;                        \
  virtual void EmitNativeCode(FlowGraphCompiler* compiler);                    \


class Instruction : public ZoneAllocated {
 public:
#define DECLARE_TAG(type) k##type,
  enum Tag {
    FOR_EACH_INSTRUCTION(DECLARE_TAG)
  };
#undef DECLARE_TAG

  Instruction()
      : deopt_id_(Isolate::Current()->GetNextDeoptId()),
        lifetime_position_(-1),
        previous_(NULL),
        next_(NULL),
        env_(NULL) { }

  virtual Tag tag() const = 0;

  intptr_t deopt_id() const {
    ASSERT(CanDeoptimize());
    return deopt_id_;
  }

  bool IsBlockEntry() { return (AsBlockEntry() != NULL); }
  virtual BlockEntryInstr* AsBlockEntry() { return NULL; }

  bool IsDefinition() { return (AsDefinition() != NULL); }
  virtual Definition* AsDefinition() { return NULL; }

  bool IsControl() { return (AsControl() != NULL); }
  virtual ControlInstruction* AsControl() { return NULL; }

  virtual intptr_t InputCount() const = 0;
  virtual Value* InputAt(intptr_t i) const = 0;
  virtual void SetInputAt(intptr_t i, Value* value) = 0;

  // Call instructions override this function and return the number of
  // pushed arguments.
  virtual intptr_t ArgumentCount() const = 0;

  // Returns true, if this instruction can deoptimize.
  virtual bool CanDeoptimize() const = 0;

  // Visiting support.
  virtual void Accept(FlowGraphVisitor* visitor) = 0;

  Instruction* previous() const { return previous_; }
  void set_previous(Instruction* instr) {
    ASSERT(!IsBlockEntry());
    previous_ = instr;
  }

  Instruction* next() const { return next_; }
  void set_next(Instruction* instr) {
    ASSERT(!IsGraphEntry());
    ASSERT(!IsReturn());
    ASSERT(!IsControl());
    ASSERT(!IsPhi());
    ASSERT(instr == NULL || !instr->IsBlockEntry());
    // TODO(fschneider): Also add Throw and ReThrow to the list of instructions
    // that do not have a successor. Currently, the graph builder will continue
    // to append instruction in case of a Throw inside an expression. This
    // condition should be handled in the graph builder
    next_ = instr;
  }

  // Removed this instruction from the graph.
  Instruction* RemoveFromGraph(bool return_previous = true);

  // Normal instructions can have 0 (inside a block) or 1 (last instruction in
  // a block) successors. Branch instruction with >1 successors override this
  // function.
  virtual intptr_t SuccessorCount() const;
  virtual BlockEntryInstr* SuccessorAt(intptr_t index) const;

  void Goto(JoinEntryInstr* entry);

  // Discover basic-block structure by performing a recursive depth first
  // traversal of the instruction graph reachable from this instruction.  As
  // a side effect, the block entry instructions in the graph are assigned
  // numbers in both preorder and postorder.  The array 'preorder' maps
  // preorder block numbers to the block entry instruction with that number
  // and analogously for the array 'postorder'.  The depth first spanning
  // tree is recorded in the array 'parent', which maps preorder block
  // numbers to the preorder number of the block's spanning-tree parent.
  // The array 'assigned_vars' maps preorder block numbers to the set of
  // assigned frame-allocated local variables in the block.  As a side
  // effect of this function, the set of basic block predecessors (e.g.,
  // block entry instructions of predecessor blocks) and also the last
  // instruction in the block is recorded in each entry instruction.
  virtual void DiscoverBlocks(
      BlockEntryInstr* current_block,
      GrowableArray<BlockEntryInstr*>* preorder,
      GrowableArray<BlockEntryInstr*>* postorder,
      GrowableArray<intptr_t>* parent,
      GrowableArray<BitVector*>* assigned_vars,
      intptr_t variable_count,
      intptr_t fixed_parameter_count) {
    // Never called for instructions except block entries and branches.
    UNREACHABLE();
  }

  // Mutate assigned_vars to add the local variable index for all
  // frame-allocated locals assigned to by the instruction.
  virtual void RecordAssignedVars(BitVector* assigned_vars,
                                  intptr_t fixed_parameter_count);

  virtual const char* DebugName() const = 0;

  // Printing support.
  virtual void PrintTo(BufferFormatter* f) const = 0;
  virtual void PrintToVisualizer(BufferFormatter* f) const = 0;

#define INSTRUCTION_TYPE_CHECK(type)                                           \
  bool Is##type() { return (As##type() != NULL); }                             \
  virtual type##Instr* As##type() { return NULL; }
FOR_EACH_INSTRUCTION(INSTRUCTION_TYPE_CHECK)
#undef INSTRUCTION_TYPE_CHECK

  // Returns structure describing location constraints required
  // to emit native code for this instruction.
  virtual LocationSummary* locs() {
    // TODO(vegorov): This should be pure virtual method.
    // However we are temporary using NULL for instructions that
    // were not converted to the location based code generation yet.
    return NULL;
  }

  virtual LocationSummary* MakeLocationSummary() const = 0;

  static LocationSummary* MakeCallSummary();

  virtual void EmitNativeCode(FlowGraphCompiler* compiler) {
    UNIMPLEMENTED();
  }

  Environment* env() const { return env_; }
  void set_env(Environment* env) { env_ = env; }

  intptr_t lifetime_position() const { return lifetime_position_; }
  void set_lifetime_position(intptr_t pos) {
    lifetime_position_ = pos;
  }

  // Returns representation expected for the input operand at the given index.
  virtual Representation RequiredInputRepresentation(intptr_t idx) const {
    return kTagged;
  }

  // Representation of the value produced by this computation.
  virtual Representation representation() const {
    return kTagged;
  }

  bool WasEliminated() const {
    return next() == NULL;
  }

  // Returns deoptimization id that corresponds to the deoptimization target
  // that input operands conversions inserted for this instruction can jump
  // to.
  virtual intptr_t DeoptimizationTarget() const {
    UNREACHABLE();
    return Isolate::kNoDeoptId;
  }

 protected:
  // Fetch deopt id without checking if this computation can deoptimize.
  intptr_t GetDeoptId() const {
    return deopt_id_;
  }

 private:
  friend class Definition;  // Needed for InsertBefore, InsertAfter.

  // Classes that set deopt_id_.
  friend class UnboxDoubleInstr;
  friend class UnboxedDoubleBinaryOpInstr;
  friend class CheckClassInstr;
  friend class CheckSmiInstr;
  friend class CheckArrayBoundInstr;
  friend class CheckEitherNonSmiInstr;
  friend class LICM;

  intptr_t deopt_id_;
  intptr_t lifetime_position_;  // Position used by register allocator.
  Instruction* previous_;
  Instruction* next_;
  Environment* env_;
  DISALLOW_COPY_AND_ASSIGN(Instruction);
};


template<intptr_t N>
class TemplateInstruction: public Instruction {
 public:
  TemplateInstruction<N>() : locs_(NULL) { }

  virtual intptr_t InputCount() const { return N; }
  virtual Value* InputAt(intptr_t i) const { return inputs_[i]; }
  virtual void SetInputAt(intptr_t i, Value* value) {
    ASSERT(value != NULL);
    inputs_[i] = value;
  }

  virtual LocationSummary* locs() {
    if (locs_ == NULL) {
      locs_ = MakeLocationSummary();
    }
    return locs_;
  }

 protected:
  EmbeddedArray<Value*, N> inputs_;

 private:
  LocationSummary* locs_;
};


class MoveOperands : public ZoneAllocated {
 public:
  MoveOperands(Location dest, Location src) : dest_(dest), src_(src) { }

  Location src() const { return src_; }
  Location dest() const { return dest_; }

  Location* src_slot() { return &src_; }
  Location* dest_slot() { return &dest_; }

  void set_src(const Location& value) { src_ = value; }
  void set_dest(const Location& value) { dest_ = value; }

  // The parallel move resolver marks moves as "in-progress" by clearing the
  // destination (but not the source).
  Location MarkPending() {
    ASSERT(!IsPending());
    Location dest = dest_;
    dest_ = Location::NoLocation();
    return dest;
  }

  void ClearPending(Location dest) {
    ASSERT(IsPending());
    dest_ = dest;
  }

  bool IsPending() const {
    ASSERT(!src_.IsInvalid() || dest_.IsInvalid());
    return dest_.IsInvalid() && !src_.IsInvalid();
  }

  // True if this move a move from the given location.
  bool Blocks(Location loc) const {
    return !IsEliminated() && src_.Equals(loc);
  }

  // A move is redundant if it's been eliminated, if its source and
  // destination are the same, or if its destination is unneeded.
  bool IsRedundant() const {
    return IsEliminated() || dest_.IsInvalid() || src_.Equals(dest_);
  }

  // We clear both operands to indicate move that's been eliminated.
  void Eliminate() { src_ = dest_ = Location::NoLocation(); }
  bool IsEliminated() const {
    ASSERT(!src_.IsInvalid() || dest_.IsInvalid());
    return src_.IsInvalid();
  }

 private:
  Location dest_;
  Location src_;

  DISALLOW_COPY_AND_ASSIGN(MoveOperands);
};


class ParallelMoveInstr : public TemplateInstruction<0> {
 public:
  ParallelMoveInstr() : moves_(4) { }

  DECLARE_INSTRUCTION(ParallelMove)

  virtual intptr_t ArgumentCount() const { return 0; }

  virtual bool CanDeoptimize() const { return false; }

  MoveOperands* AddMove(Location dest, Location src) {
    MoveOperands* move = new MoveOperands(dest, src);
    moves_.Add(move);
    return move;
  }

  MoveOperands* MoveOperandsAt(intptr_t index) const { return moves_[index]; }

  void SetSrcSlotAt(intptr_t index, const Location& loc);
  void SetDestSlotAt(intptr_t index, const Location& loc);

  intptr_t NumMoves() const { return moves_.length(); }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  GrowableArray<MoveOperands*> moves_;   // Elements cannot be null.

  DISALLOW_COPY_AND_ASSIGN(ParallelMoveInstr);
};


// Basic block entries are administrative nodes.  There is a distinguished
// graph entry with no predecessor.  Joins are the only nodes with multiple
// predecessors.  Targets are all other basic block entries.  The types
// enforce edge-split form---joins are forbidden as the successors of
// branches.
class BlockEntryInstr : public Instruction {
 public:
  virtual BlockEntryInstr* AsBlockEntry() { return this; }

  virtual intptr_t PredecessorCount() const = 0;
  virtual BlockEntryInstr* PredecessorAt(intptr_t index) const = 0;
  virtual void AddPredecessor(BlockEntryInstr* predecessor) = 0;
  virtual void PrepareEntry(FlowGraphCompiler* compiler) = 0;

  intptr_t preorder_number() const { return preorder_number_; }
  void set_preorder_number(intptr_t number) { preorder_number_ = number; }

  intptr_t postorder_number() const { return postorder_number_; }
  void set_postorder_number(intptr_t number) { postorder_number_ = number; }

  intptr_t block_id() const { return block_id_; }
  void set_block_id(intptr_t value) { block_id_ = value; }

  void set_start_pos(intptr_t pos) { start_pos_ = pos; }
  intptr_t start_pos() const { return start_pos_; }
  void  set_end_pos(intptr_t pos) { end_pos_ = pos; }
  intptr_t end_pos() const { return end_pos_; }

  BlockEntryInstr* dominator() const { return dominator_; }
  void set_dominator(BlockEntryInstr* instr) { dominator_ = instr; }

  const GrowableArray<BlockEntryInstr*>& dominated_blocks() {
    return dominated_blocks_;
  }

  void AddDominatedBlock(BlockEntryInstr* block) {
    dominated_blocks_.Add(block);
  }

  bool Dominates(BlockEntryInstr* other) const;

  Instruction* last_instruction() const { return last_instruction_; }
  void set_last_instruction(Instruction* instr) { last_instruction_ = instr; }

  ParallelMoveInstr* parallel_move() const {
    return parallel_move_;
  }

  bool HasParallelMove() const {
    return parallel_move_ != NULL;
  }

  ParallelMoveInstr* GetParallelMove() {
    if (parallel_move_ == NULL) {
      parallel_move_ = new ParallelMoveInstr();
    }
    return parallel_move_;
  }

  virtual void DiscoverBlocks(
      BlockEntryInstr* current_block,
      GrowableArray<BlockEntryInstr*>* preorder,
      GrowableArray<BlockEntryInstr*>* postorder,
      GrowableArray<intptr_t>* parent,
      GrowableArray<BitVector*>* assigned_vars,
      intptr_t variable_count,
      intptr_t fixed_parameter_count);

  virtual intptr_t InputCount() const { return 0; }
  virtual Value* InputAt(intptr_t i) const {
    UNREACHABLE();
    return NULL;
  }
  virtual void SetInputAt(intptr_t i, Value* value) { UNREACHABLE(); }

  virtual intptr_t ArgumentCount() const { return 0; }

  virtual bool CanDeoptimize() const { return false; }

  intptr_t try_index() const { return try_index_; }

  BitVector* loop_info() const { return loop_info_; }
  void set_loop_info(BitVector* loop_info) {
    loop_info_ = loop_info;
  }

 protected:
  explicit BlockEntryInstr(intptr_t try_index)
      : try_index_(try_index),
        preorder_number_(-1),
        postorder_number_(-1),
        block_id_(-1),
        dominator_(NULL),
        dominated_blocks_(1),
        last_instruction_(NULL),
        parallel_move_(NULL),
        loop_info_(NULL) { }

 private:
  const intptr_t try_index_;
  intptr_t preorder_number_;
  intptr_t postorder_number_;
  // Starting and ending lifetime positions for this block.  Used by
  // the linear scan register allocator.
  intptr_t block_id_;
  intptr_t start_pos_;
  intptr_t end_pos_;
  BlockEntryInstr* dominator_;  // Immediate dominator, NULL for graph entry.
  // TODO(fschneider): Optimize the case of one child to save space.
  GrowableArray<BlockEntryInstr*> dominated_blocks_;
  Instruction* last_instruction_;

  // Parallel move that will be used by linear scan register allocator to
  // connect live ranges at the start of the block.
  ParallelMoveInstr* parallel_move_;

  // Bit vector containg loop blocks for a loop header indexed by block
  // preorder number.
  BitVector* loop_info_;

  DISALLOW_COPY_AND_ASSIGN(BlockEntryInstr);
};


class ForwardInstructionIterator : public ValueObject {
 public:
  explicit ForwardInstructionIterator(BlockEntryInstr* block_entry)
      : block_entry_(block_entry), current_(block_entry) {
    ASSERT(block_entry_->last_instruction()->next() == NULL);
    Advance();
  }

  void Advance() {
    ASSERT(!Done());
    current_ = current_->next();
  }

  bool Done() const { return current_ == NULL; }

  // Removes 'current_' from graph and sets 'current_' to previous instruction.
  void RemoveCurrentFromGraph();

  // Inserts replaces 'current_', which must be a definition, with another
  // definition.  The new definition becomes 'current_'.
  void ReplaceCurrentWith(Definition* other);

  Instruction* Current() const { return current_; }

 private:
  BlockEntryInstr* block_entry_;
  Instruction* current_;
};


class BackwardInstructionIterator : public ValueObject {
 public:
  explicit BackwardInstructionIterator(BlockEntryInstr* block_entry)
      : block_entry_(block_entry), current_(block_entry->last_instruction()) {
    ASSERT(block_entry_->previous() == NULL);
  }

  void Advance() {
    ASSERT(!Done());
    current_ = current_->previous();
  }

  bool Done() const { return current_ == block_entry_; }

  Instruction* Current() const { return current_; }

 private:
  BlockEntryInstr* block_entry_;
  Instruction* current_;
};


class GraphEntryInstr : public BlockEntryInstr {
 public:
  explicit GraphEntryInstr(TargetEntryInstr* normal_entry);

  DECLARE_INSTRUCTION(GraphEntry)

  virtual intptr_t PredecessorCount() const { return 0; }
  virtual BlockEntryInstr* PredecessorAt(intptr_t index) const {
    UNREACHABLE();
    return NULL;
  }
  virtual void AddPredecessor(BlockEntryInstr* predecessor) { UNREACHABLE(); }

  virtual intptr_t SuccessorCount() const;
  virtual BlockEntryInstr* SuccessorAt(intptr_t index) const;

  virtual void DiscoverBlocks(
      BlockEntryInstr* current_block,
      GrowableArray<BlockEntryInstr*>* preorder,
      GrowableArray<BlockEntryInstr*>* postorder,
      GrowableArray<intptr_t>* parent,
      GrowableArray<BitVector*>* assigned_vars,
      intptr_t variable_count,
      intptr_t fixed_parameter_count);

  void AddCatchEntry(TargetEntryInstr* entry) { catch_entries_.Add(entry); }

  virtual void PrepareEntry(FlowGraphCompiler* compiler);

  Environment* start_env() const { return start_env_; }
  void set_start_env(Environment* env) { start_env_ = env; }

  ConstantInstr* constant_null() const { return constant_null_; }

  intptr_t spill_slot_count() const { return spill_slot_count_; }
  void set_spill_slot_count(intptr_t count) {
    ASSERT(count >= 0);
    spill_slot_count_ = count;
  }

  TargetEntryInstr* normal_entry() const { return normal_entry_; }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  TargetEntryInstr* normal_entry_;
  GrowableArray<TargetEntryInstr*> catch_entries_;
  Environment* start_env_;
  ConstantInstr* constant_null_;
  intptr_t spill_slot_count_;

  DISALLOW_COPY_AND_ASSIGN(GraphEntryInstr);
};


class JoinEntryInstr : public BlockEntryInstr {
 public:
  explicit JoinEntryInstr(intptr_t try_index)
      : BlockEntryInstr(try_index),
        predecessors_(2),  // Two is the assumed to be the common case.
        phis_(NULL),
        phi_count_(0) { }

  DECLARE_INSTRUCTION(JoinEntry)

  virtual intptr_t PredecessorCount() const { return predecessors_.length(); }
  virtual BlockEntryInstr* PredecessorAt(intptr_t index) const {
    return predecessors_[index];
  }
  virtual void AddPredecessor(BlockEntryInstr* predecessor) {
    predecessors_.Add(predecessor);
  }

  // Returns -1 if pred is not in the list.
  intptr_t IndexOfPredecessor(BlockEntryInstr* pred) const;

  ZoneGrowableArray<PhiInstr*>* phis() const { return phis_; }

  virtual void PrepareEntry(FlowGraphCompiler* compiler);

  void InsertPhi(intptr_t var_index, intptr_t var_count);
  void RemoveDeadPhis();

  intptr_t phi_count() const { return phi_count_; }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  GrowableArray<BlockEntryInstr*> predecessors_;
  ZoneGrowableArray<PhiInstr*>* phis_;
  intptr_t phi_count_;

  DISALLOW_COPY_AND_ASSIGN(JoinEntryInstr);
};


class TargetEntryInstr : public BlockEntryInstr {
 public:
  explicit TargetEntryInstr(intptr_t try_index)
      : BlockEntryInstr(try_index),
        predecessor_(NULL),
        catch_try_index_(CatchClauseNode::kInvalidTryIndex) { }

  // Used for exception catch entries.
  TargetEntryInstr(intptr_t try_index, intptr_t catch_try_index)
      : BlockEntryInstr(try_index),
        predecessor_(NULL),
        catch_try_index_(catch_try_index) { }

  DECLARE_INSTRUCTION(TargetEntry)

  virtual intptr_t PredecessorCount() const {
    return (predecessor_ == NULL) ? 0 : 1;
  }
  virtual BlockEntryInstr* PredecessorAt(intptr_t index) const {
    ASSERT((index == 0) && (predecessor_ != NULL));
    return predecessor_;
  }
  virtual void AddPredecessor(BlockEntryInstr* predecessor) {
    ASSERT(predecessor_ == NULL);
    predecessor_ = predecessor;
  }

  // Returns true if this Block is an entry of a catch handler.
  bool IsCatchEntry() const {
    return catch_try_index_ != CatchClauseNode::kInvalidTryIndex;
  }

  // Returns try index for the try block to which this catch handler
  // corresponds.
  intptr_t catch_try_index() const {
    ASSERT(IsCatchEntry());
    return catch_try_index_;
  }

  virtual void PrepareEntry(FlowGraphCompiler* compiler);

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  BlockEntryInstr* predecessor_;
  const intptr_t catch_try_index_;

  DISALLOW_COPY_AND_ASSIGN(TargetEntryInstr);
};


// Abstract super-class of all instructions that define a value (Bind, Phi).
class Definition : public Instruction {
 public:
  enum UseKind { kEffect, kValue };

  Definition()
      : temp_index_(-1),
        ssa_temp_index_(-1),
        propagated_type_(AbstractType::Handle()),
        propagated_cid_(kIllegalCid),
        input_use_list_(NULL),
        env_use_list_(NULL),
        use_kind_(kValue) {  // Phis and parameters rely on this default.
  }

  virtual Definition* AsDefinition() { return this; }

  bool IsComparison() { return (AsComparison() != NULL); }
  virtual ComparisonInstr* AsComparison() { return NULL; }

  // Overridden by definitions that push arguments.
  virtual intptr_t ArgumentCount() const { return 0; }

  intptr_t temp_index() const { return temp_index_; }
  void set_temp_index(intptr_t index) { temp_index_ = index; }

  intptr_t ssa_temp_index() const { return ssa_temp_index_; }
  void set_ssa_temp_index(intptr_t index) {
    ASSERT(index >= 0);
    ASSERT(is_used());
    ssa_temp_index_ = index;
  }
  bool HasSSATemp() const { return ssa_temp_index_ >= 0; }

  bool is_used() const { return (use_kind_ != kEffect); }
  void set_use_kind(UseKind kind) { use_kind_ = kind; }

  // Compile time type of the definition, which may be requested before type
  // propagation during graph building.
  virtual RawAbstractType* CompileType() const = 0;

  virtual intptr_t ResultCid() const = 0;

  bool HasPropagatedType() const {
    return !propagated_type_.IsNull();
  }
  RawAbstractType* PropagatedType() const {
    ASSERT(HasPropagatedType());
    return propagated_type_.raw();
  }
  // Returns true if the propagated type has changed.
  bool SetPropagatedType(const AbstractType& propagated_type) {
    if (propagated_type.IsNull()) {
      // Not a typed definition, e.g. access to a VM field.
      return false;
    }
    const bool changed =
        propagated_type_.IsNull() || !propagated_type.Equals(propagated_type_);
    propagated_type_ = propagated_type.raw();
    return changed;
  }

  bool has_propagated_cid() const { return propagated_cid_ != kIllegalCid; }
  intptr_t propagated_cid() const { return propagated_cid_; }

  // May compute and set propagated cid.
  virtual intptr_t GetPropagatedCid();

  // Returns true if the propagated cid has changed.
  bool SetPropagatedCid(intptr_t cid);

  // Returns true if the definition may have side effects.
  // TODO(fschneider): Make this abstract and implement for all definitions
  // instead of returning the safe default (true).
  virtual bool HasSideEffect() const { return true; }

  Value* input_use_list() { return input_use_list_; }
  void set_input_use_list(Value* head) { input_use_list_ = head; }

  Value* env_use_list() { return env_use_list_; }
  void set_env_use_list(Value* head) { env_use_list_ = head; }

  // Returns a replacement for the definition or NULL if the definition can
  // be eliminated.  By default returns the definition (input parameter)
  // which means no change.
  virtual Definition* Canonicalize();

  // Replace uses of this definition with uses of other definition or value.
  // Precondition: use lists must be properly calculated.
  // Postcondition: use lists and use values are still valid.
  void ReplaceUsesWith(Definition* other);

  // Replace this definition and all uses with another definition.  If
  // replacing during iteration, pass the iterator so that the instruction
  // can be replaced without affecting iteration order, otherwise pass a
  // NULL iterator.
  void ReplaceWith(Definition* other, ForwardInstructionIterator* iterator);

  // Insert this definition before 'next'.
  void InsertBefore(Instruction* next);

  // Insert this definition after 'prev'.
  void InsertAfter(Instruction* prev);

  // Compares two definitions.  Returns true, iff:
  // 1. They have the same tag.
  // 2. All input operands are Equals.
  // 3. They satisfy AttributesEqual.
  bool Equals(Definition* other) const;

  // Compare attributes of a definition (except input operands and tag).
  // All definition that participate in CSE have to override this function.
  // This function can assume that the argument has the same type as this.
  virtual bool AttributesEqual(Definition* other) const {
    UNREACHABLE();
    return false;
  }

  // Returns a hash code for use with hash maps.
  virtual intptr_t Hashcode() const;

  virtual void RecordAssignedVars(BitVector* assigned_vars,
                                  intptr_t fixed_parameter_count);

  // Get the block entry for that instruction.
  virtual BlockEntryInstr* GetBlock() const;

  // Printing support. These functions are sometimes overridden for custom
  // formatting. Otherwise, it prints in the format "opcode(op1, op2, op3)".
  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintOperandsTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  intptr_t temp_index_;
  intptr_t ssa_temp_index_;
  // TODO(regis): GrowableArray<const AbstractType*> propagated_types_;
  // For now:
  AbstractType& propagated_type_;
  intptr_t propagated_cid_;
  Value* input_use_list_;
  Value* env_use_list_;
  UseKind use_kind_;

  DISALLOW_COPY_AND_ASSIGN(Definition);
};


class PhiInstr : public Definition {
 public:
  explicit PhiInstr(JoinEntryInstr* block, intptr_t num_inputs)
    : block_(block),
      inputs_(num_inputs),
      is_alive_(false),
      representation_(kTagged) {
    for (intptr_t i = 0; i < num_inputs; ++i) {
      inputs_.Add(NULL);
    }
  }

  // Get the block entry for that instruction.
  virtual BlockEntryInstr* GetBlock() const { return block(); }
  JoinEntryInstr* block() const { return block_; }

  virtual RawAbstractType* CompileType() const;
  virtual intptr_t GetPropagatedCid();

  virtual intptr_t ArgumentCount() const { return 0; }

  intptr_t InputCount() const { return inputs_.length(); }

  Value* InputAt(intptr_t i) const { return inputs_[i]; }

  void SetInputAt(intptr_t i, Value* value) { inputs_[i] = value; }

  virtual bool CanDeoptimize() const { return false; }

  // TODO(regis): This helper will be removed once we support type sets.
  RawAbstractType* LeastSpecificInputType() const;

  // Phi is alive if it reaches a non-environment use.
  bool is_alive() const { return is_alive_; }
  void mark_alive() { is_alive_ = true; }

  virtual Representation RequiredInputRepresentation(intptr_t i) const {
    return representation_;
  }

  virtual Representation representation() const {
    return representation_;
  }

  virtual void set_representation(Representation r) {
    representation_ = r;
  }

  virtual intptr_t Hashcode() const {
    UNREACHABLE();
    return 0;
  }

  virtual intptr_t ResultCid() const {
    UNREACHABLE();
    return kIllegalCid;
  }

  DECLARE_INSTRUCTION(Phi)

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  JoinEntryInstr* block_;
  GrowableArray<Value*> inputs_;
  bool is_alive_;
  Representation representation_;

  DISALLOW_COPY_AND_ASSIGN(PhiInstr);
};


class ParameterInstr : public Definition {
 public:
  explicit ParameterInstr(intptr_t index, GraphEntryInstr* block)
      : index_(index), block_(block) { }

  DECLARE_INSTRUCTION(Parameter)

  intptr_t index() const { return index_; }

  // Get the block entry for that instruction.
  virtual BlockEntryInstr* GetBlock() const { return block_; }

  // Compile type of the passed-in parameter.
  virtual RawAbstractType* CompileType() const;

  // No known propagated cid for parameters.
  virtual intptr_t GetPropagatedCid();

  virtual intptr_t ArgumentCount() const { return 0; }

  intptr_t InputCount() const { return 0; }
  Value* InputAt(intptr_t i) const {
    UNREACHABLE();
    return NULL;
  }
  void SetInputAt(intptr_t i, Value* value) { UNREACHABLE(); }

  virtual bool CanDeoptimize() const { return false; }

  virtual intptr_t Hashcode() const {
    UNREACHABLE();
    return 0;
  }

  virtual intptr_t ResultCid() const {
    UNREACHABLE();
    return kIllegalCid;
  }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  const intptr_t index_;
  GraphEntryInstr* block_;

  DISALLOW_COPY_AND_ASSIGN(ParameterInstr);
};


class PushArgumentInstr : public Definition {
 public:
  explicit PushArgumentInstr(Value* value) : value_(value), locs_(NULL) {
    ASSERT(value != NULL);
    set_use_kind(kEffect);  // Override the default.
  }

  DECLARE_INSTRUCTION(PushArgument)

  intptr_t InputCount() const { return 1; }
  Value* InputAt(intptr_t i) const {
    ASSERT(i == 0);
    return value_;
  }
  void SetInputAt(intptr_t i, Value* value) {
    ASSERT(i == 0);
    value_ = value;
  }

  virtual intptr_t ArgumentCount() const { return 0; }

  virtual RawAbstractType* CompileType() const;
  virtual intptr_t GetPropagatedCid() { return propagated_cid(); }
  virtual intptr_t ResultCid() const {
    UNREACHABLE();
    return kIllegalCid;
  }

  Value* value() const { return value_; }

  virtual LocationSummary* locs() {
    if (locs_ == NULL) {
      locs_ = MakeLocationSummary();
    }
    return locs_;
  }

  virtual intptr_t Hashcode() const {
    UNREACHABLE();
    return 0;
  }

  virtual bool CanDeoptimize() const { return false; }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  Value* value_;
  LocationSummary* locs_;

  DISALLOW_COPY_AND_ASSIGN(PushArgumentInstr);
};


class ReturnInstr : public TemplateInstruction<1> {
 public:
  ReturnInstr(intptr_t token_pos, Value* value)
      : token_pos_(token_pos) {
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  DECLARE_INSTRUCTION(Return)

  virtual intptr_t ArgumentCount() const { return 0; }

  intptr_t token_pos() const { return token_pos_; }
  Value* value() const { return inputs_[0]; }

  virtual bool CanDeoptimize() const { return false; }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  const intptr_t token_pos_;

  DISALLOW_COPY_AND_ASSIGN(ReturnInstr);
};


class ThrowInstr : public TemplateInstruction<0> {
 public:
  explicit ThrowInstr(intptr_t token_pos) : token_pos_(token_pos) { }

  DECLARE_INSTRUCTION(Throw)

  virtual intptr_t ArgumentCount() const { return 1; }

  intptr_t token_pos() const { return token_pos_; }

  virtual bool CanDeoptimize() const { return false; }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  const intptr_t token_pos_;

  DISALLOW_COPY_AND_ASSIGN(ThrowInstr);
};


class ReThrowInstr : public TemplateInstruction<0> {
 public:
  explicit ReThrowInstr(intptr_t token_pos) : token_pos_(token_pos) { }

  DECLARE_INSTRUCTION(ReThrow)

  virtual intptr_t ArgumentCount() const { return 2; }

  intptr_t token_pos() const { return token_pos_; }

  virtual bool CanDeoptimize() const { return false; }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  const intptr_t token_pos_;

  DISALLOW_COPY_AND_ASSIGN(ReThrowInstr);
};


class GotoInstr : public TemplateInstruction<0> {
 public:
  explicit GotoInstr(JoinEntryInstr* entry)
    : successor_(entry),
      parallel_move_(NULL) { }

  DECLARE_INSTRUCTION(Goto)

  virtual intptr_t ArgumentCount() const { return 0; }

  JoinEntryInstr* successor() const { return successor_; }
  void set_successor(JoinEntryInstr* successor) { successor_ = successor; }
  virtual intptr_t SuccessorCount() const;
  virtual BlockEntryInstr* SuccessorAt(intptr_t index) const;

  virtual bool CanDeoptimize() const { return false; }

  ParallelMoveInstr* parallel_move() const {
    return parallel_move_;
  }

  bool HasParallelMove() const {
    return parallel_move_ != NULL;
  }

  ParallelMoveInstr* GetParallelMove() {
    if (parallel_move_ == NULL) {
      parallel_move_ = new ParallelMoveInstr();
    }
    return parallel_move_;
  }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  JoinEntryInstr* successor_;

  // Parallel move that will be used by linear scan register allocator to
  // connect live ranges at the end of the block and resolve phis.
  ParallelMoveInstr* parallel_move_;
};


class ControlInstruction : public Instruction {
 public:
  ControlInstruction() : true_successor_(NULL), false_successor_(NULL) { }

  virtual ControlInstruction* AsControl() { return this; }

  TargetEntryInstr* true_successor() const { return true_successor_; }
  TargetEntryInstr* false_successor() const { return false_successor_; }

  TargetEntryInstr** true_successor_address() { return &true_successor_; }
  TargetEntryInstr** false_successor_address() { return &false_successor_; }

  virtual intptr_t SuccessorCount() const;
  virtual BlockEntryInstr* SuccessorAt(intptr_t index) const;

  virtual void DiscoverBlocks(
      BlockEntryInstr* current_block,
      GrowableArray<BlockEntryInstr*>* preorder,
      GrowableArray<BlockEntryInstr*>* postorder,
      GrowableArray<intptr_t>* parent,
      GrowableArray<BitVector*>* assigned_vars,
      intptr_t variable_count,
      intptr_t fixed_parameter_count);


  void EmitBranchOnCondition(FlowGraphCompiler* compiler,
                             Condition true_condition);

  void EmitBranchOnValue(FlowGraphCompiler* compiler, bool result);

 private:
  TargetEntryInstr* true_successor_;
  TargetEntryInstr* false_successor_;

  DISALLOW_COPY_AND_ASSIGN(ControlInstruction);
};


class BranchInstr : public ControlInstruction {
 public:
  explicit BranchInstr(ComparisonInstr* comparison)
      : comparison_(comparison) { }

  DECLARE_INSTRUCTION(Branch)

  virtual intptr_t ArgumentCount() const;
  intptr_t InputCount() const;
  Value* InputAt(intptr_t i) const;
  void SetInputAt(intptr_t i, Value* value);
  virtual bool CanDeoptimize() const;

  ComparisonInstr* comparison() const { return comparison_; }
  void set_comparison(ComparisonInstr* value) { comparison_ = value; }

  virtual LocationSummary* locs();
  virtual intptr_t DeoptimizationTarget() const;
  virtual Representation RequiredInputRepresentation(intptr_t i) const;

  // Replace the comparison with another, leaving the branch intact.
  void ReplaceWith(ComparisonInstr* other,
                   ForwardInstructionIterator* ignored) {
    comparison_ = other;
  }

  virtual void PrintTo(BufferFormatter* f) const;
  virtual void PrintToVisualizer(BufferFormatter* f) const;

 private:
  ComparisonInstr* comparison_;

  DISALLOW_COPY_AND_ASSIGN(BranchInstr);
};


template<intptr_t N>
class TemplateDefinition : public Definition {
 public:
  TemplateDefinition<N>() : locs_(NULL) { }

  virtual intptr_t InputCount() const { return N; }
  virtual Value* InputAt(intptr_t i) const { return inputs_[i]; }
  virtual void SetInputAt(intptr_t i, Value* value) {
    ASSERT(value != NULL);
    inputs_[i] = value;
  }

  // Returns a structure describing the location constraints required
  // to emit native code for this definition.
  LocationSummary* locs() {
    if (locs_ == NULL) {
      locs_ = MakeLocationSummary();
    }
    return locs_;
  }

 protected:
  EmbeddedArray<Value*, N> inputs_;

 private:
  friend class BranchInstr;

  LocationSummary* locs_;
};


class ConstantInstr : public TemplateDefinition<0> {
 public:
  explicit ConstantInstr(const Object& value) : value_(value) { }

  DECLARE_INSTRUCTION(Constant)
  virtual RawAbstractType* CompileType() const;

  const Object& value() const { return value_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }

  virtual intptr_t ResultCid() const;

  virtual bool AttributesEqual(Definition* other) const;

 private:
  const Object& value_;

  DISALLOW_COPY_AND_ASSIGN(ConstantInstr);
};


class AssertAssignableInstr : public TemplateDefinition<3> {
 public:
  AssertAssignableInstr(intptr_t token_pos,
                        Value* value,
                        Value* instantiator,
                        Value* instantiator_type_arguments,
                        const AbstractType& dst_type,
                        const String& dst_name)
      : token_pos_(token_pos),
        dst_type_(dst_type),
        dst_name_(dst_name),
        is_eliminated_(false) {
    ASSERT(value != NULL);
    ASSERT(instantiator != NULL);
    ASSERT(instantiator_type_arguments != NULL);
    ASSERT(!dst_type.IsNull());
    ASSERT(!dst_name.IsNull());
    inputs_[0] = value;
    inputs_[1] = instantiator;
    inputs_[2] = instantiator_type_arguments;
  }

  DECLARE_INSTRUCTION(AssertAssignable)
  virtual RawAbstractType* CompileType() const;

  Value* value() const { return inputs_[0]; }
  Value* instantiator() const { return inputs_[1]; }
  Value* instantiator_type_arguments() const { return inputs_[2]; }

  intptr_t token_pos() const { return token_pos_; }
  const AbstractType& dst_type() const { return dst_type_; }
  const String& dst_name() const { return dst_name_; }

  bool is_eliminated() const {
    return is_eliminated_;
  }
  void eliminate() {
    ASSERT(!is_eliminated_);
    is_eliminated_ = true;
  }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const intptr_t token_pos_;
  const AbstractType& dst_type_;
  const String& dst_name_;
  bool is_eliminated_;

  DISALLOW_COPY_AND_ASSIGN(AssertAssignableInstr);
};


class AssertBooleanInstr : public TemplateDefinition<1> {
 public:
  AssertBooleanInstr(intptr_t token_pos, Value* value)
      : token_pos_(token_pos),
        is_eliminated_(false) {
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  DECLARE_INSTRUCTION(AssertBoolean)
  virtual RawAbstractType* CompileType() const;

  intptr_t token_pos() const { return token_pos_; }
  Value* value() const { return inputs_[0]; }

  bool is_eliminated() const {
    return is_eliminated_;
  }
  void eliminate() {
    ASSERT(!is_eliminated_);
    is_eliminated_ = true;
  }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kBoolCid; }

 private:
  const intptr_t token_pos_;
  bool is_eliminated_;

  DISALLOW_COPY_AND_ASSIGN(AssertBooleanInstr);
};


class ArgumentDefinitionTestInstr : public TemplateDefinition<1> {
 public:
  ArgumentDefinitionTestInstr(ArgumentDefinitionTestNode* node,
                              Value* saved_arguments_descriptor)
      : ast_node_(*node) {
    ASSERT(saved_arguments_descriptor != NULL);
    inputs_[0] = saved_arguments_descriptor;
  }

  DECLARE_INSTRUCTION(ArgumentDefinitionTest)
  virtual RawAbstractType* CompileType() const;

  intptr_t token_pos() const { return ast_node_.token_pos(); }
  intptr_t formal_parameter_index() const {
    return ast_node_.formal_parameter_index();
  }
  const String& formal_parameter_name() const {
    return ast_node_.formal_parameter_name();
  }
  Value* saved_arguments_descriptor() const { return inputs_[0]; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kBoolCid; }

 private:
  const ArgumentDefinitionTestNode& ast_node_;

  DISALLOW_COPY_AND_ASSIGN(ArgumentDefinitionTestInstr);
};


// Denotes the current context, normally held in a register.  This is
// a computation, not a value, because it's mutable.
class CurrentContextInstr : public TemplateDefinition<0> {
 public:
  CurrentContextInstr() { }

  DECLARE_INSTRUCTION(CurrentContext)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  DISALLOW_COPY_AND_ASSIGN(CurrentContextInstr);
};


class StoreContextInstr : public TemplateDefinition<1> {
 public:
  explicit StoreContextInstr(Value* value) {
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  DECLARE_INSTRUCTION(StoreContext);
  virtual RawAbstractType* CompileType() const;

  Value* value() const { return inputs_[0]; }

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kIllegalCid; }

 private:
  DISALLOW_COPY_AND_ASSIGN(StoreContextInstr);
};


class ClosureCallInstr : public TemplateDefinition<0> {
 public:
  ClosureCallInstr(ClosureCallNode* node,
                   ZoneGrowableArray<PushArgumentInstr*>* arguments)
      : ast_node_(*node),
        arguments_(arguments) { }

  DECLARE_INSTRUCTION(ClosureCall)
  virtual RawAbstractType* CompileType() const;

  const Array& argument_names() const { return ast_node_.arguments()->names(); }
  intptr_t token_pos() const { return ast_node_.token_pos(); }

  virtual intptr_t ArgumentCount() const { return arguments_->length(); }
  PushArgumentInstr* ArgumentAt(intptr_t index) const {
    return (*arguments_)[index];
  }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const ClosureCallNode& ast_node_;
  ZoneGrowableArray<PushArgumentInstr*>* arguments_;

  DISALLOW_COPY_AND_ASSIGN(ClosureCallInstr);
};


class InstanceCallInstr : public TemplateDefinition<0> {
 public:
  InstanceCallInstr(intptr_t token_pos,
                    const String& function_name,
                    Token::Kind token_kind,
                    ZoneGrowableArray<PushArgumentInstr*>* arguments,
                    const Array& argument_names,
                    intptr_t checked_argument_count)
      : ic_data_(Isolate::Current()->GetICDataForDeoptId(deopt_id())),
        token_pos_(token_pos),
        function_name_(function_name),
        token_kind_(token_kind),
        arguments_(arguments),
        argument_names_(argument_names),
        checked_argument_count_(checked_argument_count) {
    ASSERT(function_name.IsZoneHandle());
    ASSERT(!arguments->is_empty());
    ASSERT(argument_names.IsZoneHandle());
    ASSERT(Token::IsBinaryToken(token_kind) ||
           Token::IsUnaryToken(token_kind) ||
           Token::IsIndexOperator(token_kind) ||
           token_kind == Token::kGET ||
           token_kind == Token::kSET ||
           token_kind == Token::kILLEGAL);
  }

  DECLARE_INSTRUCTION(InstanceCall)
  virtual RawAbstractType* CompileType() const;

  const ICData* ic_data() const { return ic_data_; }
  bool HasICData() const {
    return (ic_data() != NULL) && !ic_data()->IsNull();
  }

  intptr_t token_pos() const { return token_pos_; }
  const String& function_name() const { return function_name_; }
  Token::Kind token_kind() const { return token_kind_; }
  virtual intptr_t ArgumentCount() const { return arguments_->length(); }
  PushArgumentInstr* ArgumentAt(intptr_t index) const {
    return (*arguments_)[index];
  }
  const Array& argument_names() const { return argument_names_; }
  intptr_t checked_argument_count() const { return checked_argument_count_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const ICData* ic_data_;
  const intptr_t token_pos_;
  const String& function_name_;
  const Token::Kind token_kind_;  // Binary op, unary op, kGET or kILLEGAL.
  ZoneGrowableArray<PushArgumentInstr*>* const arguments_;
  const Array& argument_names_;
  const intptr_t checked_argument_count_;

  DISALLOW_COPY_AND_ASSIGN(InstanceCallInstr);
};


class PolymorphicInstanceCallInstr : public TemplateDefinition<0> {
 public:
  PolymorphicInstanceCallInstr(InstanceCallInstr* instance_call,
                               const ICData& ic_data,
                               bool with_checks)
      : instance_call_(instance_call),
        ic_data_(ic_data),
        with_checks_(with_checks) {
    ASSERT(instance_call_ != NULL);
  }

  InstanceCallInstr* instance_call() const { return instance_call_; }
  bool with_checks() const { return with_checks_; }

  virtual intptr_t ArgumentCount() const {
    return instance_call()->ArgumentCount();
  }

  DECLARE_INSTRUCTION(PolymorphicInstanceCall)
  virtual RawAbstractType* CompileType() const;

  const ICData& ic_data() const { return ic_data_; }

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

  virtual void PrintTo(BufferFormatter* f) const;

 private:
  InstanceCallInstr* instance_call_;
  const ICData& ic_data_;
  const bool with_checks_;

  DISALLOW_COPY_AND_ASSIGN(PolymorphicInstanceCallInstr);
};


class ComparisonInstr : public TemplateDefinition<2> {
 public:
  ComparisonInstr(Token::Kind kind, Value* left, Value* right) : kind_(kind) {
    ASSERT(left != NULL);
    ASSERT(right != NULL);
    inputs_[0] = left;
    inputs_[1] = right;
  }

  Value* left() const { return inputs_[0]; }
  Value* right() const { return inputs_[1]; }

  virtual ComparisonInstr* AsComparison() { return this; }

  Token::Kind kind() const { return kind_; }

  virtual void EmitBranchCode(FlowGraphCompiler* compiler,
                              BranchInstr* branch) = 0;

 private:
  Token::Kind kind_;
};


// Inlined functions from class BranchInstr that forward to their comparison.
inline intptr_t BranchInstr::ArgumentCount() const {
  return comparison()->ArgumentCount();
}


inline intptr_t BranchInstr::InputCount() const {
  return comparison()->InputCount();
}


inline Value* BranchInstr::InputAt(intptr_t i) const {
  return comparison()->InputAt(i);
}


inline void BranchInstr::SetInputAt(intptr_t i, Value* value) {
  comparison()->SetInputAt(i, value);
}


inline bool BranchInstr::CanDeoptimize() const {
  return comparison()->CanDeoptimize();
}


inline LocationSummary* BranchInstr::locs() {
  if (comparison()->locs_ == NULL) {
    LocationSummary* summary = comparison()->MakeLocationSummary();
    // Branches don't produce a result.
    summary->set_out(Location::NoLocation());
    comparison()->locs_ = summary;
  }
  return comparison()->locs_;
}


inline intptr_t BranchInstr::DeoptimizationTarget() const {
  return comparison()->DeoptimizationTarget();
}


inline Representation BranchInstr::RequiredInputRepresentation(
    intptr_t i) const {
  return comparison()->RequiredInputRepresentation(i);
}


class StrictCompareInstr : public ComparisonInstr {
 public:
  StrictCompareInstr(Token::Kind kind, Value* left, Value* right)
      : ComparisonInstr(kind, left, right) {
    ASSERT((kind == Token::kEQ_STRICT) || (kind == Token::kNE_STRICT));
  }

  DECLARE_INSTRUCTION(StrictCompare)
  virtual RawAbstractType* CompileType() const;

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }

  virtual Definition* Canonicalize();

  virtual intptr_t ResultCid() const { return kBoolCid; }

  virtual void EmitBranchCode(FlowGraphCompiler* compiler,
                              BranchInstr* branch);

 private:
  DISALLOW_COPY_AND_ASSIGN(StrictCompareInstr);
};


class EqualityCompareInstr : public ComparisonInstr {
 public:
  EqualityCompareInstr(intptr_t token_pos,
                       Token::Kind kind,
                       Value* left,
                       Value* right)
      : ComparisonInstr(kind, left, right),
        ic_data_(Isolate::Current()->GetICDataForDeoptId(deopt_id())),
        token_pos_(token_pos),
        receiver_class_id_(kIllegalCid) {
    ASSERT((kind == Token::kEQ) || (kind == Token::kNE));
  }

  DECLARE_INSTRUCTION(EqualityCompare)
  virtual RawAbstractType* CompileType() const;

  const ICData* ic_data() const { return ic_data_; }
  bool HasICData() const {
    return (ic_data() != NULL) && !ic_data()->IsNull();
  }

  intptr_t token_pos() const { return token_pos_; }

  // Receiver class id is computed from collected ICData.
  void set_receiver_class_id(intptr_t value) { receiver_class_id_ = value; }
  intptr_t receiver_class_id() const { return receiver_class_id_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const {
    return (receiver_class_id() != kDoubleCid)
        && (receiver_class_id() != kSmiCid);
  }

  virtual intptr_t ResultCid() const;

  virtual void EmitBranchCode(FlowGraphCompiler* compiler,
                              BranchInstr* branch);

  virtual intptr_t DeoptimizationTarget() const {
    return GetDeoptId();
  }

  virtual Representation RequiredInputRepresentation(intptr_t idx) const {
    ASSERT((idx == 0) || (idx == 1));
    return (receiver_class_id() == kDoubleCid) ? kUnboxedDouble : kTagged;
  }

 private:
  const ICData* ic_data_;
  const intptr_t token_pos_;
  intptr_t receiver_class_id_;  // Set by optimizer.

  DISALLOW_COPY_AND_ASSIGN(EqualityCompareInstr);
};


class RelationalOpInstr : public ComparisonInstr {
 public:
  RelationalOpInstr(intptr_t token_pos,
                    Token::Kind kind,
                    Value* left,
                    Value* right)
      : ComparisonInstr(kind, left, right),
        ic_data_(Isolate::Current()->GetICDataForDeoptId(deopt_id())),
        token_pos_(token_pos),
        operands_class_id_(kIllegalCid) {
    ASSERT(Token::IsRelationalOperator(kind));
  }

  DECLARE_INSTRUCTION(RelationalOp)
  virtual RawAbstractType* CompileType() const;

  const ICData* ic_data() const { return ic_data_; }
  bool HasICData() const {
    return (ic_data() != NULL) && !ic_data()->IsNull();
  }

  intptr_t token_pos() const { return token_pos_; }

  // TODO(srdjan): instead of class-id pass an enum that can differentiate
  // between boxed and unboxed doubles and integers.
  void set_operands_class_id(intptr_t value) {
    operands_class_id_ = value;
  }

  intptr_t operands_class_id() const { return operands_class_id_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const {
    return (operands_class_id() != kDoubleCid)
        && (operands_class_id() != kSmiCid);
  }

  virtual intptr_t ResultCid() const;

  virtual void EmitBranchCode(FlowGraphCompiler* compiler,
                              BranchInstr* branch);


  virtual intptr_t DeoptimizationTarget() const {
    return GetDeoptId();
  }

  virtual Representation RequiredInputRepresentation(intptr_t idx) const {
    ASSERT((idx == 0) || (idx == 1));
    return (operands_class_id() == kDoubleCid) ? kUnboxedDouble : kTagged;
  }

 private:
  const ICData* ic_data_;
  const intptr_t token_pos_;
  intptr_t operands_class_id_;  // class id of both operands.

  DISALLOW_COPY_AND_ASSIGN(RelationalOpInstr);
};


class StaticCallInstr : public TemplateDefinition<0> {
 public:
  StaticCallInstr(intptr_t token_pos,
                  const Function& function,
                  const Array& argument_names,
                  ZoneGrowableArray<PushArgumentInstr*>* arguments)
      : token_pos_(token_pos),
        function_(function),
        argument_names_(argument_names),
        arguments_(arguments),
        recognized_(MethodRecognizer::kUnknown) {
    ASSERT(function.IsZoneHandle());
    ASSERT(argument_names.IsZoneHandle());
  }

  DECLARE_INSTRUCTION(StaticCall)
  virtual RawAbstractType* CompileType() const;

  // Accessors forwarded to the AST node.
  const Function& function() const { return function_; }
  const Array& argument_names() const { return argument_names_; }
  intptr_t token_pos() const { return token_pos_; }

  virtual intptr_t ArgumentCount() const { return arguments_->length(); }
  PushArgumentInstr* ArgumentAt(intptr_t index) const {
    return (*arguments_)[index];
  }

  MethodRecognizer::Kind recognized() const { return recognized_; }
  void set_recognized(MethodRecognizer::Kind kind) { recognized_ = kind; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const intptr_t token_pos_;
  const Function& function_;
  const Array& argument_names_;
  ZoneGrowableArray<PushArgumentInstr*>* arguments_;
  MethodRecognizer::Kind recognized_;

  DISALLOW_COPY_AND_ASSIGN(StaticCallInstr);
};


class LoadLocalInstr : public TemplateDefinition<0> {
 public:
  LoadLocalInstr(const LocalVariable& local, intptr_t context_level)
      : local_(local),
        context_level_(context_level) { }

  DECLARE_INSTRUCTION(LoadLocal)
  virtual RawAbstractType* CompileType() const;

  const LocalVariable& local() const { return local_; }
  intptr_t context_level() const { return context_level_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const LocalVariable& local_;
  const intptr_t context_level_;

  DISALLOW_COPY_AND_ASSIGN(LoadLocalInstr);
};


class StoreLocalInstr : public TemplateDefinition<1> {
 public:
  StoreLocalInstr(const LocalVariable& local,
                  Value* value,
                  intptr_t context_level)
      : local_(local),
        context_level_(context_level) {
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  DECLARE_INSTRUCTION(StoreLocal)
  virtual RawAbstractType* CompileType() const;

  const LocalVariable& local() const { return local_; }
  Value* value() const { return inputs_[0]; }
  intptr_t context_level() const { return context_level_; }

  virtual void RecordAssignedVars(BitVector* assigned_vars,
                                  intptr_t fixed_parameter_count);

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const LocalVariable& local_;
  const intptr_t context_level_;

  DISALLOW_COPY_AND_ASSIGN(StoreLocalInstr);
};


class NativeCallInstr : public TemplateDefinition<0> {
 public:
  explicit NativeCallInstr(NativeBodyNode* node)
      : ast_node_(*node) {}

  DECLARE_INSTRUCTION(NativeCall)
  virtual RawAbstractType* CompileType() const;

  intptr_t token_pos() const { return ast_node_.token_pos(); }

  const String& native_name() const {
    return ast_node_.native_c_function_name();
  }

  NativeFunction native_c_function() const {
    return ast_node_.native_c_function();
  }

  intptr_t argument_count() const { return ast_node_.argument_count(); }

  bool has_optional_parameters() const {
    return ast_node_.has_optional_parameters();
  }

  bool is_native_instance_closure() const {
    return ast_node_.is_native_instance_closure();
  }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const NativeBodyNode& ast_node_;

  DISALLOW_COPY_AND_ASSIGN(NativeCallInstr);
};


class LoadInstanceFieldInstr : public TemplateDefinition<1> {
 public:
  LoadInstanceFieldInstr(const Field& field, Value* instance) : field_(field) {
    ASSERT(instance != NULL);
    inputs_[0] = instance;
  }

  DECLARE_INSTRUCTION(LoadInstanceField)
  virtual RawAbstractType* CompileType() const;

  const Field& field() const { return field_; }
  Value* instance() const { return inputs_[0]; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const Field& field_;

  DISALLOW_COPY_AND_ASSIGN(LoadInstanceFieldInstr);
};


class StoreInstanceFieldInstr : public TemplateDefinition<2> {
 public:
  StoreInstanceFieldInstr(const Field& field, Value* instance, Value* value)
      : field_(field) {
    ASSERT(instance != NULL);
    ASSERT(value != NULL);
    inputs_[0] = instance;
    inputs_[1] = value;
  }

  DECLARE_INSTRUCTION(StoreInstanceField)
  virtual RawAbstractType* CompileType() const;

  const Field& field() const { return field_; }

  Value* instance() const { return inputs_[0]; }
  Value* value() const { return inputs_[1]; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const Field& field_;

  DISALLOW_COPY_AND_ASSIGN(StoreInstanceFieldInstr);
};


class LoadStaticFieldInstr : public TemplateDefinition<0> {
 public:
  explicit LoadStaticFieldInstr(const Field& field) : field_(field) {}

  DECLARE_INSTRUCTION(LoadStaticField);
  virtual RawAbstractType* CompileType() const;

  const Field& field() const { return field_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const Field& field_;

  DISALLOW_COPY_AND_ASSIGN(LoadStaticFieldInstr);
};


class StoreStaticFieldInstr : public TemplateDefinition<1> {
 public:
  StoreStaticFieldInstr(const Field& field, Value* value)
      : field_(field) {
    ASSERT(field.IsZoneHandle());
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  DECLARE_INSTRUCTION(StoreStaticField);
  virtual RawAbstractType* CompileType() const;

  const Field& field() const { return field_; }
  Value* value() const { return inputs_[0]; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const Field& field_;

  DISALLOW_COPY_AND_ASSIGN(StoreStaticFieldInstr);
};


class LoadIndexedInstr : public TemplateDefinition<2> {
 public:
  LoadIndexedInstr(Value* array, Value* index, intptr_t receiver_type)
      : receiver_type_(receiver_type) {
    ASSERT(array != NULL);
    ASSERT(index != NULL);
    inputs_[0] = array;
    inputs_[1] = index;
  }

  DECLARE_INSTRUCTION(LoadIndexed)
  virtual RawAbstractType* CompileType() const;

  Value* array() const { return inputs_[0]; }
  Value* index() const { return inputs_[1]; }

  intptr_t receiver_type() const { return receiver_type_; }

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  intptr_t receiver_type_;

  DISALLOW_COPY_AND_ASSIGN(LoadIndexedInstr);
};


class StoreIndexedInstr : public TemplateDefinition<3> {
 public:
  StoreIndexedInstr(Value* array,
                    Value* index,
                    Value* value,
                    intptr_t receiver_type)
        : receiver_type_(receiver_type) {
    ASSERT(array != NULL);
    ASSERT(index != NULL);
    ASSERT(value != NULL);
    inputs_[0] = array;
    inputs_[1] = index;
    inputs_[2] = value;
  }

  DECLARE_INSTRUCTION(StoreIndexed)
  virtual RawAbstractType* CompileType() const;

  Value* array() const { return inputs_[0]; }
  Value* index() const { return inputs_[1]; }
  Value* value() const { return inputs_[2]; }

  intptr_t receiver_type() const { return receiver_type_; }

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  intptr_t receiver_type_;

  DISALLOW_COPY_AND_ASSIGN(StoreIndexedInstr);
};


// Note overrideable, built-in: value? false : true.
class BooleanNegateInstr : public TemplateDefinition<1> {
 public:
  explicit BooleanNegateInstr(Value* value) {
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  DECLARE_INSTRUCTION(BooleanNegate)
  virtual RawAbstractType* CompileType() const;

  Value* value() const { return inputs_[0]; }

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kBoolCid; }

 private:
  DISALLOW_COPY_AND_ASSIGN(BooleanNegateInstr);
};


class InstanceOfInstr : public TemplateDefinition<3> {
 public:
  InstanceOfInstr(intptr_t token_pos,
                  Value* value,
                  Value* instantiator,
                  Value* instantiator_type_arguments,
                  const AbstractType& type,
                  bool negate_result)
      : token_pos_(token_pos),
        type_(type),
        negate_result_(negate_result) {
    ASSERT(value != NULL);
    ASSERT(instantiator != NULL);
    ASSERT(instantiator_type_arguments != NULL);
    ASSERT(!type.IsNull());
    inputs_[0] = value;
    inputs_[1] = instantiator;
    inputs_[2] = instantiator_type_arguments;
  }

  DECLARE_INSTRUCTION(InstanceOf)
  virtual RawAbstractType* CompileType() const;

  Value* value() const { return inputs_[0]; }
  Value* instantiator() const { return inputs_[1]; }
  Value* instantiator_type_arguments() const { return inputs_[2]; }

  bool negate_result() const { return negate_result_; }
  const AbstractType& type() const { return type_; }
  intptr_t token_pos() const { return token_pos_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kBoolCid; }

 private:
  const intptr_t token_pos_;
  Value* value_;
  Value* instantiator_;
  Value* type_arguments_;
  const AbstractType& type_;
  const bool negate_result_;

  DISALLOW_COPY_AND_ASSIGN(InstanceOfInstr);
};


class AllocateObjectInstr : public TemplateDefinition<0> {
 public:
  AllocateObjectInstr(ConstructorCallNode* node,
                      ZoneGrowableArray<PushArgumentInstr*>* arguments)
      : ast_node_(*node), arguments_(arguments) {
    // Either no arguments or one type-argument and one instantiator.
    ASSERT(arguments->is_empty() || (arguments->length() == 2));
  }

  DECLARE_INSTRUCTION(AllocateObject)
  virtual RawAbstractType* CompileType() const;

  virtual intptr_t ArgumentCount() const { return arguments_->length(); }
  PushArgumentInstr* ArgumentAt(intptr_t index) const {
    return (*arguments_)[index];
  }

  const Function& constructor() const { return ast_node_.constructor(); }
  intptr_t token_pos() const { return ast_node_.token_pos(); }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const ConstructorCallNode& ast_node_;
  ZoneGrowableArray<PushArgumentInstr*>* const arguments_;

  DISALLOW_COPY_AND_ASSIGN(AllocateObjectInstr);
};


class AllocateObjectWithBoundsCheckInstr : public TemplateDefinition<2> {
 public:
  AllocateObjectWithBoundsCheckInstr(ConstructorCallNode* node,
                                     Value* type_arguments,
                                     Value* instantiator)
      : ast_node_(*node) {
    ASSERT(type_arguments != NULL);
    ASSERT(instantiator != NULL);
    inputs_[0] = type_arguments;
    inputs_[1] = instantiator;
  }

  DECLARE_INSTRUCTION(AllocateObjectWithBoundsCheck)
  virtual RawAbstractType* CompileType() const;

  const Function& constructor() const { return ast_node_.constructor(); }
  intptr_t token_pos() const { return ast_node_.token_pos(); }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const ConstructorCallNode& ast_node_;

  DISALLOW_COPY_AND_ASSIGN(AllocateObjectWithBoundsCheckInstr);
};


class CreateArrayInstr : public TemplateDefinition<1> {
 public:
  CreateArrayInstr(intptr_t token_pos,
                   ZoneGrowableArray<PushArgumentInstr*>* arguments,
                   const AbstractType& type,
                   Value* element_type)
      : token_pos_(token_pos),
        arguments_(arguments),
        type_(type) {
#if defined(DEBUG)
    for (int i = 0; i < ArgumentCount(); ++i) {
      ASSERT(ArgumentAt(i) != NULL);
    }
    ASSERT(element_type != NULL);
    ASSERT(type_.IsZoneHandle());
    ASSERT(!type_.IsNull());
    ASSERT(type_.IsFinalized());
#endif
    inputs_[0] = element_type;
  }

  DECLARE_INSTRUCTION(CreateArray)
  virtual RawAbstractType* CompileType() const;

  virtual intptr_t ArgumentCount() const { return arguments_->length(); }

  intptr_t token_pos() const { return token_pos_; }
  PushArgumentInstr* ArgumentAt(intptr_t i) const { return (*arguments_)[i]; }
  const AbstractType& type() const { return type_; }
  Value* element_type() const { return inputs_[0]; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const intptr_t token_pos_;
  ZoneGrowableArray<PushArgumentInstr*>* const arguments_;
  const AbstractType& type_;

  DISALLOW_COPY_AND_ASSIGN(CreateArrayInstr);
};


class CreateClosureInstr : public TemplateDefinition<0> {
 public:
  CreateClosureInstr(ClosureNode* node,
                     ZoneGrowableArray<PushArgumentInstr*>* arguments)
      : ast_node_(*node),
        arguments_(arguments) { }

  DECLARE_INSTRUCTION(CreateClosure)
  virtual RawAbstractType* CompileType() const;

  intptr_t token_pos() const { return ast_node_.token_pos(); }
  const Function& function() const { return ast_node_.function(); }

  virtual intptr_t ArgumentCount() const { return arguments_->length(); }
  PushArgumentInstr* ArgumentAt(intptr_t index) const {
    return (*arguments_)[index];
  }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const ClosureNode& ast_node_;
  ZoneGrowableArray<PushArgumentInstr*>* arguments_;

  DISALLOW_COPY_AND_ASSIGN(CreateClosureInstr);
};


class LoadVMFieldInstr : public TemplateDefinition<1> {
 public:
  LoadVMFieldInstr(Value* value,
                   intptr_t offset_in_bytes,
                   const AbstractType& type)
      : offset_in_bytes_(offset_in_bytes),
        type_(type),
        result_cid_(kDynamicCid) {
    ASSERT(value != NULL);
    ASSERT(type.IsZoneHandle());  // May be null if field is not an instance.
    inputs_[0] = value;
  }

  DECLARE_INSTRUCTION(LoadVMField)
  virtual RawAbstractType* CompileType() const;

  Value* value() const { return inputs_[0]; }
  intptr_t offset_in_bytes() const { return offset_in_bytes_; }
  const AbstractType& type() const { return type_; }
  void set_result_cid(intptr_t value) { result_cid_ = value; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return result_cid_; }

 private:
  const intptr_t offset_in_bytes_;
  const AbstractType& type_;
  intptr_t result_cid_;

  DISALLOW_COPY_AND_ASSIGN(LoadVMFieldInstr);
};


class StoreVMFieldInstr : public TemplateDefinition<2> {
 public:
  StoreVMFieldInstr(Value* dest,
                    intptr_t offset_in_bytes,
                    Value* value,
                    const AbstractType& type)
      : offset_in_bytes_(offset_in_bytes), type_(type) {
    ASSERT(value != NULL);
    ASSERT(dest != NULL);
    ASSERT(type.IsZoneHandle());  // May be null if field is not an instance.
    inputs_[0] = value;
    inputs_[1] = dest;
  }

  DECLARE_INSTRUCTION(StoreVMField)
  virtual RawAbstractType* CompileType() const;

  Value* value() const { return inputs_[0]; }
  Value* dest() const { return inputs_[1]; }
  intptr_t offset_in_bytes() const { return offset_in_bytes_; }
  const AbstractType& type() const { return type_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const intptr_t offset_in_bytes_;
  const AbstractType& type_;

  DISALLOW_COPY_AND_ASSIGN(StoreVMFieldInstr);
};


class InstantiateTypeArgumentsInstr : public TemplateDefinition<1> {
 public:
  InstantiateTypeArgumentsInstr(intptr_t token_pos,
                                const AbstractTypeArguments& type_arguments,
                                Value* instantiator)
      : token_pos_(token_pos),
        type_arguments_(type_arguments) {
    ASSERT(type_arguments.IsZoneHandle());
    ASSERT(instantiator != NULL);
    inputs_[0] = instantiator;
  }

  DECLARE_INSTRUCTION(InstantiateTypeArguments)
  virtual RawAbstractType* CompileType() const;

  Value* instantiator() const { return inputs_[0]; }
  const AbstractTypeArguments& type_arguments() const {
    return type_arguments_;
  }
  intptr_t token_pos() const { return token_pos_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const intptr_t token_pos_;
  const AbstractTypeArguments& type_arguments_;

  DISALLOW_COPY_AND_ASSIGN(InstantiateTypeArgumentsInstr);
};


class ExtractConstructorTypeArgumentsInstr : public TemplateDefinition<1> {
 public:
  ExtractConstructorTypeArgumentsInstr(
      intptr_t token_pos,
      const AbstractTypeArguments& type_arguments,
      Value* instantiator)
      : token_pos_(token_pos),
        type_arguments_(type_arguments) {
    ASSERT(instantiator != NULL);
    inputs_[0] = instantiator;
  }

  DECLARE_INSTRUCTION(ExtractConstructorTypeArguments)
  virtual RawAbstractType* CompileType() const;

  Value* instantiator() const { return inputs_[0]; }
  const AbstractTypeArguments& type_arguments() const {
    return type_arguments_;
  }
  intptr_t token_pos() const { return token_pos_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const intptr_t token_pos_;
  const AbstractTypeArguments& type_arguments_;

  DISALLOW_COPY_AND_ASSIGN(ExtractConstructorTypeArgumentsInstr);
};


class ExtractConstructorInstantiatorInstr : public TemplateDefinition<1> {
 public:
  ExtractConstructorInstantiatorInstr(ConstructorCallNode* ast_node,
                                      Value* instantiator)
      : ast_node_(*ast_node) {
    ASSERT(instantiator != NULL);
    inputs_[0] = instantiator;
  }

  DECLARE_INSTRUCTION(ExtractConstructorInstantiator)
  virtual RawAbstractType* CompileType() const;

  Value* instantiator() const { return inputs_[0]; }
  const AbstractTypeArguments& type_arguments() const {
    return ast_node_.type_arguments();
  }
  const Function& constructor() const { return ast_node_.constructor(); }
  intptr_t token_pos() const { return ast_node_.token_pos(); }

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const ConstructorCallNode& ast_node_;

  DISALLOW_COPY_AND_ASSIGN(ExtractConstructorInstantiatorInstr);
};


class AllocateContextInstr : public TemplateDefinition<0> {
 public:
  AllocateContextInstr(intptr_t token_pos,
                       intptr_t num_context_variables)
      : token_pos_(token_pos),
        num_context_variables_(num_context_variables) {}

  DECLARE_INSTRUCTION(AllocateContext);
  virtual RawAbstractType* CompileType() const;

  intptr_t token_pos() const { return token_pos_; }
  intptr_t num_context_variables() const { return num_context_variables_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kDynamicCid; }

 private:
  const intptr_t token_pos_;
  const intptr_t num_context_variables_;

  DISALLOW_COPY_AND_ASSIGN(AllocateContextInstr);
};


class ChainContextInstr : public TemplateDefinition<1> {
 public:
  explicit ChainContextInstr(Value* context_value) {
    ASSERT(context_value != NULL);
    inputs_[0] = context_value;
  }

  DECLARE_INSTRUCTION(ChainContext)
  virtual RawAbstractType* CompileType() const;

  Value* context_value() const { return inputs_[0]; }

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kIllegalCid; }

 private:
  DISALLOW_COPY_AND_ASSIGN(ChainContextInstr);
};


class CloneContextInstr : public TemplateDefinition<1> {
 public:
  CloneContextInstr(intptr_t token_pos, Value* context_value)
      : token_pos_(token_pos) {
    ASSERT(context_value != NULL);
    inputs_[0] = context_value;
  }

  intptr_t token_pos() const { return token_pos_; }
  Value* context_value() const { return inputs_[0]; }

  DECLARE_INSTRUCTION(CloneContext)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kIllegalCid; }

 private:
  const intptr_t token_pos_;

  DISALLOW_COPY_AND_ASSIGN(CloneContextInstr);
};


class CatchEntryInstr : public TemplateDefinition<0> {
 public:
  CatchEntryInstr(const LocalVariable& exception_var,
                  const LocalVariable& stacktrace_var)
      : exception_var_(exception_var), stacktrace_var_(stacktrace_var) {}

  const LocalVariable& exception_var() const { return exception_var_; }
  const LocalVariable& stacktrace_var() const { return stacktrace_var_; }

  DECLARE_INSTRUCTION(CatchEntry)
  virtual RawAbstractType* CompileType() const;

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kIllegalCid; }

 private:
  const LocalVariable& exception_var_;
  const LocalVariable& stacktrace_var_;

  DISALLOW_COPY_AND_ASSIGN(CatchEntryInstr);
};


class CheckEitherNonSmiInstr : public TemplateDefinition<2> {
 public:
  CheckEitherNonSmiInstr(Value* left,
                         Value* right,
                         InstanceCallInstr* instance_call) {
    ASSERT(left != NULL);
    ASSERT(right != NULL);
    inputs_[0] = left;
    inputs_[1] = right;
    deopt_id_ = instance_call->deopt_id();
  }

  DECLARE_INSTRUCTION(CheckEitherNonSmi)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kIllegalCid; }

  virtual bool AttributesEqual(Definition* other) const { return true; }

  virtual bool HasSideEffect() const { return false; }

  Value* left() const { return inputs_[0]; }

  Value* right() const { return inputs_[1]; }

  virtual Definition* Canonicalize();

 private:
  DISALLOW_COPY_AND_ASSIGN(CheckEitherNonSmiInstr);
};


class BoxDoubleInstr : public TemplateDefinition<1> {
 public:
  BoxDoubleInstr(Value* value, InstanceCallInstr* instance_call)
      : token_pos_((instance_call != NULL) ? instance_call->token_pos() : 0) {
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  Value* value() const { return inputs_[0]; }

  intptr_t token_pos() const { return token_pos_; }

  virtual bool CanDeoptimize() const { return false; }
  virtual bool HasSideEffect() const { return false; }
  virtual bool AttributesEqual(Definition* other) const { return true; }

  virtual intptr_t ResultCid() const;

  virtual Representation RequiredInputRepresentation(intptr_t idx) const {
    ASSERT(idx == 0);
    return kUnboxedDouble;
  }

  DECLARE_INSTRUCTION(BoxDouble)
  virtual RawAbstractType* CompileType() const;

 private:
  const intptr_t token_pos_;

  DISALLOW_COPY_AND_ASSIGN(BoxDoubleInstr);
};


class UnboxDoubleInstr : public TemplateDefinition<1> {
 public:
  UnboxDoubleInstr(Value* value, intptr_t deopt_id) {
    ASSERT(value != NULL);
    inputs_[0] = value;
    deopt_id_ = deopt_id;
  }

  Value* value() const { return inputs_[0]; }

  virtual bool CanDeoptimize() const {
    return value()->ResultCid() != kDoubleCid;
  }

  // The output is not an instance but when it is boxed it becomes double.
  virtual intptr_t ResultCid() const { return kDoubleCid; }

  virtual Representation representation() const {
    return kUnboxedDouble;
  }

  virtual bool HasSideEffect() const { return false; }
  virtual bool AttributesEqual(Definition* other) const { return true; }

  DECLARE_INSTRUCTION(UnboxDouble)
  virtual RawAbstractType* CompileType() const;

 private:
  DISALLOW_COPY_AND_ASSIGN(UnboxDoubleInstr);
};


class UnboxedDoubleBinaryOpInstr : public TemplateDefinition<2> {
 public:
  UnboxedDoubleBinaryOpInstr(Token::Kind op_kind,
                             Value* left,
                             Value* right,
                             InstanceCallInstr* instance_call)
      : op_kind_(op_kind) {
    ASSERT(left != NULL);
    ASSERT(right != NULL);
    inputs_[0] = left;
    inputs_[1] = right;
    deopt_id_ = instance_call->deopt_id();
  }

  Value* left() const { return inputs_[0]; }
  Value* right() const { return inputs_[1]; }

  Token::Kind op_kind() const { return op_kind_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  virtual bool CanDeoptimize() const { return false; }
  virtual bool HasSideEffect() const { return false; }

  virtual bool AttributesEqual(Definition* other) const {
    return op_kind() == other->AsUnboxedDoubleBinaryOp()->op_kind();
  }

  // The output is not an instance but when it is boxed it becomes double.
  virtual intptr_t ResultCid() const { return kDoubleCid; }

  virtual Representation representation() const {
    return kUnboxedDouble;
  }

  virtual Representation RequiredInputRepresentation(intptr_t idx) const {
    ASSERT((idx == 0) || (idx == 1));
    return kUnboxedDouble;
  }

  virtual intptr_t DeoptimizationTarget() const {
    // Direct access since this instuction cannot deoptimize, and the deopt-id
    // was inherited from another instuction that could deoptimize.
    return deopt_id_;
  }

  DECLARE_INSTRUCTION(UnboxedDoubleBinaryOp)
  virtual RawAbstractType* CompileType() const;

 private:
  const Token::Kind op_kind_;

  DISALLOW_COPY_AND_ASSIGN(UnboxedDoubleBinaryOpInstr);
};


class BinarySmiOpInstr : public TemplateDefinition<2> {
 public:
  BinarySmiOpInstr(Token::Kind op_kind,
                   InstanceCallInstr* instance_call,
                   Value* left,
                   Value* right)
      : op_kind_(op_kind),
        instance_call_(instance_call) {
    ASSERT(left != NULL);
    ASSERT(right != NULL);
    inputs_[0] = left;
    inputs_[1] = right;
  }

  Value* left() const { return inputs_[0]; }
  Value* right() const { return inputs_[1]; }

  Token::Kind op_kind() const { return op_kind_; }

  InstanceCallInstr* instance_call() const { return instance_call_; }

  const ICData* ic_data() const { return instance_call()->ic_data(); }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  DECLARE_INSTRUCTION(BinarySmiOp)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const;

  virtual intptr_t ResultCid() const;

 private:
  const Token::Kind op_kind_;
  InstanceCallInstr* instance_call_;

  DISALLOW_COPY_AND_ASSIGN(BinarySmiOpInstr);
};


class BinaryMintOpInstr : public TemplateDefinition<2> {
 public:
  BinaryMintOpInstr(Token::Kind op_kind,
                    InstanceCallInstr* instance_call,
                    Value* left,
                    Value* right)
      : op_kind_(op_kind),
        instance_call_(instance_call) {
    ASSERT(left != NULL);
    ASSERT(right != NULL);
    inputs_[0] = left;
    inputs_[1] = right;
  }

  Value* left() const { return inputs_[0]; }
  Value* right() const { return inputs_[1]; }

  Token::Kind op_kind() const { return op_kind_; }

  InstanceCallInstr* instance_call() const { return instance_call_; }

  const ICData* ic_data() const { return instance_call()->ic_data(); }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  DECLARE_INSTRUCTION(BinaryMintOp)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const;

 private:
  const Token::Kind op_kind_;
  InstanceCallInstr* instance_call_;

  DISALLOW_COPY_AND_ASSIGN(BinaryMintOpInstr);
};


// Handles both Smi operations: BIT_OR and NEGATE.
class UnarySmiOpInstr : public TemplateDefinition<1> {
 public:
  UnarySmiOpInstr(Token::Kind op_kind,
                  InstanceCallInstr* instance_call,
                  Value* value)
      : op_kind_(op_kind), instance_call_(instance_call) {
    ASSERT((op_kind == Token::kNEGATE) || (op_kind == Token::kBIT_NOT));
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  Value* value() const { return inputs_[0]; }
  Token::Kind op_kind() const { return op_kind_; }

  InstanceCallInstr* instance_call() const { return instance_call_; }

  virtual void PrintOperandsTo(BufferFormatter* f) const;

  DECLARE_INSTRUCTION(UnarySmiOp)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return op_kind() == Token::kNEGATE; }
  virtual intptr_t ResultCid() const { return kSmiCid; }

 private:
  const Token::Kind op_kind_;
  InstanceCallInstr* instance_call_;

  DISALLOW_COPY_AND_ASSIGN(UnarySmiOpInstr);
};


// Handles non-Smi NEGATE operations
class NumberNegateInstr : public TemplateDefinition<1> {
 public:
  NumberNegateInstr(InstanceCallInstr* instance_call, Value* value)
      : instance_call_(instance_call) {
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  Value* value() const { return inputs_[0]; }

  InstanceCallInstr* instance_call() const { return instance_call_; }

  const ICData* ic_data() const { return instance_call()->ic_data(); }

  DECLARE_INSTRUCTION(NumberNegate)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kDoubleCid; }

 private:
  InstanceCallInstr* instance_call_;

  DISALLOW_COPY_AND_ASSIGN(NumberNegateInstr);
};


class CheckStackOverflowInstr : public TemplateDefinition<0> {
 public:
  explicit CheckStackOverflowInstr(intptr_t token_pos)
      : token_pos_(token_pos) {}

  intptr_t token_pos() const { return token_pos_; }

  DECLARE_INSTRUCTION(CheckStackOverflow)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return false; }
  virtual intptr_t ResultCid() const { return kIllegalCid; }

 private:
  const intptr_t token_pos_;

  DISALLOW_COPY_AND_ASSIGN(CheckStackOverflowInstr);
};


class DoubleToDoubleInstr : public TemplateDefinition<1> {
 public:
  DoubleToDoubleInstr(Value* value, InstanceCallInstr* instance_call)
      : instance_call_(instance_call) {
    ASSERT(value != NULL);
    inputs_[0] = value;
  }

  Value* value() const { return inputs_[0]; }

  InstanceCallInstr* instance_call() const { return instance_call_; }

  DECLARE_INSTRUCTION(DoubleToDouble)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kDoubleCid; }

 private:
  InstanceCallInstr* instance_call_;

  DISALLOW_COPY_AND_ASSIGN(DoubleToDoubleInstr);
};


class SmiToDoubleInstr : public TemplateDefinition<0> {
 public:
  explicit SmiToDoubleInstr(InstanceCallInstr* instance_call)
      : instance_call_(instance_call) { }

  InstanceCallInstr* instance_call() const { return instance_call_; }

  DECLARE_INSTRUCTION(SmiToDouble)
  virtual RawAbstractType* CompileType() const;

  virtual intptr_t ArgumentCount() const { return 1; }

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kDoubleCid; }

 private:
  InstanceCallInstr* instance_call_;

  DISALLOW_COPY_AND_ASSIGN(SmiToDoubleInstr);
};


class CheckClassInstr : public TemplateDefinition<1> {
 public:
  CheckClassInstr(Value* value,
                  InstanceCallInstr* instance_call,
                  const ICData& unary_checks)
      : unary_checks_(unary_checks) {
    ASSERT(value != NULL);
    inputs_[0] = value;
    deopt_id_ = instance_call->deopt_id();
  }

  DECLARE_INSTRUCTION(CheckClass)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kIllegalCid; }

  virtual bool AttributesEqual(Definition* other) const;

  virtual bool HasSideEffect() const { return false; }

  Value* value() const { return inputs_[0]; }

  const ICData& unary_checks() const { return unary_checks_; }

  virtual Definition* Canonicalize();

  virtual void PrintOperandsTo(BufferFormatter* f) const;

 private:
  const ICData& unary_checks_;

  DISALLOW_COPY_AND_ASSIGN(CheckClassInstr);
};


class CheckSmiInstr : public TemplateDefinition<1> {
 public:
  CheckSmiInstr(Value* value, intptr_t original_deopt_id) {
    ASSERT(value != NULL);
    ASSERT(original_deopt_id != Isolate::kNoDeoptId);
    inputs_[0] = value;
    deopt_id_ = original_deopt_id;
  }

  DECLARE_INSTRUCTION(CheckSmi)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kIllegalCid; }

  virtual bool AttributesEqual(Definition* other) const { return true; }

  virtual bool HasSideEffect() const { return false; }

  virtual Definition* Canonicalize();

  Value* value() const { return inputs_[0]; }

 private:
  DISALLOW_COPY_AND_ASSIGN(CheckSmiInstr);
};


class CheckArrayBoundInstr : public TemplateDefinition<2> {
 public:
  CheckArrayBoundInstr(Value* array,
                       Value* index,
                       intptr_t array_type,
                       InstanceCallInstr* instance_call)
      : array_type_(array_type) {
    ASSERT(array != NULL);
    ASSERT(index != NULL);
    inputs_[0] = array;
    inputs_[1] = index;
    deopt_id_ = instance_call->deopt_id();
  }

  DECLARE_INSTRUCTION(CheckArrayBound)
  virtual RawAbstractType* CompileType() const;

  virtual bool CanDeoptimize() const { return true; }
  virtual intptr_t ResultCid() const { return kIllegalCid; }

  virtual bool AttributesEqual(Definition* other) const;

  virtual bool HasSideEffect() const { return false; }

  Value* array() const { return inputs_[0]; }
  Value* index() const { return inputs_[1]; }

  intptr_t array_type() const { return array_type_; }

 private:
  intptr_t array_type_;

  DISALLOW_COPY_AND_ASSIGN(CheckArrayBoundInstr);
};


#undef DECLARE_INSTRUCTION


class Environment : public ZoneAllocated {
 public:
  // Construct an environment by constructing uses from an array of definitions.
  Environment(const GrowableArray<Definition*>& definitions,
              intptr_t fixed_parameter_count);

  void set_locations(Location* locations) {
    ASSERT(locations_ == NULL);
    locations_ = locations;
  }

  const GrowableArray<Value*>& values() const {
    return values_;
  }

  GrowableArray<Value*>* values_ptr() {
    return &values_;
  }

  Location LocationAt(intptr_t ix) const {
    ASSERT((ix >= 0) && (ix < values_.length()));
    return locations_[ix];
  }

  Location* LocationSlotAt(intptr_t ix) const {
    ASSERT((ix >= 0) && (ix < values_.length()));
    return &locations_[ix];
  }

  intptr_t fixed_parameter_count() const {
    return fixed_parameter_count_;
  }

  void CopyTo(Instruction* instr) const;

  void PrintTo(BufferFormatter* f) const;

 private:
  Environment(intptr_t length, intptr_t fixed_parameter_count)
      : values_(length),
        locations_(NULL),
        fixed_parameter_count_(fixed_parameter_count) { }

  GrowableArray<Value*> values_;
  Location* locations_;
  const intptr_t fixed_parameter_count_;

  DISALLOW_COPY_AND_ASSIGN(Environment);
};


// Visitor base class to visit each instruction and computation in a flow
// graph as defined by a reversed list of basic blocks.
class FlowGraphVisitor : public ValueObject {
 public:
  explicit FlowGraphVisitor(const GrowableArray<BlockEntryInstr*>& block_order)
      : block_order_(block_order), current_iterator_(NULL) { }
  virtual ~FlowGraphVisitor() { }

  ForwardInstructionIterator* current_iterator() const {
    return current_iterator_;
  }

  // Visit each block in the block order, and for each block its
  // instructions in order from the block entry to exit.
  virtual void VisitBlocks();

  // Visit functions for instruction classes, with an empty default
  // implementation.
#define DECLARE_VISIT_INSTRUCTION(ShortName)                                   \
  virtual void Visit##ShortName(ShortName##Instr* instr) { }

  FOR_EACH_INSTRUCTION(DECLARE_VISIT_INSTRUCTION)

#undef DECLARE_VISIT_INSTRUCTION

 protected:
  const GrowableArray<BlockEntryInstr*>& block_order_;
  ForwardInstructionIterator* current_iterator_;

 private:
  DISALLOW_COPY_AND_ASSIGN(FlowGraphVisitor);
};


}  // namespace dart

#endif  // VM_INTERMEDIATE_LANGUAGE_H_
