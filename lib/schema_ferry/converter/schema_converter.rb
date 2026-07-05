# frozen_string_literal: true

module SchemaFerry
  module Converter
    class SchemaConverter
      include Warnings

      # PostgreSQL has no FULLTEXT/SPATIAL equivalent that ridgepole can express.
      UNSUPPORTED_INDEX_TYPES = %i[fulltext spatial].freeze

      def initialize(config)
        @column_converter = ColumnConverter.new(TypeMapper.new(config.global_type_overrides))
        @table_rules      = config.table_rules
        @ignored_tables   = config.ignored_tables
        @enum_check       = (EnumCheckBuilder.new if config.enum_mode == :check)
      end

      def convert(raw_tables)
        raw_tables
          .reject { |t| @ignored_tables.include?(t[:name]) }
          .map    { |t| convert_table(t) }
      end

      private

      def convert_table(raw)
        rule    = @table_rules[raw[:name]]
        ignored = rule&.ignored_columns || []
        IdentifierShortener.warn_long_table_name(raw[:name])

        TableSchema.new(
          name:              raw[:name],
          primary_key:       raw[:primary_key],
          pk_type:           convert_pk_type(raw),
          pk_limit:          raw[:pk_limit],
          comment:           raw[:comment],
          columns:           convert_columns(raw[:columns], raw[:name], rule, ignored),
          indexes:           convert_indexes(raw[:indexes], raw[:name], rule, ignored),
          foreign_keys:      convert_foreign_keys(raw[:foreign_keys], ignored),
          check_constraints: build_check_constraints(raw, rule, ignored)
        )
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

      def convert_columns(raw_columns, table_name, rule, ignored)
        raw_columns
          .reject { |c| ignored.include?(c[:name]) }
          .map    { |c| @column_converter.call(c, table_name, rule) }
      end

      def convert_indexes(raw_indexes, table_name, rule, ignored)
        converted = raw_indexes
                    .reject { |idx| rule&.ignored_indexes&.include?(idx[:name]) }
                    .reject { |idx| skip_unsupported_index?(idx, table_name) }
                    .reject { |idx| idx[:columns].intersect?(ignored) }
                    .map    { |idx| build_index_schema(idx, table_name) }
        converted + extra_indexes(rule, table_name)
      end

      def extra_indexes(rule, table_name)
        (rule&.extra_indexes || []).map do |extra|
          opts = extra[:options]
          name = opts[:name] || "index_#{table_name}_on_#{extra[:columns].join("_")}"
          IndexSchema.new(
            name:    IdentifierShortener.shorten(name.to_s, kind: "index", table: table_name),
            columns: extra[:columns],
            unique:  opts[:unique],
            using:   opts[:using],
            opclass: opts[:opclass],
            where:   opts[:where],
            orders:  opts[:order],
            lengths: nil
          )
        end
      end

      def convert_foreign_keys(raw_fkeys, ignored)
        raw_fkeys
          .reject { |fk| @ignored_tables.include?(fk[:to_table]) }
          .reject { |fk| ignored.include?(fk[:column]) }
          .map    { |fk| build_fk_schema(fk) }
      end

      def skip_unsupported_index?(idx, table_name)
        return false unless UNSUPPORTED_INDEX_TYPES.include?(idx[:type])

        emit_warning "#{table_name}: skipping #{idx[:type].to_s.upcase} index #{idx[:name].inspect} " \
                     "(no PostgreSQL equivalent). Declare a replacement with add_index " \
                     "(e.g. add_index :col, using: :gin, opclass: :gin_trgm_ops) and " \
                     "silence this warning with ignore_index :#{idx[:name]}."
        true
      end

      def build_index_schema(raw, table_name)
        IndexSchema.new(
          name:    IdentifierShortener.shorten(raw[:name], kind: "index", table: table_name),
          columns: raw[:columns],
          unique:  raw[:unique],
          using:   raw[:using],
          opclass: nil, # MySQL has no operator classes
          where:   raw[:where],
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
