require File.dirname(__FILE__) + '/../spec_helper'

describe "A While node" do
  pre_while_sexp = [
    :while,
     [:call, nil, :a, [:arglist]],
     [:call, [:call, nil, :b, [:arglist]], :+, [:arglist, [:lit, 1]]],
     true
  ]

  pre_while = lambda do |g|
    top    = g.new_label
    rdo    = g.new_label
    brk    = g.new_label
    bottom = g.new_label

    g.push_modifiers

    top.set!
    g.push :self
    g.send :a, 0, true
    g.gif bottom

    rdo.set!
    g.push :self
    g.send :b, 0, true
    g.push 1
    g.send :+, 1, false
    g.pop

    g.goto top

    bottom.set!
    g.push :nil

    brk.set!
    g.pop_modifiers
  end

  relates <<-ruby do
      while a
        b + 1
      end
    ruby

    parse do
      pre_while_sexp
    end

    compile(&pre_while)
  end

  relates "b + 1 while a" do
    parse do
      pre_while_sexp
    end

    compile(&pre_while)
  end

  relates <<-ruby do
      until not a
        b + 1
      end
    ruby

    parse do
      pre_while_sexp
    end

    compile(&pre_while)
  end

  relates "b + 1 until not a" do
    parse do
      pre_while_sexp
    end

    compile(&pre_while)
  end

  post_while_sexp = [
    :while,
     [:call, nil, :a, [:arglist]],
     [:call, [:call, nil, :b, [:arglist]], :+, [:arglist, [:lit, 1]]],
     false
  ]

  post_while = lambda do |g|
    top    = g.new_label
    rdo    = g.new_label
    brk    = g.new_label
    bottom = g.new_label

    g.push_modifiers

    top.set!

    g.push :self
    g.send :b, 0, true
    g.push 1
    g.send :+, 1, false
    g.pop

    rdo.set!

    g.push :self
    g.send :a, 0, true
    g.gif bottom

    g.goto top

    bottom.set!
    g.push :nil

    brk.set!
    g.pop_modifiers
  end

  relates <<-ruby do
      begin
        b + 1
      end while a
    ruby

    parse do
      post_while_sexp
    end

    compile(&post_while)
  end

  relates <<-ruby do
      begin
        b + 1
      end until not a
    ruby

    parse do
      post_while_sexp
    end

    compile(&post_while)
  end

  nil_condition_sexp = [:while, [:nil], [:call, nil, :a, [:arglist]], true]

  nil_condition = lambda do |g|
    top    = g.new_label
    rdo    = g.new_label
    brk    = g.new_label
    bottom = g.new_label

    g.push_modifiers

    top.set!
    g.push :nil
    g.gif bottom

    rdo.set!
    g.push :self
    g.send :a, 0, true
    g.pop

    g.goto top

    bottom.set!
    g.push :nil

    brk.set!
    g.pop_modifiers
  end

  relates "a while ()" do
    parse do
      nil_condition_sexp
    end

    compile(&nil_condition)
  end

  relates <<-ruby do
      while ()
        a
      end
    ruby

    parse do
      nil_condition_sexp
    end

    compile(&nil_condition)
  end

  relates "a until not ()" do

    parse do
      nil_condition_sexp
    end

    compile(&nil_condition)
  end

  relates <<-ruby do
      until not ()
        a
      end
    ruby

    parse do
      nil_condition_sexp
    end

    compile(&nil_condition)
  end
end
