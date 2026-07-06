# frozen_string_literal: true

module SchemaFerry
  module Converter
    class TypeMapper
      # PG has no limit concept for text/binary/bigint/float; drop the
      # MySQL-derived limits (float's limit: 53 is DOUBLE's internal bit
      # width, not something AR ever reads back from a PG column).
      LIMIT_STRIPPED_TYPES = %i[text binary bigint float].freeze

      # PG's default timestamp precision is 6. Spelling it out makes ridgepole
      # see a diff against the PG export (which omits it) on every run.
      DEFAULT_PRECISION_TYPES = %i[datetime time].freeze
      PG_DEFAULT_PRECISION    = 6

      # ActiveRecord's PostgreSQL adapter never honors a precision option on
      # :timestamptz (only :datetime/:timestamp/:time do — see
      # ActiveRecord::ConnectionAdapters::SchemaStatements#type_to_sql).
      # Declaring one is always a lie, so it must never be emitted.
      NO_PRECISION_TYPES = %i[timestamptz].freeze

      DEFAULTS = {
        json: :jsonb
      }.freeze

      KNOWN_TYPES = %i[
        string text integer bigint float decimal
        datetime date time boolean binary json jsonb
      ].freeze

      def initialize(global_overrides = {})
        @overrides = DEFAULTS.merge(global_overrides)
      end

      # Returns [pg_type_sym, adjusted_options_hash]
      def call(ar_type, options = {})
        unless KNOWN_TYPES.include?(ar_type)
          raise ConversionError, "Unknown MySQL AR type: #{ar_type.inspect}. " \
                                 "Use map_type or map_column to specify a PostgreSQL type."
        end

        pg_type  = @overrides.fetch(ar_type, ar_type)
        adjusted = options.dup
        pg_type, adjusted = normalize_integer(adjusted) if pg_type == :integer
        adjusted.delete(:limit) if LIMIT_STRIPPED_TYPES.include?(pg_type)
        strip_default_precision(pg_type, adjusted)
        if pg_type == :decimal
          # PG numeric(20) equals numeric(20,0) and is exported without scale.
          adjusted[:scale] = nil if adjusted[:scale]&.zero?
          # AR's schema dumper renders decimal defaults as a string (e.g.
          # `default: "0"`), not a numeric literal. ridgepole compares against
          # that dumped form, so a BigDecimal/Integer default never matches
          # and gets re-applied on every run.
          adjusted[:default] = adjusted[:default]&.to_s
        end

        [pg_type, adjusted]
      end

      private

      # MySQL reports every integer flavor as :integer with a byte limit; PG only
      # has smallint(2) / integer(4) / bigint(8). Emit the shape ridgepole
      # exports for PG so repeated runs see no diff.
      def normalize_integer(options)
        case options[:limit]
        when nil  then [:integer, options]
        when 1, 2 then [:integer, options.merge(limit: 2)]
        when 3, 4 then [:integer, options.merge(limit: nil)]
        else           [:bigint,  options.merge(limit: nil)]
        end
      end

      def strip_default_precision(pg_type, options)
        options[:precision] = nil if NO_PRECISION_TYPES.include?(pg_type)
        return unless DEFAULT_PRECISION_TYPES.include?(pg_type)

        options[:precision] = nil if options[:precision] == PG_DEFAULT_PRECISION
      end
    end
  end
end
