require File.dirname(__FILE__) + '/../spec_helper'

describe "A Super node" do
  relates <<-ruby do
      def x
        super()
      end
    ruby

    parse do
      [:defn, :x, [:args], [:scope, [:block, [:super]]]]
    end

    compile do |g|
      in_method :x do |d|
        d.push_block
        d.send_super :x, 0
      end
    end
  end

  relates <<-ruby do
      def x
        super([24, 42])
      end
    ruby

    parse do
      [:defn,
       :x,
       [:args],
       [:scope, [:block, [:super, [:array, [:lit, 24], [:lit, 42]]]]]]
    end

    compile do |g|
      in_method :x do |d|
        d.push 24
        d.push 42
        d.make_array 2
        d.push_block
        d.send_super :x, 1
      end
    end
  end

  relates <<-ruby do
      def x
        super(4)
      end
    ruby

    parse do
      [:defn, :x, [:args], [:scope, [:block, [:super, [:lit, 4]]]]]
    end

    compile do |g|
      in_method :x do |d|
        d.push 4
        d.push_block
        d.send_super :x, 1
      end
    end
  end

  relates "super(a, &b)" do
    parse do
      [:super,
       [:call, nil, :a, [:arglist]],
       [:block_pass, [:call, nil, :b, [:arglist]]]]
    end

    compile do |g|
      t = g.new_label

      g.push :self
      g.send :a, 0, true

      g.push :self
      g.send :b, 0, true

      g.dup
      g.is_nil
      g.git t

      g.push_cpath_top
      g.find_const :Proc
      g.swap

      g.send :__from_block__, 1

      t.set!

      # nil here because the test isn't wrapped in a method, so
      # there is no current method to pull the name of the method
      # from
      g.send_super nil, 1
    end
  end

  relates "super(a, *b)" do
    parse do
      [:super,
        [:call, nil, :a, [:arglist]],
        [:splat, [:call, nil, :b, [:arglist]]]]
    end

    compile do |g|
      g.push :self
      g.send :a, 0, true

      g.push :self
      g.send :b, 0, true

      g.cast_array

      g.push_block

      # nil here because the test isn't wrapped in a method, so
      # there is no current method to pull the name of the method
      # from
      g.send_super nil, 1, true
    end
  end

  relates <<-ruby do
      def x
        super(24, 42)
      end
    ruby

    parse do
      [:defn,
        :x,
        [:args],
        [:scope, [:block, [:super, [:lit, 24], [:lit, 42]]]]]
    end

    compile do |g|
      in_method :x do |d|
        d.push 24
        d.push 42
        d.push_block
        d.send_super :x, 2
      end
    end
  end

  relates "super([*[1]])" do
    parse do
      [:super, [:array, [:splat, [:array, [:lit, 1]]]]]
    end

    compile do |g|
      g.array_of_splatted_array

      g.push_block
      g.send_super nil, 1
    end
  end

  relates "super(*[1])" do
    parse do
      [:super, [:splat, [:array, [:lit, 1]]]]
    end

    compile do |g|
      g.push 1
      g.make_array 1
      g.cast_array

      g.push_block
      g.send_super nil, 0, true
    end
  end
end
