// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/flow_graph.h"

#include "vm/bit_vector.h"
#include "vm/flow_graph_builder.h"
#include "vm/intermediate_language.h"
#include "vm/longjump.h"

namespace dart {

FlowGraph::FlowGraph(const FlowGraphBuilder& builder,
                     GraphEntryInstr* graph_entry)
  : parent_(),
    assigned_vars_(),
    current_ssa_temp_index_(0),
    parsed_function_(builder.parsed_function()),
    copied_parameter_count_(builder.copied_parameter_count()),
    non_copied_parameter_count_(builder.non_copied_parameter_count()),
    stack_local_count_(builder.stack_local_count()),
    graph_entry_(graph_entry),
    preorder_(),
    postorder_(),
    reverse_postorder_() {
  DiscoverBlocks();
}


void FlowGraph::DiscoverBlocks() {
  // Initialize state.
  preorder_.TruncateTo(0);
  postorder_.TruncateTo(0);
  reverse_postorder_.TruncateTo(0);
  parent_.TruncateTo(0);
  assigned_vars_.TruncateTo(0);
  // Perform a depth-first traversal of the graph to build preorder and
  // postorder block orders.
  graph_entry_->DiscoverBlocks(NULL,  // Entry block predecessor.
                               &preorder_,
                               &postorder_,
                               &parent_,
                               &assigned_vars_,
                               variable_count(),
                               non_copied_parameter_count());
  // Number blocks in reverse postorder.
  intptr_t block_count = postorder_.length();
  for (intptr_t i = 0; i < block_count; ++i) {
    postorder_[i]->set_block_id(block_count - i - 1);
    reverse_postorder_.Add(postorder_[block_count - i - 1]);
  }
  // Link instructions backwards for optimized compilation.
  // TODO(zerny): The builder should do this at construction time.
  for (intptr_t i = 0; i < block_count; ++i) {
    BlockEntryInstr* entry = postorder_[i];
    Instruction* previous = entry;
    for (ForwardInstructionIterator it(entry); !it.Done(); it.Advance()) {
      Instruction* current = it.Current();
      current->set_previous(previous);
      previous = current;
    }
  }
}


void FlowGraph::ComputeSSA() {
  GrowableArray<BitVector*> dominance_frontier;
  ComputeDominators(&preorder_, &parent_, &dominance_frontier);
  InsertPhis(preorder_, assigned_vars_, dominance_frontier);
  GrowableArray<PhiInstr*> live_phis;
  // Rename uses to reference inserted phis where appropriate.
  // Collect phis that reach a non-environment use.
  Rename(&live_phis);
  // Propagate alive mark transitively from alive phis.
  MarkLivePhis(&live_phis);
}


// Compute immediate dominators and the dominance frontier for each basic
// block.  As a side effect of the algorithm, sets the immediate dominator
// of each basic block.
//
// preorder: an input list of basic block entries in preorder.  The
//     algorithm relies on the block ordering.
//
// parent: an input parameter encoding a depth-first spanning tree of
//     the control flow graph.  The array maps the preorder block
//     number of a block to the preorder block number of its spanning
//     tree parent.
//
// dominance_frontier: an output parameter encoding the dominance frontier.
//     The array maps the preorder block number of a block to the set of
//     (preorder block numbers of) blocks in the dominance frontier.
void FlowGraph::ComputeDominators(
    GrowableArray<BlockEntryInstr*>* preorder,
    GrowableArray<intptr_t>* parent,
    GrowableArray<BitVector*>* dominance_frontier) {
  // Use the SEMI-NCA algorithm to compute dominators.  This is a two-pass
  // version of the Lengauer-Tarjan algorithm (LT is normally three passes)
  // that eliminates a pass by using nearest-common ancestor (NCA) to
  // compute immediate dominators from semidominators.  It also removes a
  // level of indirection in the link-eval forest data structure.
  //
  // The algorithm is described in Georgiadis, Tarjan, and Werneck's
  // "Finding Dominators in Practice".
  // See http://www.cs.princeton.edu/~rwerneck/dominators/ .

  // All arrays are maps between preorder basic-block numbers.
  intptr_t size = parent->length();
  GrowableArray<intptr_t> idom(size);  // Immediate dominator.
  GrowableArray<intptr_t> semi(size);  // Semidominator.
  GrowableArray<intptr_t> label(size);  // Label for link-eval forest.

  // 1. First pass: compute semidominators as in Lengauer-Tarjan.
  // Semidominators are computed from a depth-first spanning tree and are an
  // approximation of immediate dominators.

  // Use a link-eval data structure with path compression.  Implement path
  // compression in place by mutating the parent array.  Each block has a
  // label, which is the minimum block number on the compressed path.

  // Initialize idom, semi, and label used by SEMI-NCA.  Initialize the
  // dominance frontier output array.
  for (intptr_t i = 0; i < size; ++i) {
    idom.Add((*parent)[i]);
    semi.Add(i);
    label.Add(i);
    dominance_frontier->Add(new BitVector(size));
  }

  // Loop over the blocks in reverse preorder (not including the graph
  // entry).
  for (intptr_t block_index = size - 1; block_index >= 1; --block_index) {
    // Loop over the predecessors.
    BlockEntryInstr* block = (*preorder)[block_index];
    for (intptr_t i = 0, count = block->PredecessorCount(); i < count; ++i) {
      BlockEntryInstr* pred = block->PredecessorAt(i);
      ASSERT(pred != NULL);

      // Look for the semidominator by ascending the semidominator path
      // starting from pred.
      intptr_t pred_index = pred->preorder_number();
      intptr_t best = pred_index;
      if (pred_index > block_index) {
        CompressPath(block_index, pred_index, parent, &label);
        best = label[pred_index];
      }

      // Update the semidominator if we've found a better one.
      semi[block_index] = Utils::Minimum(semi[block_index], semi[best]);
    }

    // Now use label for the semidominator.
    label[block_index] = semi[block_index];
  }

  // 2. Compute the immediate dominators as the nearest common ancestor of
  // spanning tree parent and semidominator, for all blocks except the entry.
  for (intptr_t block_index = 1; block_index < size; ++block_index) {
    intptr_t dom_index = idom[block_index];
    while (dom_index > semi[block_index]) {
      dom_index = idom[dom_index];
    }
    idom[block_index] = dom_index;
    (*preorder)[block_index]->set_dominator((*preorder)[dom_index]);
    (*preorder)[dom_index]->AddDominatedBlock((*preorder)[block_index]);
  }

  // 3. Now compute the dominance frontier for all blocks.  This is
  // algorithm in "A Simple, Fast Dominance Algorithm" (Figure 5), which is
  // attributed to a paper by Ferrante et al.  There is no bookkeeping
  // required to avoid adding a block twice to the same block's dominance
  // frontier because we use a set to represent the dominance frontier.
  for (intptr_t block_index = 0; block_index < size; ++block_index) {
    BlockEntryInstr* block = (*preorder)[block_index];
    intptr_t count = block->PredecessorCount();
    if (count <= 1) continue;
    for (intptr_t i = 0; i < count; ++i) {
      BlockEntryInstr* runner = block->PredecessorAt(i);
      while (runner != block->dominator()) {
        (*dominance_frontier)[runner->preorder_number()]->Add(block_index);
        runner = runner->dominator();
      }
    }
  }
}


void FlowGraph::CompressPath(intptr_t start_index,
                             intptr_t current_index,
                             GrowableArray<intptr_t>* parent,
                             GrowableArray<intptr_t>* label) {
  intptr_t next_index = (*parent)[current_index];
  if (next_index > start_index) {
    CompressPath(start_index, next_index, parent, label);
    (*label)[current_index] =
        Utils::Minimum((*label)[current_index], (*label)[next_index]);
    (*parent)[current_index] = (*parent)[next_index];
  }
}


void FlowGraph::InsertPhis(
    const GrowableArray<BlockEntryInstr*>& preorder,
    const GrowableArray<BitVector*>& assigned_vars,
    const GrowableArray<BitVector*>& dom_frontier) {
  const intptr_t block_count = preorder.length();
  // Map preorder block number to the highest variable index that has a phi
  // in that block.  Use it to avoid inserting multiple phis for the same
  // variable.
  GrowableArray<intptr_t> has_already(block_count);
  // Map preorder block number to the highest variable index for which the
  // block went on the worklist.  Use it to avoid adding the same block to
  // the worklist more than once for the same variable.
  GrowableArray<intptr_t> work(block_count);

  // Initialize has_already and work.
  for (intptr_t block_index = 0; block_index < block_count; ++block_index) {
    has_already.Add(-1);
    work.Add(-1);
  }

  // Insert phis for each variable in turn.
  GrowableArray<BlockEntryInstr*> worklist;
  for (intptr_t var_index = 0; var_index < variable_count(); ++var_index) {
    // Add to the worklist each block containing an assignment.
    for (intptr_t block_index = 0; block_index < block_count; ++block_index) {
      if (assigned_vars[block_index]->Contains(var_index)) {
        work[block_index] = var_index;
        worklist.Add(preorder[block_index]);
      }
    }

    while (!worklist.is_empty()) {
      BlockEntryInstr* current = worklist.Last();
      worklist.RemoveLast();
      // Ensure a phi for each block in the dominance frontier of current.
      for (BitVector::Iterator it(dom_frontier[current->preorder_number()]);
           !it.Done();
           it.Advance()) {
        int index = it.Current();
        if (has_already[index] < var_index) {
          BlockEntryInstr* block = preorder[index];
          ASSERT(block->IsJoinEntry());
          block->AsJoinEntry()->InsertPhi(var_index, variable_count());
          has_already[index] = var_index;
          if (work[index] < var_index) {
            work[index] = var_index;
            worklist.Add(block);
          }
        }
      }
    }
  }
}


void FlowGraph::Rename(GrowableArray<PhiInstr*>* live_phis) {
  // TODO(fschneider): Support catch-entry.
  if (graph_entry_->SuccessorCount() > 1) {
    Bailout("Catch-entry support in SSA.");
  }

  // Initialize start environment.
  GrowableArray<Value*> start_env(variable_count());
  for (intptr_t i = 0; i < parameter_count(); ++i) {
    ParameterInstr* param = new ParameterInstr(i);
    param->set_ssa_temp_index(alloc_ssa_temp_index());  // New SSA temp.
    start_env.Add(new UseVal(param));
  }

  // All locals are initialized with #null.
  Value* null_value = new ConstantVal(Object::ZoneHandle());
  while (start_env.length() < variable_count()) {
    start_env.Add(null_value);
  }
  graph_entry_->set_start_env(
      new Environment(start_env, non_copied_parameter_count_));

  BlockEntryInstr* normal_entry = graph_entry_->SuccessorAt(0);
  ASSERT(normal_entry != NULL);  // Must have entry.
  GrowableArray<Value*> env(variable_count());
  env.AddArray(start_env);
  RenameRecursive(normal_entry, &env, live_phis);
}


// Helper to a copy a value iff it is a UseVal.
static Value* CopyValue(Value* value) {
  return value->IsUse()
      ? new UseVal(value->AsUse()->definition())
      : value;
}


void FlowGraph::RenameRecursive(BlockEntryInstr* block_entry,
                                GrowableArray<Value*>* env,
                                GrowableArray<PhiInstr*>* live_phis) {
  // 1. Process phis first.
  if (block_entry->IsJoinEntry()) {
    JoinEntryInstr* join = block_entry->AsJoinEntry();
    if (join->phis() != NULL) {
      for (intptr_t i = 0; i < join->phis()->length(); ++i) {
        PhiInstr* phi = (*join->phis())[i];
        if (phi != NULL) {
          (*env)[i] = new UseVal(phi);
          phi->set_ssa_temp_index(alloc_ssa_temp_index());  // New SSA temp.
        }
      }
    }
  }

  // 2. Process normal instructions.
  for (ForwardInstructionIterator it(block_entry); !it.Done(); it.Advance()) {
    Instruction* current = it.Current();
    // Attach current environment to the instruction. First, each instruction
    // gets a full copy of the environment. Later we optimize this by
    // eliminating unnecessary environments.
    current->set_env(new Environment(*env, non_copied_parameter_count_));

    // 2a. Handle uses:
    // Update expression stack environment for each use.
    // For each use of a LoadLocal or StoreLocal: Replace it with the value
    // from the environment.
    for (intptr_t i = current->InputCount() - 1; i >= 0; --i) {
      Value* v = current->InputAt(i);
      if (!v->IsUse()) continue;
      // Update expression stack.
      ASSERT(env->length() > variable_count());

      Value* input_value = env->Last();
      ASSERT(input_value->IsUse());
      env->RemoveLast();

      BindInstr* as_bind = v->AsUse()->definition()->AsBind();
      if ((as_bind != NULL) &&
          (as_bind->computation()->IsLoadLocal() ||
           as_bind->computation()->IsStoreLocal())) {
        // Assert exactly one use.
        ASSERT(as_bind->use_list() == v);
        ASSERT(as_bind->use_list()->next_use() == NULL);
        // Remove the use, its definition and copy the environment value.
        v->RemoveFromUseList();
        as_bind->RemoveFromGraph();
        current->SetInputAt(i, CopyValue(input_value));
      }
    }

    // Drop pushed arguments for calls.
    for (intptr_t j = 0; j < current->ArgumentCount(); j++) {
      env->RemoveLast();
    }

    // 2b. Handle LoadLocal and StoreLocal.
    // For each LoadLocal: Remove it from the graph.
    // For each StoreLocal: Remove it from the graph and update the environment.
    BindInstr* bind = current->AsBind();
    if (bind != NULL) {
      LoadLocalComp* load = bind->computation()->AsLoadLocal();
      StoreLocalComp* store = bind->computation()->AsStoreLocal();
      if ((load != NULL) || (store != NULL)) {
        intptr_t index;
        if (store != NULL) {
          index = store->local().BitIndexIn(non_copied_parameter_count_);
          // Update renaming environment.
          (*env)[index] = store->value();
        } else {
          // The graph construction ensures we do not have an unused LoadLocal
          // computation.
          ASSERT(bind->is_used());
          index = load->local().BitIndexIn(non_copied_parameter_count_);

          Value* value = (*env)[index];
          if (value->IsUse()) {
            PhiInstr* phi = value->AsUse()->definition()->AsPhi();
            if ((phi != NULL) && !phi->is_alive()) {
              phi->mark_alive();
              live_phis->Add(phi);
            }
          }
        }
        // Update expression stack or remove from graph.
        if (bind->is_used()) {
          // Assert exactly one use.
          ASSERT(bind->use_list() != NULL);
          ASSERT(bind->use_list()->next_use() == NULL);
          env->Add(CopyValue((*env)[index]));
          // We remove load/store instructions when we find their use in 2a.
        } else {
          it.RemoveCurrentFromGraph();
        }
      } else {
        // Not a load or store.
        if (bind->is_used()) {
          // Assign fresh SSA temporary and update expression stack.
          bind->set_ssa_temp_index(alloc_ssa_temp_index());
          env->Add(new UseVal(bind));
        }
      }
    }

    // 2c. Handle pushed argument.
    PushArgumentInstr* push = current->AsPushArgument();
    if (push != NULL) {
      env->Add(new UseVal(push));
    }
  }

  // 3. Process dominated blocks.
  for (intptr_t i = 0; i < block_entry->dominated_blocks().length(); ++i) {
    BlockEntryInstr* block = block_entry->dominated_blocks()[i];
    GrowableArray<Value*> new_env(env->length());
    new_env.AddArray(*env);
    RenameRecursive(block, &new_env, live_phis);
  }

  // 4. Process successor block. We have edge-split form, so that only blocks
  // with one successor can have a join block as successor.
  if ((block_entry->last_instruction()->SuccessorCount() == 1) &&
      block_entry->last_instruction()->SuccessorAt(0)->IsJoinEntry()) {
    JoinEntryInstr* successor =
        block_entry->last_instruction()->SuccessorAt(0)->AsJoinEntry();
    intptr_t pred_index = successor->IndexOfPredecessor(block_entry);
    ASSERT(pred_index >= 0);
    if (successor->phis() != NULL) {
      for (intptr_t i = 0; i < successor->phis()->length(); ++i) {
        PhiInstr* phi = (*successor->phis())[i];
        if (phi != NULL) {
          // Rename input operand and make a copy if it is a UseVal.
          phi->SetInputAt(pred_index, CopyValue((*env)[i]));
        }
      }
    }
  }
}


void FlowGraph::MarkLivePhis(GrowableArray<PhiInstr*>* live_phis) {
  while (!live_phis->is_empty()) {
    PhiInstr* phi = live_phis->Last();
    live_phis->RemoveLast();
    for (intptr_t i = 0; i < phi->InputCount(); i++) {
      Value* val = phi->InputAt(i);
      if (!val->IsUse()) continue;
      PhiInstr* used_phi = val->AsUse()->definition()->AsPhi();
      if ((used_phi != NULL) && !used_phi->is_alive()) {
        used_phi->mark_alive();
        live_phis->Add(used_phi);
      }
    }
  }
}


void FlowGraph::Bailout(const char* reason) const {
  const char* kFormat = "FlowGraph Bailout: %s %s";
  const char* function_name = parsed_function_.function().ToCString();
  intptr_t len = OS::SNPrint(NULL, 0, kFormat, function_name, reason) + 1;
  char* chars = Isolate::Current()->current_zone()->Alloc<char>(len);
  OS::SNPrint(chars, len, kFormat, function_name, reason);
  const Error& error = Error::Handle(
      LanguageError::New(String::Handle(String::New(chars))));
  Isolate::Current()->long_jump_base()->Jump(1, error);
}


}  // namespace dart
