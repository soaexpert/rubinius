# depends on: class.rb

class IO

  # Buffer provides a sliding window into a region of bytes.
  # The buffer is filled to the +used+ indicator, which is
  # always less than or equal to +total+. As bytes are taken
  # from the buffer, the +start+ indicator is incremented by
  # the number of bytes taken. Once +start+ == +used+, the
  # buffer is +empty?+ and needs to be refilled.
  #
  # This description should be independent of the "direction"
  # in which the buffer is used. As a read buffer, +fill_from+
  # appends at +used+, but not exceeding +total+. When +used+
  # equals total, no additional bytes will be filled until the
  # buffer is emptied.
  #
  # As a write buffer, +empty_to+ removes bytes from +start+ up
  # to +used+. When +start+ equals +used+, no additional bytes
  # will be emptied until the buffer is filled.
  #
  # IO presents a stream of input. Buffer presents buckets of
  # input. IO's task is to chain the buckets so the user sees
  # a stream. IO explicitly requests that the buffer be filled
  # (on input) and then determines how much of the input to take
  # (e.g. by looking for a separator or collecting a certain
  # number of bytes). Buffer decides whether or not to go to the
  # source for more data or just present what is already in the
  # buffer.
  class Buffer

    attr_reader :total
    attr_reader :start
    attr_reader :used
    attr_reader :channel

    ##
    # Returns +true+ if the buffer can be filled.
    def empty?
      @start == @used
    end

    ##
    # Returns +true+ if the buffer is empty and cannot be filled further.
    def exhausted?
      @eof and empty?
    end

    ##
    # A request to the buffer to have data. The buffer decides whether
    # existing data is sufficient, or whether to read more data from the
    # +IO+ instance. Any new data causes this method to return.
    #
    # Returns the number of bytes in the buffer.
    def fill_from(io, skip = nil)
      empty_to io
      discard skip if skip
      return size unless empty?

      reset!
      Scheduler.send_on_readable @channel, io, self, unused

      # FIX: what is obj and what should it be?
      obj = @channel.receive
      if obj.kind_of? Class
        raise IOError, "error occured while filling buffer (#{obj})"
      end

      if @used == 0
        io.eof!
        @eof = true
      end

      return size
    end

    def empty_to(io)
      return 0 if @write_synced or empty?
      @write_synced = true

      io.prim_write(String.from_bytearray(@storage, @start, size))
      reset!

      return size
    end

    ##
    # Advances the beginning-of-buffer marker past any number
    # of contiguous characters == +skip+. For example, if +skip+
    # is ?\n and the buffer contents are "\n\n\nAbc...", the
    # start marker will be positioned on 'A'.
    def discard(skip)
      while @start < @used
        break unless @storage[@start] == skip
        @start += 1
      end
    end

    ##
    # Returns the number of bytes to fetch from the buffer up-to-
    # and-including +pattern+. Returns +nil+ if pattern is not found.
    def find(pattern, discard = nil)
      return unless count = @storage.locate(pattern, @start)
      count - @start
    end

    ##
    # Returns +true+ if the buffer is filled to capacity.
    def full?
      @total == @used
    end

    def inspect # :nodoc:
      "#<IO::Buffer:0x%x total=%p start=%p used=%p data=%p>" % [
        object_id, @total, @start, @used, @storage
      ]
    end

    ##
    # Blocks until the buffer receives more data.
    def process
      @channel.receive
    end

    ##
    # Resets the buffer state so the buffer can be filled again.
    def reset!
      @start = @used = 0
      @eof = false
      @write_synced = true
    end

    def write_synced?
      @write_synced
    end

    def unseek!(io)
      # Unseek the still buffered amount
      return unless write_synced?
      unless empty?
        io.prim_seek(@start - @used, IO::SEEK_CUR)
      end
      reset!
    end

    ##
    # Returns +count+ bytes from the +start+ of the buffer as a new String.
    # If +count+ is +nil+, returns all available bytes in the buffer.
    def shift(count = nil)
      total = size
      total = count if count and count < total

      str = String.from_bytearray @storage, @start, total
      @start += total

      return str
    end

    ##
    # Returns the number of bytes available in the buffer.
    def size
      @used - @start
    end

    ##
    # Returns the number of bytes of capacity remaining in the buffer.
    # This is the number of additional bytes that can be added to the
    # buffer before it is full.
    def unused
      @total - @used
    end
  end

  module Constants
    F_GETFL  = Rubinius::RUBY_CONFIG['rbx.platform.fcntl.F_GETFL']
    F_SETFL  = Rubinius::RUBY_CONFIG['rbx.platform.fcntl.F_SETFL']

    # O_ACCMODE is /undocumented/ for fcntl() on some platforms
    ACCMODE  = Rubinius::RUBY_CONFIG['rbx.platform.fcntl.O_ACCMODE']

    SEEK_SET = Rubinius::RUBY_CONFIG['rbx.platform.io.SEEK_SET']
    SEEK_CUR = Rubinius::RUBY_CONFIG['rbx.platform.io.SEEK_CUR']
    SEEK_END = Rubinius::RUBY_CONFIG['rbx.platform.io.SEEK_END']

    RDONLY   = Rubinius::RUBY_CONFIG['rbx.platform.file.O_RDONLY']
    WRONLY   = Rubinius::RUBY_CONFIG['rbx.platform.file.O_WRONLY']
    RDWR     = Rubinius::RUBY_CONFIG['rbx.platform.file.O_RDWR']

    CREAT    = Rubinius::RUBY_CONFIG['rbx.platform.file.O_CREAT']
    EXCL     = Rubinius::RUBY_CONFIG['rbx.platform.file.O_EXCL']
    NOCTTY   = Rubinius::RUBY_CONFIG['rbx.platform.file.O_NOCTTY']
    TRUNC    = Rubinius::RUBY_CONFIG['rbx.platform.file.O_TRUNC']
    APPEND   = Rubinius::RUBY_CONFIG['rbx.platform.file.O_APPEND']
    NONBLOCK = Rubinius::RUBY_CONFIG['rbx.platform.file.O_NONBLOCK']
    SYNC     = Rubinius::RUBY_CONFIG['rbx.platform.file.O_SYNC']

    # TODO: these flags should probably be imported from Platform
    LOCK_SH  = 0x01
    LOCK_EX  = 0x02
    LOCK_NB  = 0x04
    LOCK_UN  = 0x08
    BINARY   = 0x04
  end

  include Constants

  def self.for_fd(fd, mode = nil)
    new fd, mode
  end

  def self.foreach(name, sep_string = $/, &block)
    sep_string ||= ''
    io = File.open(StringValue(name), 'r')
    sep = StringValue(sep_string)
    begin
      while(line = io.gets(sep))
        yield line
      end
    ensure
      io.close
    end
  end

  ##
  # Creates a new IO object to access the existing stream referenced by the
  # descriptor given. The stream is not copied in any way so anything done on
  # one IO will affect any other IOs accessing the same descriptor.
  #
  # The mode string given must be compatible with the original one so going
  # 'r' from 'w' cannot be done but it is possible to go from 'w+' to 'r', for
  # example (since the stream is not being "widened".)
  #
  # The initialization will verify that the descriptor given is a valid one.
  # Errno::EBADF will be raised if that is not the case. If the mode is
  # incompatible, it will raise Errno::EINVAL instead.
  def self.open(fd, mode = nil)
    io = new fd, mode

    return io unless block_given?

    begin
      yield io
    ensure
      io.close rescue nil unless io.closed?
    end
  end

  def self.parse_mode(mode)
    ret = 0

    case mode[0]
    when ?r
      ret |= RDONLY
    when ?w
      ret |= WRONLY | CREAT | TRUNC
    when ?a
      ret |= WRONLY | CREAT | APPEND
    else
      raise ArgumentError, "invalid mode -- #{mode}"
    end

    return ret if mode.length == 1

    case mode[1]
    when ?+
      ret &= ~(RDONLY | WRONLY)
      ret |= RDWR
    when ?b
      ret |= BINARY
    else
      raise ArgumentError, "invalid mode -- #{mode}"
    end

    return ret if mode.length == 2

    case mode[2]
    when ?+
      ret &= ~(RDONLY | WRONLY)
      ret |= RDWR
    when ?b
      ret |= BINARY
    else
      raise ArgumentError, "invalid mode -- #{mode}"
    end

    ret
  end

  ##
  # Creates a pair of pipe endpoints (connected to each other)
  # and returns them as a two-element array of IO objects:
  # [ read_file, write_file ]. Not available on all platforms.
  #
  # In the example below, the two processes close the ends of 
  # the pipe that they are not using. This is not just a cosmetic
  # nicety. The read end of a pipe will not generate an end of
  # file condition if there are any writers with the pipe still
  # open. In the case of the parent process, the rd.read will
  # never return if it does not first issue a wr.close.
  #
  #  rd, wr = IO.pipe
  #
  #  if fork
  #    wr.close
  #    puts "Parent got: <#{rd.read}>"
  #    rd.close
  #    Process.wait
  #  else
  #    rd.close
  #    puts "Sending message to parent"
  #    wr.write "Hi Dad"
  #    wr.close
  #  end
  # produces:
  #
  #  Sending message to parent
  #  Parent got: <Hi Dad>
  def self.pipe
    lhs = IO.allocate
    rhs = IO.allocate
    connect_pipe(lhs, rhs)
    lhs.sync = true
    rhs.sync = true
    return [lhs, rhs]
  end

  ## 
  # Runs the specified command string as a subprocess;
  # the subprocess‘s standard input and output will be
  # connected to the returned IO object. If cmd_string
  # starts with a ``-’’, then a new instance of Ruby is
  # started as the subprocess. The default mode for the
  # new file object is ``r’’, but mode may be set to any
  # of the modes listed in the description for class IO.
  #
  # If a block is given, Ruby will run the command as a
  # child connected to Ruby with a pipe. Ruby‘s end of
  # the pipe will be passed as a parameter to the block. 
  # At the end of block, Ruby close the pipe and sets $?.
  # In this case IO::popen returns the value of the block.
  # 
  # If a block is given with a cmd_string of ``-’’, the
  # block will be run in two separate processes: once in
  # the parent, and once in a child. The parent process
  # will be passed the pipe object as a parameter to the
  # block, the child version of the block will be passed
  # nil, and the child‘s standard in and standard out will
  # be connected to the parent through the pipe.
  # Not available on all platforms.
  #
  #  f = IO.popen("uname")
  #  p f.readlines
  #  puts "Parent is #{Process.pid}"
  #  IO.popen ("date") { |f| puts f.gets }
  #  IO.popen("-") {|f| $stderr.puts "#{Process.pid} is here, f is #{f}"}
  #  p $?
  # produces:
  # 
  #  ["Linux\n"]
  #  Parent is 26166
  #  Wed Apr  9 08:53:52 CDT 2003
  #  26169 is here, f is
  #  26166 is here, f is #<IO:0x401b3d44>
  #  #<Process::Status: pid=26166,exited(0)>
  def self.popen(str, mode = "r")
    if str == "+-+" and !block_given?
      raise ArgumentError, "this mode requires a block currently"
    end

    mode = parse_mode mode

    readable = false
    writable = false

    if mode & IO::RDWR != 0 then
      readable = true
      writable = true
    elsif mode & IO::WRONLY != 0 then
      writable = true
    else # IO::RDONLY
      readable = true
    end

    pa_read, ch_write = IO.pipe if readable
    ch_read, pa_write = IO.pipe if writable

    pid = Process.fork do
      if readable then
        pa_read.close
        STDOUT.reopen ch_write
      end

      if writable then
        pa_write.close
        STDIN.reopen ch_read
      end

      if str == "+-+"
        yield nil
      else
        Process.perform_exec "/bin/sh", ["sh", "-c", str]
      end
    end

    ch_write.close if readable
    ch_read.close  if writable

    # See bottom for definition
    pipe = IO::BidirectionalPipe.new pid, pa_read, pa_write

    if block_given? then
      begin
        yield pipe
      ensure
        pipe.close
      end
    else
      return pipe
    end
  end

  ##
  # Opens the file, optionally seeks to the given offset,
  # then returns length bytes (defaulting to the rest of
  # the file). read ensures the file is closed before returning.
  #
  #  IO.read("testfile")           #=> "This is line one\nThis is line two\nThis is line three\nAnd so on...\n"
  #  IO.read("testfile", 20)       #=> "This is line one\nThi"
  #  IO.read("testfile", 20, 10)   #=> "ne one\nThis is line "
  def self.read(name, length = Undefined, offset = 0)
    name = StringValue(name)
    length ||= Undefined
    offset ||= 0

    offset = Type.coerce_to(offset, Fixnum, :to_int)

    if offset < 0
      raise Errno::EINVAL, "offset must not be negative"
    end

    unless length.equal?(Undefined)
      length = Type.coerce_to(length, Fixnum, :to_int)

      if length < 0
        raise ArgumentError, "length must not be negative"
      end
    end

    File.open(name) do |f|
      f.seek(offset) unless offset.zero?

      if length.equal?(Undefined)
        f.read
      else
        f.read(length)
      end
    end
  end

  ## 
  # Reads the entire file specified by name as individual
  # lines, and returns those lines in an array. Lines are
  # separated by sep_string.
  #
  #  a = IO.readlines("testfile")
  #  a[0]   #=> "This is line one\n"
  def self.readlines(name, sep_string = $/)
    name = StringValue name
    io = File.open(name, 'r')
    return if io.nil?

    begin
      io.readlines(sep_string)
    ensure
      io.close
    end
  end

  ##
  # Select() examines the I/O descriptor sets who are passed in
  # +read_array+, +write_array+, and +error_array+ to see if some of their descriptors are
  # ready for reading, are ready for writing, or have an exceptions pending.
  #
  # If +timeout+ is not nil, it specifies a maximum interval to wait
  # for the selection to complete. If timeout is nil, the select
  # blocks indefinitely.
  #
  # +write_array+, +error_array+, and +timeout+ may be left as nil if they are
  # unimportant
  def self.select(read_array, write_array = nil, error_array = nil,
                  timeout = nil)
    # TODO libev doesn't seem to support exception fd set.
    raise NotImplementedError, "error_array is not supported" if error_array

    if timeout
      raise TypeError, "timeout must be numeric" unless Type.obj_kind_of?(timeout, Numeric)
      raise ArgumentError, 'timeout must be positive' if timeout < 0
    end

    chan = Channel.new

    fd_map = {}
    [read_array, write_array, error_array].each_with_index do |io_array, pos|
      next unless io_array
      raise TypeError, "wrong argument type #{io_array.class} (expected Array)" unless Type.obj_kind_of?(io_array, Array)

      io_array.each do |io|
        io_obj = Type.coerce_to(io, IO, :to_io)
        fd_map[io_obj.fileno] = [pos, io]

        case pos
        when 0 # read_array
          Scheduler.send_on_readable chan, io_obj, nil, -1
        when 1 # write_array
          Scheduler.send_on_writable chan, io_obj
        end
      end
    end

    Scheduler.send_in_microseconds chan, (timeout * 1_000_000).to_i, nil if timeout

    # blocks until a fd is ready, or timeout
    value = chan.receive
    other_values = chan.value

    if other_values
      # we have more objects ready to be received, let's count them.
      available_count = other_values.count
    else
      return nil if value.nil? # tired of waiting, timed out
      available_count = 0
    end

    ret = [[], [], []]
    while true
      if value
        fd_info = fd_map[value]
        ret[fd_info[0]] << fd_info[1]
      end
      break if (available_count -= 1) < 0
      value = chan.receive
    end

    ret
  end

  ##
  # Opens the given path, returning the underlying file descriptor as a Fixnum.
  #  IO.sysopen("testfile")   #=> 3
  def self.sysopen(path, mode = "r", perm = 0666)
    unless mode.kind_of? Integer
      mode = parse_mode(StringValue(mode))
    end

    open_with_mode(path, mode, perm)
  end

  #
  # Create a new IO associated with the given fd.
  #
  def initialize(fd, mode = nil)
    if block_given?
      Rubinius.warn 'IO::new() does not take block; use IO::open() instead'
    end
    setup Type.coerce_to(fd, Integer, :to_int), mode
  end

  private :initialize

  #
  # @internal
  #
  # Internally associate this object with the given descriptor.
  #
  # The mode will be checked and set as the current mode if
  # the underlying descriptor allows it.
  #
  def setup(fd, mode = nil)
    cur_mode = Platform::POSIX.fcntl(fd, F_GETFL, 0)
    Errno.handle if cur_mode < 0
    cur_mode &= ACCMODE

    if mode
      str_mode = StringValue mode
      mode = IO.parse_mode(str_mode) & ACCMODE

      if (cur_mode == RDONLY or cur_mode == WRONLY) and mode != cur_mode
        raise Errno::EINVAL, "Invalid new mode '#{str_mode}' for existing descriptor #{fd}"
      end
    end

    @descriptor = fd
    @mode = mode || cur_mode
    @sync = [STDOUT.fileno, STDERR.fileno].include? fd
  end

  private :setup

  ##
  # Obtains a new duplicate descriptor for the current one.
  def initialize_copy(original) # :nodoc:
    @descriptor = Platform::POSIX.dup(@descriptor)
  end

  private :initialize_copy

  def <<(obj)
    write(obj.to_s)
    return self
  end

  ##
  # Puts ios into binary mode. This is useful only in
  # MS-DOS/Windows environments. Once a stream is in
  # binary mode, it cannot be reset to nonbinary mode.
  def binmode
    # HACK what to do?
  end

  ##
  # Closes the read end of a duplex I/O stream (i.e., one
  # that contains both a read and a write stream, such as
  # a pipe). Will raise an IOError if the stream is not duplexed.
  #
  #  f = IO.popen("/bin/sh","r+")
  #  f.close_read
  #  f.readlines
  # produces:
  #
  #  prog.rb:3:in `readlines': not opened for reading (IOError)
  #   from prog.rb:3
  def close_read
    if @mode == WRONLY || @mode == RDWR
      raise IOError, 'closing non-duplex IO for reading'
    end
    close
  end

  ##
  # Closes the write end of a duplex I/O stream (i.e., one
  # that contains both a read and a write stream, such as
  # a pipe). Will raise an IOError if the stream is not duplexed.
  #
  #  f = IO.popen("/bin/sh","r+")
  #  f.close_write
  #  f.print "nowhere"
  # produces:
  #
  #  prog.rb:3:in `write': not opened for writing (IOError)
  #   from prog.rb:3:in `print'
  #   from prog.rb:3
  def close_write
    if @mode == RDONLY || @mode == RDWR
      raise IOError, 'closing non-duplex IO for writing'
    end
    close
  end

  ##
  # Returns true if ios is completely closed (for duplex
  # streams, both reader and writer), false otherwise.
  #
  #  f = File.new("testfile")
  #  f.close         #=> nil
  #  f.closed?       #=> true
  #  f = IO.popen("/bin/sh","r+")
  #  f.close_write   #=> nil
  #  f.closed?       #=> false
  #  f.close_read    #=> nil
  #  f.closed?       #=> true
  def closed?
    @descriptor == -1
  end

  attr_reader :descriptor

  def dup
    ensure_open
    super
  end

  ##
  # Executes the block for every line in ios, where
  # lines are separated by sep_string. ios must be
  # opened for reading or an IOError will be raised.
  #
  #  f = File.new("testfile")
  #  f.each {|line| puts "#{f.lineno}: #{line}" }
  # produces:
  #
  #  1: This is line one
  #  2: This is line two
  #  3: This is line three
  #  4: And so on...
  def each(sep=$/)
    ensure_open_and_readable

    sep = sep.to_str if sep
    while line = read_to_separator(sep)
      yield line
    end

    self
  end

  alias_method :each_line, :each

  def each_byte
    yield getc until eof?

    self
  end

  ##
  # Set the pipe so it is at the end of the file
  def eof!
    @eof = true
  end

  ##
  # Returns true if ios is at end of file that means
  # there are no more data to read. The stream must be
  # opened for reading or an IOError will be raised.
  #
  #  f = File.new("testfile")
  #  dummy = f.readlines
  #  f.eof   #=> true
  # If ios is a stream such as pipe or socket, IO#eof? 
  # blocks until the other end sends some data or closes it.
  #
  #  r, w = IO.pipe
  #  Thread.new { sleep 1; w.close }
  #  r.eof?  #=> true after 1 second blocking
  #
  #  r, w = IO.pipe
  #  Thread.new { sleep 1; w.puts "a" }
  #  r.eof?  #=> false after 1 second blocking
  #
  #  r, w = IO.pipe
  #  r.eof?  # blocks forever
  # Note that IO#eof? reads data to a input buffer. So IO#sysread doesn't work with IO#eof?.
  def eof?
    ensure_open_and_readable
    @ibuffer.fill_from self unless @ibuffer.exhausted?
    @eof and @ibuffer.exhausted?
  end

  alias_method :eof, :eof?

  def ensure_open_and_readable
    ensure_open
    write_only = @mode & ACCMODE == WRONLY
    raise IOError, "not opened for reading" if write_only
  end

  def ensure_open_and_writable
    ensure_open
    read_only = @mode & ACCMODE == RDONLY
    raise IOError, "not opened for writing" if read_only
  end

  ##
  # Provides a mechanism for issuing low-level commands to
  # control or query file-oriented I/O streams. Arguments
  # and results are platform dependent. If arg is a number,
  # its value is passed directly. If it is a string, it is
  # interpreted as a binary sequence of bytes (Array#pack
  # might be a useful way to build this string). On Unix
  # platforms, see fcntl(2) for details. Not implemented on all platforms.
  def fcntl(command, arg=0)
    ensure_open
    if arg.kind_of? Fixnum then
      Platform::POSIX.fcntl(descriptor, command, arg)
    else
      raise NotImplementedError, "cannot handle #{arg.class}"
    end
  end

  ##
  # Returns an integer representing the numeric file descriptor for ios.
  #
  #  $stdin.fileno    #=> 0
  #  $stdout.fileno   #=> 1
  def fileno
    ensure_open
    @descriptor
  end

  alias_method :to_i, :fileno

  ##
  # Flushes any buffered data within ios to the underlying
  # operating system (note that this is Ruby internal 
  # buffering only; the OS may buffer the data as well).
  #
  #  $stdout.print "no newline"
  #  $stdout.flush
  # produces:
  #
  #  no newline
  def flush
    ensure_open
    @ibuffer.empty_to self
    self
  end

  ##
  # Immediately writes all buffered data in ios to disk. Returns
  # nil if the underlying operating system does not support fsync(2).
  # Note that fsync differs from using IO#sync=. The latter ensures
  # that data is flushed from Ruby's buffers, but does not guarantee
  # that the underlying operating system actually writes it to disk.
  def fsync
    flush

    err = Platform::POSIX.fsync @descriptor

    Errno.handle 'fsync(2)' if err < 0

    err
  end

  ##
  # Gets the next 8-bit byte (0..255) from ios.
  # Returns nil if called at end of file.
  #
  #  f = File.new("testfile")
  #  f.getc   #=> 84
  #  f.getc   #=> 104
  def getc
    char = read 1
    return nil if char.nil?
    char[0]
  end

  ##
  # Reads the next ``line’’ from the I/O stream;
  # lines are separated by sep_string. A separator
  # of nil reads the entire contents, and a zero-length 
  # separator reads the input a paragraph at a time (two
  # successive newlines in the input separate paragraphs).
  # The stream must be opened for reading or an IOError
  # will be raised. The line read in will be returned and
  # also assigned to $_. Returns nil if called at end of file.
  #
  #  File.new("testfile").gets   #=> "This is line one\n"
  #  $_                          #=> "This is line one\n"
  def gets(sep=$/)
    ensure_open_and_readable

    if line = read_to_separator(sep)
      line.taint
      @lineno += 1
      $. = @lineno
    end

    $_ = line
  end

  ##
  # Return a string describing this IO object.
  def inspect
    "#<#{self.class}:0x#{object_id.to_s(16)}>"
  end

  ##
  # Returns the current line number in ios. The
  # stream must be opened for reading. lineno
  # counts the number of times gets is called,
  # rather than the number of newlines encountered.
  # The two values will differ if gets is called with
  # a separator other than newline. See also the $. variable.
  #
  #  f = File.new("testfile")
  #  f.lineno   #=> 0
  #  f.gets     #=> "This is line one\n"
  #  f.lineno   #=> 1
  #  f.gets     #=> "This is line two\n"
  #  f.lineno   #=> 2
  def lineno
    ensure_open

    @lineno
  end

  ##
  # Manually sets the current line number to the
  # given value. $. is updated only on the next read.
  #
  #  f = File.new("testfile")
  #  f.gets                     #=> "This is line one\n"
  #  $.                         #=> 1
  #  f.lineno = 1000
  #  f.lineno                   #=> 1000
  #  $. # lineno of last read   #=> 1
  #  f.gets                     #=> "This is line two\n"
  #  $. # lineno of last read   #=> 1001
  def lineno=(line_number)
    ensure_open

    raise TypeError if line_number.nil?

    @lineno = Integer line_number
  end

  ##
  # FIXME
  # Returns the process ID of a child process
  # associated with ios. This will be set by IO::popen.
  #
  #  pipe = IO.popen("-")
  #  if pipe
  #    $stderr.puts "In parent, child pid is #{pipe.pid}"
  #  else
  #    $stderr.puts "In child, pid is #{$$}"
  #  end
  # produces:
  #
  #  In child, pid is 26209
  #  In parent, child pid is 26209
  def pid
    nil
  end

  ##
  # 
  def pos
    seek 0, SEEK_CUR
  end

  alias_method :tell, :pos

  ##
  # Seeks to the given position (in bytes) in ios.
  #
  #  f = File.new("testfile")
  #  f.pos = 17
  #  f.gets   #=> "This is line two\n"
  def pos=(offset)
    offset = Integer offset

    seek offset, SEEK_SET
  end

  ##
  # Writes each given argument.to_s to the stream or $_ (the result of last
  # IO#gets) if called without arguments. Appends $\.to_s to output. Returns
  # nil.
  def print(*args)
    if args.empty?
      write $_.to_s
    else
      args.each {|o| write o.to_s }
    end

    write $\.to_s
    nil
  end

  ##
  # Formats and writes to ios, converting parameters under
  # control of the format string. See Kernel#sprintf for details.
  def printf(fmt, *args)
    write Sprintf.new(fmt, *args).parse
  end

  ##
  # If obj is Numeric, write the character whose code is obj,
  # otherwise write the first character of the string
  # representation of obj to ios.
  #
  #  $stdout.putc "A"
  #  $stdout.putc 65
  # produces:
  #
  #  AA
  def putc(obj)
    byte = if obj.__kind_of__ String then
             obj[0]
           else
             Type.coerce_to(obj, Integer, :to_int) & 0xff
           end

    write byte.chr
  end

  ##
  # Writes the given objects to ios as with IO#print.
  # Writes a record separator (typically a newline)
  # after any that do not already end with a newline
  # sequence. If called with an array argument, writes 
  # each element on a new line. If called without arguments,
  # outputs a single record separator.
  #
  #  $stdout.puts("this", "is", "a", "test")
  # produces:
  #
  #  this
  #  is
  #  a
  #  test
  def puts(*args)
    if args.empty?
      write DEFAULT_RECORD_SEPARATOR
    else
      args.each do |arg|
        if arg.nil?
          str = "nil"
        elsif RecursionGuard.inspecting?(arg)
          str = "[...]"
        elsif arg.kind_of?(Array)
          RecursionGuard.inspect(arg) do
            arg.each do |a|
              puts a
            end
          end
        else
          str = arg.to_s
        end

        if str
          write str
          write DEFAULT_RECORD_SEPARATOR unless str.suffix?(DEFAULT_RECORD_SEPARATOR)
        end
      end
    end

    nil
  end

  ##
  # Reads at most _length_ bytes from the I/O stream, or to the
  # end of file if _length_ is omitted or is +nil+. _length_
  # must be a non-negative integer or +nil+. If the optional
  # _buffer_ argument is present, it must reference a String,
  # which will receive the data.
  #
  # At end of file, it returns +nil+ or +""+ depending on
  # _length_. +_ios_.read()+ and +_ios_.read(nil)+ returns +""+.
  # +_ios_.read(_positive-integer_)+ returns +nil+.
  #
  #   f = File.new("testfile")
  #   f.read(16)   #=> "This is line one"
  def read(length=nil, buffer=nil)
    ensure_open
    buffer = StringValue buffer if buffer

    unless length
      str = read_all
      return str unless buffer

      buffer.replace str
      return buffer
    end

    return nil if @ibuffer.exhausted?

    str = ""
    needed = length
    while needed > 0 and not @ibuffer.exhausted?
      available = @ibuffer.fill_from self

      count = available > needed ? needed : available
      str << @ibuffer.shift(count)
      str = nil if str.empty?

      needed -= count
    end

    return str unless buffer

    buffer.replace str
    buffer
  end

  ##
  # Reads all input until +#eof?+ is true. Returns the input read.
  # If the buffer is already exhausted, returns +""+.
  def read_all
    str = ""
    until @ibuffer.exhausted?
      @ibuffer.fill_from self
      str << @ibuffer.shift
    end

    str
  end

  private :read_all

  ##
  # Reads at most maxlen bytes from ios using read(2) system
  # call after O_NONBLOCK is set for the underlying file descriptor.
  #
  # If the optional outbuf argument is present, it must reference
  # a String, which will receive the data.
  #
  # read_nonblock just calls read(2). It causes all errors read(2)
  # causes: EAGAIN, EINTR, etc. The caller should care such errors.
  #
  # read_nonblock causes EOFError on EOF.
  #
  # If the read buffer is not empty, read_nonblock reads from the
  # buffer like readpartial. In this case, read(2) is not called.
  def read_nonblock(size, buffer = nil)
    ensure_open
    prim_read(size, buffer)
  end

  ##
  # Chains together buckets of input from the buffer until
  # locating +sep+. If +sep+ is +nil+, returns +read_all+.
  # If +sep+ is +""+, reads until +"\n\n"+. Otherwise, reads
  # until +sep+. This is the behavior of +#each+ and +#gets+.
  # Also, sets +$.+ for each line read. Returns the line read
  # or +nil+ if <tt>#eof?</tt> is true.
  #--
  # This implementation is slightly longer to reduce several
  # method calls. The common case is that the buffer has
  # enough data to just find the sep and return. Instead of
  # returning nil right of if buffer.exhausted?, allow the
  # nil to fall through. Also, don't create an empty string
  # just to append a single line to it.
  #++
  def read_to_separator(sep)
    return if @ibuffer.exhausted?
    return read_all unless sep

    sep = StringValue sep if sep

    if sep.empty?
      sep = "\n\n"
      skip = ?\n
    else
      skip = nil
    end

    line = nil
    until @ibuffer.exhausted?
      @ibuffer.fill_from self, skip

      if count = @ibuffer.find(sep)
        str = @ibuffer.shift(count)
      else
        str = @ibuffer.shift
      end

      if line
        line << str
      else
        line = str
      end

      break if count
    end
    @ibuffer.discard skip if skip

    line unless line.empty?
  end

  private :read_to_separator

  ##
  # Reads a character as with IO#getc, but raises an EOFError on end of file.
  def readchar
    char = getc

    raise EOFError, 'end of file reached' if char.nil?

    char
  end

  ##
  # Reads a line as with IO#gets, but raises an EOFError on end of file.
  def readline(sep=$/)
    out = gets(sep)
    raise EOFError, "end of file" unless out
    return out
  end

  ##
  # Reads all of the lines in ios, and returns them in an array.
  # Lines are separated by the optional sep_string. If sep_string
  # is nil, the rest of the stream is returned as a single record.
  # The stream must be opened for reading or an IOError will be raised.
  #
  #  f = File.new("testfile")
  #  f.readlines[0]   #=> "This is line one\n"
  def readlines(sep=$/)
    sep = StringValue sep if sep

    old_line = $_
    ary = Array.new
    while line = gets(sep)
      ary << line
    end
    $_ = old_line

    ary
  end

  ##
  # Reads at most maxlen bytes from the I/O stream. It blocks
  # only if ios has no data immediately available. It doesn‘t
  # block if some data available. If the optional outbuf argument
  # is present, it must reference a String, which will receive the
  # data. It raises EOFError on end of file.
  #
  # readpartial is designed for streams such as pipe, socket, tty,
  # etc. It blocks only when no data immediately available. This
  # means that it blocks only when following all conditions hold.
  #
  # the buffer in the IO object is empty.
  # the content of the stream is empty.
  # the stream is not reached to EOF.
  # When readpartial blocks, it waits data or EOF on the stream.
  # If some data is reached, readpartial returns with the data.
  # If EOF is reached, readpartial raises EOFError.
  #
  # When readpartial doesn‘t blocks, it returns or raises immediately.
  # If the buffer is not empty, it returns the data in the buffer.
  # Otherwise if the stream has some content, it returns the data in
  # the stream. Otherwise if the stream is reached to EOF, it raises EOFError.
  #
  #  r, w = IO.pipe           #               buffer          pipe content
  #  w << "abc"               #               ""              "abc".
  #  r.readpartial(4096)      #=> "abc"       ""              ""
  #  r.readpartial(4096)      # blocks because buffer and pipe is empty.
  #
  #  r, w = IO.pipe           #               buffer          pipe content
  #  w << "abc"               #               ""              "abc"
  #  w.close                  #               ""              "abc" EOF
  #  r.readpartial(4096)      #=> "abc"       ""              EOF
  #  r.readpartial(4096)      # raises EOFError
  #
  #  r, w = IO.pipe           #               buffer          pipe content
  #  w << "abc\ndef\n"        #               ""              "abc\ndef\n"
  #  r.gets                   #=> "abc\n"     "def\n"         ""
  #  w << "ghi\n"             #               "def\n"         "ghi\n"
  #  r.readpartial(4096)      #=> "def\n"     ""              "ghi\n"
  #  r.readpartial(4096)      #=> "ghi\n"     ""              ""
  # Note that readpartial behaves similar to sysread. The differences are:
  #
  # If the buffer is not empty, read from the buffer instead
  # of "sysread for buffered IO (IOError)".
  # It doesn‘t cause Errno::EAGAIN and Errno::EINTR. When readpartial
  # meets EAGAIN and EINTR by read system call, readpartial retry the system call.
  # The later means that readpartial is nonblocking-flag insensitive. It
  # blocks on the situation IO#sysread causes Errno::EAGAIN as if the fd is blocking mode.
  def readpartial(size, buffer = nil)
    raise ArgumentError, 'negative string size' unless size >= 0
    ensure_open

    buffer = '' if buffer.nil?

    in_buf = @ibuffer.shift size
    size = size - in_buf.length

    in_buf << sysread(size) if size > 0

    buffer.replace in_buf

    buffer
  end

  alias_method :orig_reopen, :reopen

  ##
  # Reassociates ios with the I/O stream given in other_IO or to
  # a new stream opened on path. This may dynamically change the
  # actual class of this stream.
  #
  #  f1 = File.new("testfile")
  #  f2 = File.new("testfile")
  #  f2.readlines[0]   #=> "This is line one\n"
  #  f2.reopen(f1)     #=> #<File:testfile>
  #  f2.readlines[0]   #=> "This is line one\n"
  def reopen(other, mode = 'r+')
    flush
    other = if other.respond_to? :to_io then
              other.to_io
            else
              File.new other, mode
            end

    other.ensure_open

    prim_reopen other

    self
  end

  ##
  # Positions ios to the beginning of input, resetting lineno to zero.
  #
  #  f = File.new("testfile")
  #  f.readline   #=> "This is line one\n"
  #  f.rewind     #=> 0
  #  f.lineno     #=> 0
  #  f.readline   #=> "This is line one\n"
  def rewind
    seek 0
    #ARGF.lineno -= @lineno
    @lineno = 0
    return 0
  end

  ##
  # Seeks to a given offset +amount+ in the stream according to the value of whence:
  #
  # IO::SEEK_CUR  | Seeks to _amount_ plus current position
  # --------------+----------------------------------------------------
  # IO::SEEK_END  | Seeks to _amount_ plus end of stream (you probably
  #               | want a negative value for _amount_)
  # --------------+----------------------------------------------------
  # IO::SEEK_SET  | Seeks to the absolute location given by _amount_
  # Example:
  #
  #  f = File.new("testfile")
  #  f.seek(-13, IO::SEEK_END)   #=> 0
  #  f.readline                  #=> "And so on...\n"
  def seek(amount, whence=SEEK_SET)
    flush

    @ibuffer.unseek! self
    @eof = false

    prim_seek amount, whence
  end

  ##
  # Returns status information for ios as an object of type File::Stat.
  #
  #  f = File.new("testfile")
  #  s = f.stat
  #  "%o" % s.mode   #=> "100644"
  #  s.blksize       #=> 4096
  #  s.atime         #=> Wed Apr 09 08:53:54 CDT 2003
  def stat
    ensure_open

    File::Stat.from_fd fileno
  end

  ##
  # Returns the current "sync mode" of ios. When sync mode is true,
  # all output is immediately flushed to the underlying operating
  # system and is not buffered by Ruby internally. See also IO#fsync.
  #
  #  f = File.new("testfile")
  #  f.sync   #=> false
  def sync
    ensure_open
    @sync == true
  end

  ##
  # Sets the "sync mode" to true or false. When sync mode is true,
  # all output is immediately flushed to the underlying operating
  # system and is not buffered internally. Returns the new state.
  # See also IO#fsync.
  def sync=(v)
    ensure_open
    @sync = (v and true)
  end

  ##
  # Reads integer bytes from ios using a low-level read and returns
  # them as a string. Do not mix with other methods that read from
  # ios or you may get unpredictable results. Raises SystemCallError 
  # on error and EOFError at end of file.
  #
  #  f = File.new("testfile")
  #  f.sysread(16)   #=> "This is line one"
  def sysread(size, buffer = nil)
    flush
    raise IOError unless @ibuffer.empty?
    raise ArgumentError, 'negative string size' unless size >= 0

    buffer = StringValue buffer if buffer

    chan = Channel.new
    Scheduler.send_on_readable chan, self, nil, size
    # waits until stream is ready for reading
    chan.receive
    str = blocking_read size
    raise EOFError if str.nil?

    buffer.replace str if buffer

    str
  end

  ##
  # Seeks to a given offset in the stream according to the value
  # of whence (see IO#seek for values of whence). Returns the new offset into the file.
  #
  #  f = File.new("testfile")
  #  f.sysseek(-13, IO::SEEK_END)   #=> 53
  #  f.sysread(10)                  #=> "And so on."
  def sysseek(amount, whence=SEEK_SET)
    ensure_open
    if @ibuffer.write_synced?
      raise IOError unless @ibuffer.empty?
    else
      Rubinius.warn 'sysseek for buffered IO'
    end

    amount = Integer(amount)

    prim_seek amount, whence
  end

  def to_io
    self
  end

  ##
  # Returns true if ios is associated with a terminal device (tty), false otherwise.
  #
  #  File.new("testfile").isatty   #=> false
  #  File.new("/dev/tty").isatty   #=> true
  def tty?
    ensure_open
    Platform::POSIX.isatty(@descriptor) == 1
  end

  alias_method :isatty, :tty?

  def wait_til_readable
    chan = Channel.new
    Scheduler.send_on_readable chan, self, nil, -1
    chan.receive
  end

  alias_method :prim_write, :write
  alias_method :prim_close, :close

  ##
  # Pushes back one character (passed as a parameter) onto ios,
  # such that a subsequent buffered read will return it. Only one
  # character may be pushed back before a subsequent read operation
  # (that is, you will be able to read only the last of several
  # characters that have been pushed back). Has no effect with
  # unbuffered reads (such as IO#sysread).
  #
  #  f = File.new("testfile")   #=> #<File:testfile>
  #  c = f.getc                 #=> 84
  #  f.ungetc(c)                #=> nil
  #  f.getc                     #=> 84
  def ungetc(chr)
    # HACK this doc block was on #write
    raise Exception, "IO#ungetc is not yet implemented"
  end

  def write(data)
    data = String data
    return 0 if data.length == 0

    ensure_open_and_writable

    @ibuffer.unseek! self
    bytes_to_write = data.size
    while bytes_to_write > 0
      bytes_to_write -= @ibuffer.unshift(data, data.size - bytes_to_write)
      @ibuffer.empty_to self if @ibuffer.full? or sync
    end

    data.size
  end

  def syswrite(data)
    data = String data
    return 0 if data.length == 0

    ensure_open_and_writable
    @ibuffer.unseek! self

    prim_write(data)
  end

  def close
    flush
    prim_close
  end

  alias_method :write_nonblock, :write

end

##
# Implements the pipe returned by IO::pipe.

class IO::BidirectionalPipe < IO

  READ_METHODS = [
    :each,
    :each_line,
    :getc,
    :gets,
    :read,
    :read_nonblock,
    :readchar,
    :readline,
    :readlines,
    :readpartial,
    :sysread,
  ]

  WRITE_METHODS = [
    :<<,
    :print,
    :printf,
    :putc,
    :puts,
    :syswrite,
    :write,
    :write_nonblock,
  ]

  def initialize(pid, read, write)
    @pid = pid
    @read = read
    @write = write
    @sync = true
  end

  def check_read
    raise IOError, 'not opened for reading' if @read.nil?
  end

  def check_write
    raise IOError, 'not opened for writing' if @write.nil?
  end

  ##
  # Closes ios and flushes any pending writes to the
  # operating system. The stream is unavailable for
  # any further data operations; an IOError is raised
  # if such an attempt is made. I/O streams are
  # automatically closed when they are claimed by
  # the garbage collector.
  #
  # If ios is opened by IO.popen, close sets $?.
  def close
    @read.close  if @read  and not @read.closed?
    @write.close if @write and not @write.closed?

    if @pid != 0 then
      Process.wait @pid

      @pid = 0
    end

    nil
  end

  def closed?
    if @read and @write then
      @read.closed? and @write.closed?
    elsif @read then
      @read.closed?
    else
      @write.closed?
    end
  end

  def close_read
    raise IOError, 'closed stream' if @read.closed?

    @read.close if @read
  end

  def close_write
    raise IOError, 'closed stream' if @write.closed?

    @write.close if @write
  end

  def method_missing(message, *args, &block)
    if READ_METHODS.include? message then
      check_read

      @read.send(message, *args, &block)
    elsif WRITE_METHODS.include? message then
      check_write

      @write.send(message, *args, &block)
    else
      super
    end
  end

  def pid
    raise IOError, 'closed stream' if closed?

    @pid
  end
end
