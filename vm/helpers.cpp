#include "helpers.hpp"
#include "builtin/object.hpp"
#include "call_frame.hpp"
#include "builtin/symbol.hpp"
#include "builtin/module.hpp"
#include "builtin/compiledmethod.hpp"
#include "builtin/class.hpp"
#include "builtin/staticscope.hpp"
#include "builtin/lookuptable.hpp"
#include "global_cache.hpp"
#include "objectmemory.hpp"
#include "builtin/tuple.hpp"
#include "builtin/sendsite.hpp"

#include "vm.hpp"
#include "object_utils.hpp"
#include "message.hpp"

namespace rubinius {
  namespace Helpers {
    void add_method(STATE, CallFrame* call_frame, Module* mod, Symbol* name, CompiledMethod* method) {
      method->scope(state, call_frame->cm->scope());
      method->serial(state, Fixnum::from(0));
      mod->method_table()->store(state, name, method);
      state->global_cache->clear(mod, name);

      if(Class* cls = try_as<Class>(mod)) {
        method->formalize(state, false);

        object_type type = (object_type)cls->instance_type()->to_native();
        TypeInfo* ti = state->om->type_info[type];
        if(ti) {
          method->specialize(state, ti);
        }
      }
    }

    void attach_method(STATE, CallFrame* call_frame, Object* recv, Symbol* name, CompiledMethod* method) {
      if(Module* mod = try_as<Module>(recv)) {
        StaticScope* ss = StaticScope::create(state);
        ss->module(state, mod);
        ss->parent(state, method->scope());
        method->scope(state, ss);
      } else {
        /* Push the current scope down. */
        method->scope(state, call_frame->cm->scope());
      }

      add_method(state, call_frame, recv->metaclass(state), name, method);
    }

    Object* const_get(STATE, Module* mod, Symbol* name, bool* found) {
      Object* res;

      *found = false;

      while(!mod->nil_p()) {
        res = mod->get_const(state, name, found);
        if(*found) return res;

        if(mod == G(object)) break;
        mod = mod->superclass();
      }

      return Qnil;
    }

    Object* const_get(STATE, CallFrame* call_frame, Symbol* name, bool* found) {
      LookupTableAssociation* assoc = const_get_association(state, call_frame, name, found);
      if(*found) {
        return assoc->value();
      } else {
        return Qnil;
      }
    }

    LookupTableAssociation* const_get_association(STATE, CallFrame* call_frame,
        Symbol* name, bool* found) {
      StaticScope *cur;
      LookupTableAssociation* result;

      *found = false;

      cur = call_frame->cm->scope();
      while(!cur->nil_p()) {
        if(cur->module() == G(object)) break;

        result = cur->module()->get_const_association(state, name, found);
        if(*found) return result;

        cur = cur->parent();
      }

      Module* mod = call_frame->cm->scope()->module();
      while(!mod->nil_p()) {
        result = mod->get_const_association(state, name, found);
        if(*found) return result;

        mod = mod->superclass();
      }

      /* Lastly, check Object specificly */
      result = G(object)->get_const_association(state, name, found);
      if(*found) return result;

      return reinterpret_cast<LookupTableAssociation*>(Qnil);
    }

    Object* locate_method_on(STATE, Object* recv, Symbol* name, Object* priv) {
      Message msg(state);

      msg.recv = recv;
      msg.lookup_from = recv->lookup_begin(state);
      msg.name = name;
      msg.priv = (priv == Qtrue);
      msg.set_caller(NULL); // HACK

      if(!GlobalCacheResolver::resolve(state, msg)) {
        return (Tuple*)Qnil;
      }

      MethodVisibility *vis;

      vis = try_as<MethodVisibility>(msg.method);
      if(vis) {
        return Tuple::from(state, 2, vis->method(), msg.module);
      }

      return Tuple::from(state, 2, msg.method, msg.module);
    }

    Class* open_class(STATE, CallFrame* call_frame, Object* super, Symbol* name, bool* created) {
      Module* under;

      if(call_frame->cm->scope()->nil_p()) {
        under = G(object);
      } else {
        under = call_frame->cm->scope()->module();
      }

      return open_class(state, under, super, name, created);
    }

    static Class* add_class(STATE, Module* under, Object* super, Symbol* name) {
      if(super->nil_p()) super = G(object);
      Class* cls = Class::create(state, as<Class>(super));

      if(under == G(object)) {
        cls->name(state, name);
      } else {
        cls->set_name(state, under, name);
      }

      under->set_const(state, name, cls);

      return cls;
    }

    static Class* check_superclass(STATE, Class* cls, Object* super) {
      if(super->nil_p()) return cls;
      if(cls->direct_superclass(state) != super) {
        std::ostringstream message;
        message << "Superclass mismatch: given "
                << as<Module>(super)->name()->c_str(state)
                << " but previously set to "
                << cls->direct_superclass(state)->name()->c_str(state);
        Exception::type_error(state, Class::type, super, message.str().c_str());
        return NULL;
      }

      return cls;
    }

    Class* open_class(STATE, Module* under, Object* super, Symbol* name, bool* created) {
      bool found;

      *created = false;

      Object* obj = under->get_const(state, name, &found);
      if(found) return check_superclass(state, as<Class>(obj), super);

      *created = true;
      return add_class(state, under, super, name);
    }

    Module* open_module(STATE, CallFrame* call_frame, Symbol* name) {
      Module* under = G(object);

      if(!call_frame->cm->scope()->nil_p()) {
        under = call_frame->cm->scope()->module();
      }

      return open_module(state, under, name);
    }

    Module* open_module(STATE, Module* under, Symbol* name) {
      Module* module;
      bool found;

      Object* obj = const_get(state, under, name, &found);

      if(found) {
        return as<Module>(obj);
      }

      module = Module::create(state);

      module->set_name(state, under, name);
      under->set_const(state, name, module);

      return module;
    }

    void yield_debugger(STATE, CallFrame* call_frame) {
      abort();
    }

  }
}