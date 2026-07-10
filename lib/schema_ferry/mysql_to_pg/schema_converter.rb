# frozen_string_literal: true

module SchemaFerry
  module MysqlToPg
    class SchemaConverter
      include Support::Warnings
      include IdentifierShortenable

      UNSUPPORTED_INDEX_TYPES = %i[fulltext spatial].freeze
      SPATIAL_SQL_TYPES = /\A(?:geometry|point|linestring|polygon|multipoint|multilinestring|multipolygon|
                              geometrycollection)\z/ix

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
        check_table_name_length!(raw[:name])

        Support::TableSchema.new(
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

      def check_table_name_length!(name)
        return if name.bytesize <= MAX_BYTES

        raise ConversionError, "table name #{name.inspect} exceeds PostgreSQL's #{MAX_BYTES}-byte " \
                               "identifier limit. Exclude it with ignore_table :#{name}, or rename it in MySQL."
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
            check_spatial_type!(c, table_name, rule)
            @column_converter.call(c, table_name, rule, fk_columns)
          end
      end

      def check_spatial_type!(raw, table_name, rule)
        return if rule&.column_type_overrides&.key?(raw[:name]) # handled downstream, like any other override

        if raw[:sql_type].to_s.match?(SPATIAL_SQL_TYPES)
          raise ConversionError, "#{table_name}.#{raw[:name]}: MySQL #{raw[:sql_type]} columns have no " \
                                 "PostgreSQL equivalent without PostGIS, which schema_ferry does not " \
                                 "manage. Exclude it with ignore_column :#{raw[:name]}."
        end
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

      def check_unsupported_index_type!(idx, table_name)
        if UNSUPPORTED_INDEX_TYPES.include?(idx[:type])
          raise ConversionError, "#{table_name}: #{idx[:type].to_s.upcase} index #{idx[:name].inspect} " \
                                 "has no PostgreSQL equivalent. Exclude it with ignore_index :#{idx[:name]}."
        end
      end

      def build_index_schema(raw, table_name)
        Support::IndexSchema.new(
          name:    shorten_identifier(raw[:name], kind: "index", table: table_name),
          columns: raw[:columns],
          unique:  raw[:unique],
          using:   raw[:using],
          lengths: raw[:lengths],
          orders:  raw[:orders]
        )
      end

      def build_fk_schema(raw)
        Support::ForeignKeySchema.new(
          from_table:  raw[:from_table],
          to_table:    raw[:to_table],
          column:      raw[:column],
          primary_key: raw[:primary_key],
          on_update:   raw[:on_update],
          on_delete:   raw[:on_delete],
          name:        shorten_identifier(raw[:name], kind: "foreign key", table: raw[:from_table])
        )
      end

      def build_check_constraints(raw, rule, ignored)
        return [] unless @enum_check

        @enum_check.call(raw, rule, ignored)
      end
    end
  end
end
