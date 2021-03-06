//===-- Internalize.cpp - Mark functions internal -------------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass loops over all of the functions in the input module, looking for a
// main function.  If a main function is found, all other functions and all
// global variables with initializers are marked as internal.
//
//===----------------------------------------------------------------------===//

#define DEBUG_TYPE "internalize"
#include "llvm/Transforms/IPO.h"
#include "llvm/Pass.h"
#include "llvm/Module.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Compiler.h"
#include "llvm/Support/Debug.h"
#include "llvm/ADT/Statistic.h"
#include <fstream>
#include <set>
using namespace llvm;

STATISTIC(NumFunctions, "Number of functions internalized");
STATISTIC(NumGlobals  , "Number of global vars internalized");

namespace {

  // APIFile - A file which contains a list of symbols that should not be marked
  // external.
  static cl::opt<std::string>
  APIFile("internalize-public-api-file", cl::value_desc("filename"),
          cl::desc("A file containing list of symbol names to preserve"));

  // APIList - A list of symbols that should not be marked internal.
  static cl::list<std::string>
  APIList("internalize-public-api-list", cl::value_desc("list"),
          cl::desc("A list of symbol names to preserve"),
          cl::CommaSeparated);

  class VISIBILITY_HIDDEN InternalizePass : public ModulePass {
    std::set<std::string> ExternalNames;
    bool DontInternalize;
  public:
    static char ID; // Pass identification, replacement for typeid
    explicit InternalizePass(bool InternalizeEverything = true);
    explicit InternalizePass(const std::vector <const char *>& exportList);
    void LoadFile(const char *Filename);
    virtual bool runOnModule(Module &M);
  };
  char InternalizePass::ID = 0;
  RegisterPass<InternalizePass> X("internalize", "Internalize Global Symbols");
} // end anonymous namespace

InternalizePass::InternalizePass(bool InternalizeEverything) 
  : ModulePass((intptr_t)&ID), DontInternalize(false){
  if (!APIFile.empty())           // If a filename is specified, use it
    LoadFile(APIFile.c_str());
  else if (!APIList.empty())      // Else, if a list is specified, use it.
    ExternalNames.insert(APIList.begin(), APIList.end());
  else if (!InternalizeEverything)
    // Finally, if we're allowed to, internalize all but main.
    DontInternalize = true;
}

InternalizePass::InternalizePass(const std::vector<const char *>&exportList) 
  : ModulePass((intptr_t)&ID), DontInternalize(false){
  for(std::vector<const char *>::const_iterator itr = exportList.begin();
        itr != exportList.end(); itr++) {
    ExternalNames.insert(*itr);
  }
}

void InternalizePass::LoadFile(const char *Filename) {
  // Load the APIFile...
  std::ifstream In(Filename);
  if (!In.good()) {
    cerr << "WARNING: Internalize couldn't load file '" << Filename << "'!\n";
    return;   // Do not internalize anything...
  }
  while (In) {
    std::string Symbol;
    In >> Symbol;
    if (!Symbol.empty())
      ExternalNames.insert(Symbol);
  }
}

bool InternalizePass::runOnModule(Module &M) {
  if (DontInternalize) return false;
  
  // If no list or file of symbols was specified, check to see if there is a
  // "main" symbol defined in the module.  If so, use it, otherwise do not
  // internalize the module, it must be a library or something.
  //
  if (ExternalNames.empty()) {
    Function *MainFunc = M.getFunction("main");
    if (MainFunc == 0 || MainFunc->isDeclaration())
      return false;  // No main found, must be a library...
    
    // Preserve main, internalize all else.
    ExternalNames.insert(MainFunc->getName());
  }
  
  bool Changed = false;
  
  // Found a main function, mark all functions not named main as internal.
  for (Module::iterator I = M.begin(), E = M.end(); I != E; ++I)
    if (!I->isDeclaration() &&         // Function must be defined here
        !I->hasInternalLinkage() &&  // Can't already have internal linkage
        !ExternalNames.count(I->getName())) {// Not marked to keep external?
      I->setLinkage(GlobalValue::InternalLinkage);
      Changed = true;
      ++NumFunctions;
      DOUT << "Internalizing func " << I->getName() << "\n";
    }
  
  // Never internalize the llvm.used symbol.  It is used to implement
  // attribute((used)).
  ExternalNames.insert("llvm.used");
  
  // Never internalize anchors used by the machine module info, else the info
  // won't find them.  (see MachineModuleInfo.)
  ExternalNames.insert("llvm.dbg.compile_units");
  ExternalNames.insert("llvm.dbg.global_variables");
  ExternalNames.insert("llvm.dbg.subprograms");
  ExternalNames.insert("llvm.global_ctors");
  ExternalNames.insert("llvm.global_dtors");
  ExternalNames.insert("llvm.noinline");
  ExternalNames.insert("llvm.global.annotations");
      
  // Mark all global variables with initializers as internal as well.
  for (Module::global_iterator I = M.global_begin(), E = M.global_end();
       I != E; ++I)
    if (!I->isDeclaration() && !I->hasInternalLinkage() &&
        !ExternalNames.count(I->getName())) {
      I->setLinkage(GlobalValue::InternalLinkage);
      Changed = true;
      ++NumGlobals;
      DOUT << "Internalized gvar " << I->getName() << "\n";
    }
      
  return Changed;
}

ModulePass *llvm::createInternalizePass(bool InternalizeEverything) {
  return new InternalizePass(InternalizeEverything);
}

ModulePass *llvm::createInternalizePass(const std::vector <const char *> &el) {
  return new InternalizePass(el);
}
