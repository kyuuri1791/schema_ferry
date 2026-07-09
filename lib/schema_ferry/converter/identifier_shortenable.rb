# frozen_string_literal: true

require "digest"

module SchemaFerry
  module Converter
    # PostgreSQL truncates identifiers to 63 bytes (MySQL allows 64). A silently
    # truncated index name makes ridgepole see a diff on every run, so names that
    # would overflow are shortened deterministically instead.
    module IdentifierShortenable
      include Warnings

      MAX_BYTES   = 63
      HASH_LENGTH = 8

      def shorten_identifier(name, kind:, table:)
        return name if name.nil? || name.bytesize <= MAX_BYTES

        prefix = name.byteslice(0, MAX_BYTES - HASH_LENGTH - 1)
        short  = "#{prefix}_#{Digest::MD5.hexdigest(name)[0, HASH_LENGTH]}"
        emit_warning "#{table}: #{kind} name #{name.inspect} exceeds PostgreSQL's " \
                     "#{MAX_BYTES}-byte identifier limit; renamed to #{short.inspect}."
        short
      end
    end
  end
end
