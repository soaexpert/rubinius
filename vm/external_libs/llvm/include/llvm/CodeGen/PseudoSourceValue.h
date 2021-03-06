//===-- llvm/CodeGen/PseudoSourceValue.h ------------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file contains the declaration of the PseudoSourceValue class.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CODEGEN_PSEUDOSOURCEVALUE_H
#define LLVM_CODEGEN_PSEUDOSOURCEVALUE_H

#include "llvm/Value.h"

namespace llvm {
  /// PseudoSourceValue - Special value supplied for machine level alias
  /// analysis. It indicates that the a memory access references the functions
  /// stack frame (e.g., a spill slot), below the stack frame (e.g., argument
  /// space), or constant pool.
  class PseudoSourceValue : public Value {
  public:
    PseudoSourceValue();

    virtual void print(std::ostream &OS) const;

    /// classof - Methods for support type inquiry through isa, cast, and
    /// dyn_cast:
    ///
    static inline bool classof(const PseudoSourceValue *) { return true; }
    static inline bool classof(const Value *V) {
      return V->getValueID() == PseudoSourceValueVal;
    }

    /// A pseudo source value referencing to the stack frame of a function,
    /// e.g., a spill slot.
    static const PseudoSourceValue *getFixedStack();

    /// A source value referencing the area below the stack frame of a function,
    /// e.g., the argument space.
    static const PseudoSourceValue *getStack();

    /// A source value referencing the global offset table (or something the
    /// like).
    static const PseudoSourceValue *getGOT();

    /// A SV referencing the constant pool
    static const PseudoSourceValue *getConstantPool();

    /// A SV referencing the jump table
    static const PseudoSourceValue *getJumpTable();
  };
} // End llvm namespace

#endif
