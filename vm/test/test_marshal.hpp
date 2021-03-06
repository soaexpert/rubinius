#include "marshal.hpp"
#include "builtin/sendsite.hpp"

#include <cxxtest/TestSuite.h>

#include <iostream>
#include <sstream>

using namespace rubinius;

class StringMarshaller : public Marshaller {
public:
  std::ostringstream sstream;

  StringMarshaller(STATE) : Marshaller(state, sstream) { }
};

class TestMarshal : public CxxTest::TestSuite {
public:
  VM* state;
  StringMarshaller* mar;

  void setUp() {
    state = new VM();
    mar = new StringMarshaller(state);
  }

  void tearDown() {
    delete state;
    delete mar;
  }

  void test_nil() {
    mar->marshal(Qnil);
    TS_ASSERT_EQUALS(mar->sstream.str(), "n\n");
  }

  void test_true() {
    mar->marshal(Qtrue);
    TS_ASSERT_EQUALS(mar->sstream.str(), "t\n");
  }

  void test_false() {
    mar->marshal(Qfalse);
    TS_ASSERT_EQUALS(mar->sstream.str(), "f\n");
  }

  void test_int() {
    mar->marshal(Fixnum::from(1));
    TS_ASSERT_EQUALS(mar->sstream.str(), "I\n1\n");
  }

  void test_bignum() {
    mar->marshal(Bignum::from(state, (native_int)1));
    TS_ASSERT_EQUALS(mar->sstream.str(), "I\n1\n");
  }

  void test_string() {
    String* str = String::create(state, "blah");
    mar->marshal(str);
    TS_ASSERT_EQUALS(mar->sstream.str(), "s\n4\nblah\n");
  }

  void test_string_with_null() {
    String* str = String::create(state, "blah\0more", 9);
    mar->marshal(str);
    TS_ASSERT_EQUALS(mar->sstream.str(), std::string("s\n9\nblah\0more\n", 14));
  }

  void test_symbol() {
    mar->marshal(state->symbol("blah"));
    TS_ASSERT_EQUALS(mar->sstream.str(), "x\n4\nblah\n");
  }

  void test_sendsite() {
    mar->marshal(SendSite::create(state, state->symbol("blah")));
    TS_ASSERT_EQUALS(mar->sstream.str(), "S\n4\nblah\n");
  }

  void test_array() {
    Array* ary = Array::create(state, 3);
    ary->set(state, 0, Fixnum::from(1));
    ary->set(state, 1, Fixnum::from(2));
    ary->set(state, 2, Fixnum::from(3));

    mar->marshal(ary);
    TS_ASSERT_EQUALS(mar->sstream.str(), std::string("A\n3\nI\n1\nI\n2\nI\n3\n"));
  }

  void test_array_with_inner_array() {
    Array* ary = Array::create(state, 3);
    ary->set(state, 0, Fixnum::from(1));
    ary->set(state, 1, Fixnum::from(2));
    ary->set(state, 2, Fixnum::from(3));

    Array* out = Array::create(state, 2);
    out->set(state, 0, ary);
    out->set(state, 1, Fixnum::from(4));

    mar->marshal(out);
    TS_ASSERT_EQUALS(mar->sstream.str(), std::string("A\n2\nA\n3\nI\n1\nI\n2\nI\n3\nI\n4\n"));
  }

  void test_tuple() {
    Tuple* tup = Tuple::from(state, 2, Fixnum::from(8), Fixnum::from(10));

    mar->marshal(tup);
    TS_ASSERT_EQUALS(mar->sstream.str(), std::string("p\n2\nI\n8\nI\n10\n"));
  }

  void test_float() {
    mar->marshal(Float::create(state, 1.0 / 6.0));
    TS_ASSERT_EQUALS(mar->sstream.str(),
        std::string("d\n +0.666666666666666629659232512494781985878944396972656250    -2\n"));
  }

  void test_iseq() {
    InstructionSequence* iseq = InstructionSequence::create(state, 1);
    iseq->opcodes()->put(state, 0, Fixnum::from(0));

    mar->marshal(iseq);
    TS_ASSERT_EQUALS(mar->sstream.str(), std::string("i\n1\n0\n"));
  }

};
