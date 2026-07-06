# frozen_string_literal: true

module SchemaFerry
  module Converter
    class SchemaConverter
      include Warnings

      # PostgreSQL has no FULLTEXT/SPATIAL equivalent that ridgepole can express.
      UNSUPPORTED_INDEX_TYPES = %i[fulltext spatial].freeze

      # MySQL spatial column types have no PostgreSQL equivalent (that would
      # require PostGIS, which schema_ferry does not manage). Most of these
      # already raise TypeMapper's ConversionError, since ActiveRecord's
      # mysql2 adapter reports them as an unrecognized type (nil). POINT is
      # the sole exception: AR matches sql_type against an unanchored /int/i
      # regex (see register_class_with_limit in
      # ActiveRecord::ConnectionAdapters::AbstractAdapter#initialize_type_map),
      # which matches "point" as a substring — so it's misreported as plain
      # :integer instead. Without this check it would sail through as a
      # meaningless integer column instead of raising. It must be caught
      # here, by sql_type, and raised explicitly — the same failure mode as
      # any other unsupported type, not a warning that's easy to miss in a
      # cron log.
      MISDETECTED_SPATIAL_SQL_TYPE = /\Apoint\b/i

      def initialize(config)
        @column_converter = ColumnConverter.new(TypeMapper.new(config.global_type_overrides))
        @table_rules      = config.table_rules
        @ignored_tables   = config.ignored_tables
        @enum_check       = (EnumCheckBuilder.new if config.enum_mode == :check)
      end

      def convert(raw_tables)
        kept_tables = raw_tables.reject { |t| @ignored_tables.include?(t[:name]) }
        fk_columns  = collect_fk_columns(kept_tables)
        kept_tables.map { |t| convert_table(t, fk_columns.fetch(t[:name], [])) }
      end

      private

      def convert_table(raw, fk_columns)
        rule    = @table_rules[raw[:name]]
        ignored = rule&.ignored_columns || []
        IdentifierShortener.warn_long_table_name(raw[:name])

        TableSchema.new(
          name:              raw[:name],
          primary_key:       raw[:primary_key],
          pk_type:           convert_pk_type(raw),
          pk_limit:          raw[:pk_limit],
          comment:           raw[:comment],
          columns:           convert_columns(raw[:columns], raw[:name], rule, ignored, fk_columns),
          indexes:           convert_indexes(raw[:indexes], raw[:name], rule, ignored),
          foreign_keys:      convert_foreign_keys(raw),
          check_constraints: build_check_constraints(raw, rule, ignored)
        )
      end

      # Columns on either side of a surviving foreign key must land in
      # PostgreSQL's integer type family: a numeric(20, 0) column cannot
      # reference a bigint key.
      def collect_fk_columns(raw_tables)
        raw_tables.each_with_object({}) do |raw, acc|
          surviving_foreign_keys(raw).each do |fk|
            (acc[raw[:name]] ||= []) << fk[:column]
            (acc[fk[:to_table]] ||= []) << fk[:primary_key]
          end
        end
      end

      def surviving_foreign_keys(raw)
        ignored = @table_rules[raw[:name]]&.ignored_columns || []
        raw[:foreign_keys]
          .reject { |fk| @ignored_tables.include?(fk[:to_table]) }
          .reject { |fk| ignored.include?(fk[:column]) }
      end

      # MySQL BIGINT comes through AR as :integer with limit 8, so the sql_type
      # is the only reliable source for the id: option.
      def convert_pk_type(raw)
        return raw[:pk_type] unless raw[:pk_type] == :integer

        sql_type = raw[:pk_sql_type].to_s
        if sql_type.include?("unsigned")
          if sql_type.start_with?("bigint")
            emit_warning "table #{raw[:name]}: BIGINT UNSIGNED primary key has no PostgreSQL " \
                         "equivalent; using signed bigint (values above 2^63-1 will not fit)."
          end
          :bigint
        elsif sql_type.start_with?("bigint")
          :bigint
        else
          :integer
        end
      end

      def convert_columns(raw_columns, table_name, rule, ignored, fk_columns)
        raw_columns
          .reject { |c| ignored.include?(c[:name]) }
          .map do |c|
            check_misdetected_spatial_type!(c, table_name, rule)
            @column_converter.call(c, table_name, rule, fk_columns)
          end
      end

      # map_column already lets a rule override any column's type before it
      # ever reaches this check (ColumnConverter#call skips TypeMapper
      # entirely when an override is present), same as for any other type.
      def check_misdetected_spatial_type!(raw, table_name, rule)
        return unless raw[:sql_type].to_s.match?(MISDETECTED_SPATIAL_SQL_TYPE)
        return if rule&.column_type_overrides&.key?(raw[:name])

        raise ConversionError, "#{table_name}.#{raw[:name]}: MySQL #{raw[:sql_type]} columns have no " \
                               "PostgreSQL equivalent without PostGIS, which schema_ferry does not " \
                               "manage. Exclude it with ignore_column :#{raw[:name]}."
      end

      def convert_indexes(raw_indexes, table_name, rule, ignored)
        raw_indexes
          .reject { |idx| rule&.ignored_indexes&.include?(idx[:name]) }
          .reject { |idx| idx[:columns].intersect?(ignored) }
          .map do |idx|
            check_unsupported_index_type!(idx, table_name)
            build_index_schema(idx, table_name)
          end
      end

      def convert_foreign_keys(raw)
        surviving_foreign_keys(raw).map { |fk| build_fk_schema(fk) }
      end

      # A warning here would be easy to miss in an unattended cron run.
      # Raising makes this failure show up the same way as any other error:
      # a non-zero exit status a monitor can catch.
      def check_unsupported_index_type!(idx, table_name)
        return unless UNSUPPORTED_INDEX_TYPES.include?(idx[:type])

        raise ConversionError, "#{table_name}: #{idx[:type].to_s.upcase} index #{idx[:name].inspect} " \
                               "has no PostgreSQL equivalent. Exclude it with ignore_index :#{idx[:name]}."
      end

      def build_index_schema(raw, table_name)
        IndexSchema.new(
          name:    IdentifierShortener.shorten(raw[:name], kind: "index", table: table_name),
          columns: raw[:columns],
          unique:  raw[:unique],
          using:   raw[:using],
          lengths: raw[:lengths],
          orders:  raw[:orders]
        )
      end

      def build_fk_schema(raw)
        ForeignKeySchema.new(
          from_table:  raw[:from_table],
          to_table:    raw[:to_table],
          column:      raw[:column],
          primary_key: raw[:primary_key],
          on_update:   raw[:on_update],
          on_delete:   raw[:on_delete],
          name:        IdentifierShortener.shorten(raw[:name], kind: "foreign key", table: raw[:from_table])
        )
      end

      def build_check_constraints(raw, rule, ignored)
        return [] unless @enum_check

        @enum_check.call(raw, rule, ignored)
      end
    end
  end
end
