# Contained first is the system startup code.
begin
  ENV = EnvironmentVariables.new

  String.ruby_parser if ENV['RUBY_PARSER']
  String.sydney_parser if ENV['SYDNEY'] or ENV['SYDPARSE']

  # define a global "start time" to use for process calculation
  $STARTUP_TIME = Time.now
rescue Object => e
  STDOUT << "Error detected running loader startup stage:\n"
  STDOUT << "  #{e.message} (#{e.class})\n"
  STDOUT << e.backtrace
  exit 2
end

# Set up a handler for SIGINT that raises Interrupt on the main thread
Signal.action("INT") do |_|
  thread = Thread.main

  if thread.alive?
    thread.raise Interrupt, "Thread has been interrupted"
  else # somehow..?
    puts "Signal received, but the main thread is dead."
    puts "Unable to continue."
    exit! 1
  end
end

# This is the end of the kernel and the beginning of specified
# code. We read out of ARGV to figure out what the user is
# trying to do.

# Setup $LOAD_PATH.

# Add a fallback directory if Rubinius::LIB_PATH doesn't exist
lib_path = File.expand_path(Rubinius::LIB_PATH)
lib_path = File.join(Dir.pwd, 'lib') unless File.exists?(lib_path)

additions = []
additions << lib_path

# The main stdlib location
# HACK todo remove this comment when we're setting this constant in the VM
# additions << Rubinius::CODE_PATH

$LOAD_PATH.unshift(*additions)

# Pull it out now so that later unshifts don't obsure it.
main_lib = $LOAD_PATH.first

if ENV['RUBYLIB'] and not ENV['RUBYLIB'].empty? then
  rubylib_paths = ENV['RUBYLIB'].split(':')
  $LOAD_PATH.unshift(*rubylib_paths)
end

# Allow system wide code preloading

['/etc/rbxrc',"#{ENV['HOME']}/.rbxrc",ENV['RBX_PRELOAD']].each do |file|
  begin
    load file if file and File.exist?(file)
  rescue LoadError
    nil
  end
end

# Parse options here!
RBS_USAGE = <<END
Usage: rubinius [options] [file]
  File may be any valid Ruby source file (.rb) or a compiled Ruby file (.rbc).

Options:
  -d             Enable debugging output and set $DEBUG to true.
  -dc            Display debugging information for the compiler.
  -dl            Display debugging information for the loader.
  -debug         Launch the debugger.
  -remote-debug  Run the program under the control of a remote debugger.
  -e 'code'      Directly compile and execute code (no file provided).
  -Idir1[:dir2]  Add directories to $LOAD_PATH.
  -S script      Run script using PATH environment variable to find it.
  -P             Run the profiler.
  -Ps            Run the Selector profiler.
  -Pss           Run the SendSite profiler.
  -rlibrary      Require library before execution.
  --sydney       Use SydneyParser.
  --ruby_parser  Use RubyParser.
  -w             Enable warnings. (currently does nothing--compatibility)
  -v             Display the version and set $VERBOSE to true.
END

$VERBOSE = false
code = 0

show_selectors = false
show_sendsites = false

# Setup the proper staticscope
MethodContext.current.method.scope = StaticScope.new(Object)

TOPLEVEL_BINDING = binding()

show_eval = false
eval_code = nil
script = nil

begin

  script_debug_requested = false
  until ARGV.empty?
    arg = ARGV.shift
    case arg
    when '--'
      break
    when '-h', '--help'
      puts RBS_USAGE
      exit 1
    when "-v"
      puts "rubinius #{Rubinius::RBX_VERSION} (ruby #{RUBY_VERSION}) (#{Rubinius::BUILDREV[0..8]} #{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"
      $VERBOSE = true
      exit 0 if ARGV.empty?
    when "-vv"
      puts "rubinius #{Rubinius::RBX_VERSION} (ruby #{RUBY_VERSION}) (#{Rubinius::BUILDREV[0..8]} #{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"
      $VERBOSE = true
      puts "Options:"
      puts "  Interpreter type: #{Rubinius::INTERPRETER}"
      if jit = Rubinius::JIT
        puts "  JIT enabled: #{jit}"
      else
        puts "  JIT disabled"
      end
      puts
      exit 0 if ARGV.empty?
    when "-w"
      # do nothing (HACK)
    when '-dc'
      puts "[Compiler debugging enabled]"
      $DEBUG_COMPILER = true
    when '-dl'
      $DEBUG_LOADING = true
      puts "[Code loading debugging enabled]"
    when '-d'
      $DEBUG = true
    when '-debug'
      require 'debugger/interface'
      Debugger::CmdLineInterface.new
      script_debug_requested = true
    when '-remote-debug'
      require 'debugger/debug_server'
      if port = (ARGV.first =~ /^\d+$/ and ARGV.shift)
        $DEBUG_SERVER = Debugger::Server.new(port.to_i)
      else
        $DEBUG_SERVER = Debugger::Server.new
      end
      $DEBUG_SERVER.listen
      script_debug_requested = true
    when '-P'
      require 'profile'
    when '-Ps'
      count = (ARGV.first =~ /^\d+$/) ? ARGV.shift : '30'
      show_selectors = count.to_i
    when '-Pss'
      count = (ARGV.first =~ /^\d+$/) ? ARGV.shift : '30'
      show_sendsites = count.to_i
    when '-S'
      script = ARGV.shift
      sep    = File::PATH_SEPARATOR
      path   = ENV['PATH'].split(sep).map { |d| File.join(d, script) }
      file   = path.find { |path| File.exist? path }

      $0 = script if file

      # if missing, let it die a natural death
      ARGV.unshift file ? file : script
    when '--sydney'
      String.sydney_parser
    when '--ruby_parser'
      String.ruby_parser
    when '-e'
      $0 = "(eval)"
      eval_code = ARGV.shift
    when '-ed'
      show_eval = true
    else
      if arg.prefix? "-I"
        more = arg[2..-1]
        if more.empty?
          path = File.expand_path ARGV.shift
          $LOAD_PATH.unshift path
        else
          more.split(":").reverse_each do |path|
            path = File.expand_path path
            $LOAD_PATH.unshift(path)
          end
        end
      elsif arg.prefix? "-r"
        more = arg[2..-1]
        if more.empty?
          require ARGV.shift
        else
          require more
        end
      elsif arg.prefix? "-i"
        # in place edit mode
        $-i = arg[2..-1]
      elsif arg == "-"
        $0 = "-"
        Compile.execute STDIN.read
      elsif arg.prefix? "-"
        puts "Invalid switch '#{arg}'"
        puts RBS_USAGE
        exit! 1
      else
        script = arg
        # And we're done.
        break
      end
    end
  end

  # If someone used -e, run that code.
  if eval_code
    # If we also caught a script to run, we just treat it like
    # another arg.
    ARGV.unshift script if script
    eval(eval_code, TOPLEVEL_BINDING) do |compiled_method|
      if show_eval
        p eval_code.to_sexp("(eval)", 1)
        puts compiled_method.decode
      end
    end
  elsif script
    if File.exist?(script)
      $0 = script
      Compile.debug_script! if script_debug_requested
      Compile.load_from_extension arg
    else
      if script.suffix?(".rb")
        puts "Unable to find '#{script}'"
        exit! 1
      else
        prog = File.join main_lib, "bin", "#{script}.rb"
        if File.exist? prog
          $0 = prog
          load prog
        else
          raise LoadError, "Unable to find a script '#{script}' to run"
        end
      end
    end
  end

  unless $0
    if Rubinius::Terminal
      repr = ENV['RBX_REPR'] || "bin/irb"
      $0 = repr
      prog = File.join main_lib, repr
      begin
        # HACK: this was load but load raises LoadError
        # with prog == "lib/bin/irb". However, require works.
        # Investigate when we have specs running.
        require prog
      rescue LoadError => e
        STDERR.puts "Unable to find repr named '#{repr}' to load."
        exit 1
      end
    else
      $0 = "(eval)"
      Compile.execute "p #{STDIN.read}"
    end
  end

rescue SystemExit => e
  code = e.status
rescue Object => e
  original_context = e.context

  begin
    if e.kind_of? Exception or e.kind_of? ThrownValue
      msg = e.message
    else
      msg = "strange object detected as exception: #{e.inspect}"
    end
    if e.kind_of? SyntaxError
      puts "A syntax error has occured:"
      puts "    #{msg}"
      puts "    near line #{e.file}:#{e.line}, column #{e.column}"
      puts "\nCode:\n#{e.code}"
      if e.column
        puts((" " * (e.column - 1)) + "^")
      end
    else
      puts "An exception has occurred:"
      puts "    #{msg} (#{e.class})"
    end
    puts "\nBacktrace:"
    puts e.awesome_backtrace.show
    code = 1
  rescue Object => e2
    puts "\n====================================="
    puts "Unable to build proper backtrace due to errors!"
    puts
    puts "Original Exception: #{e.inspect} (#{e.class})"
    if original_context
      puts "Lowlevel backtrace:"
      Rubinius::VM.show_backtrace(original_context)
      puts
    end

    puts "New Exception: #{e2.inspect} (#{e.class})"
    new_context = e2.context
    if new_context
      puts "Lowlevel backtrace:"
      Rubinius::VM.show_backtrace(new_context)
    end
    code = 128
  end
end

begin
  Rubinius::AtExit.shift.call until Rubinius::AtExit.empty?
rescue SystemExit => e
  code = e.status
rescue Object => e
  puts "An exception occurred inside an at_exit handler:"
  puts "    #{e.message} (#{e.class})"
  puts "\nBacktrace:"
  puts e.awesome_backtrace.show
  code = 1
end

begin
  ObjectSpace.run_finalizers
rescue Object => e
  puts "An exception occured while running object finalizers:"
  puts "    #{e.message} (#{e.class})"
  puts "\nBacktrace:"
  puts e.awesome_backtrace.show
  code = 1
end

if show_selectors
  ps = Rubinius::Profiler::Selectors.new
  begin
    ps.show_stats show_selectors
  rescue Object => e
    puts "An exception occured while running selector profiler:"
    puts "    #{e.message} (#{e.class})"
    puts "\nBacktrace:"
    puts e.awesome_backtrace.show
    code = 1
  end
end

if show_sendsites
  ps = Rubinius::Profiler::SendSites.new
  begin
    ps.show_stats show_sendsites
  rescue Object => e
    puts "An exception occured while running sendsite profiler:"
    puts "    #{e.message} (#{e.class})"
    puts "\nBacktrace:"
    puts e.awesome_backtrace.show
    code = 1
  end
end

if Rubinius::RUBY_CONFIG['rbx.jit_stats']
  stats = Rubinius::VM.jit_info
  puts "JIT time spent: #{stats[0] / 1000000}ms"
  puts " JITed methods: #{stats[1]}"
end

if Rubinius::RUBY_CONFIG['rbx.gc_stats']
  timing = Rubinius::VM.gc_info
  puts "Time spent in GC: #{timing / 1000000}ms"
end

Process.exit(code || 0)
