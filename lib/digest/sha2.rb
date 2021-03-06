#--
# sha2.rb - defines Digest::SHA2 class which wraps up the SHA256,
#           SHA384, and SHA512 classes.
#++
# Copyright (c) 2006 Akinori MUSHA <knu@iDaemons.org>
#
# All rights reserved.  You can redistribute and/or modify it under the same
# terms as Ruby.
#
#   $Id: sha2.rb 11708 2007-02-12 23:01:19Z shyouhei $

require 'digest'
require 'ext/digest/sha2/sha2'

Digest.create :SHA256, 'rbx_Digest_SHA256_Init', 'rbx_Digest_SHA256_Update',
              'rbx_Digest_SHA256_Finish', (4 * 8 + 8 + 64), 64, 32

Digest.create :SHA384, 'rbx_Digest_SHA384_Init', 'rbx_Digest_SHA384_Update',
              'rbx_Digest_SHA384_Finish', (8 * 8 + 8 * 2 + 128), 128, 48

Digest.create :SHA512, 'rbx_Digest_SHA512_Init', 'rbx_Digest_SHA512_Update',
              'rbx_Digest_SHA512_Finish', (8 * 8 + 8 * 2 + 128), 128, 64

module Digest
  #
  # A meta digest provider class for SHA256, SHA384 and SHA512.
  #
  class SHA2

    include Digest::Class

    # call-seq:
    #     Digest::SHA2.new(bitlen = 256) -> digest_obj
    #
    # Creates a new SHA2 hash object with a given bit length.
    def initialize(bitlen = 256)
      case bitlen
      when 256
        @sha2 = Digest::SHA256.new
      when 384
        @sha2 = Digest::SHA384.new
      when 512
        @sha2 = Digest::SHA512.new
      else
        raise ArgumentError, "unsupported bit length: %s" % bitlen.inspect
      end
      @bitlen = bitlen
    end

    # :nodoc:
    def reset
      @sha2.reset
      self
    end

    # :nodoc:
    def update(str)
      @sha2.update(str)
      self
    end
    alias << update

    def finish
      @sha2.digest!
    end
    private :finish

    def block_length
      @sha2.block_length
    end

    def digest_length
      @sha2.digest_length
    end

    # :nodoc:
    def initialize_copy(other)
      @sha2 = other.instance_eval { @sha2.clone }
    end

    # :nodoc:
    def inspect
      "#<%s:%d %s>" % [self.class.name, @bitlen, hexdigest]
    end
  end
end

