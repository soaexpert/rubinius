#include "builtin/object.hpp"
#include "builtin/variable_scope.hpp"

#include "object_utils.hpp"
#include "vm.hpp"
#include "objectmemory.hpp"

#include "call_frame.hpp"

namespace rubinius {
  void VariableScope::Info::mark(Object* obj, ObjectMark& mark) {
    auto_mark(obj, mark);

    Object* tmp;
    VariableScope* vs = as<VariableScope>(obj);

    size_t locals = vs->number_of_locals();
    for(size_t i = 0; i < locals; i++) {
      tmp = mark.call(vs->get_local(i));
      if(tmp) vs->set_local(mark.gc->object_memory->state, i, tmp);
    }
  }

  VariableScope* VariableScope::promote(STATE) {
    VariableScope* scope = state->new_struct<VariableScope>(
        G(variable_scope), number_of_locals_ * sizeof(Object*));

    scope->parent(state, parent_);
    scope->self(state, self_);
    scope->module(state, module_);
    scope->block(state, block_);
    scope->number_of_locals_ = number_of_locals_;

    for(int i = 0; i < number_of_locals_; i++) {
      scope->set_local(state, i, locals_[i]);
    }

    return scope;
  }

  void VariableScope::setup_as_block(VariableScope* top, VariableScope* parent, int num) {
    obj_type = InvalidType;
    parent_ = parent;
    self_ =   top->self();
    module_ = top->module();
    block_ =  top->block();
    number_of_locals_ = num;

    for(int i = 0; i < num; i++) {
      locals_[i] = Qnil;
    }
  }
}