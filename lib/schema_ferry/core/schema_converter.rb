# frozen_string_literal: true

module SchemaFerry
  module Core
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
        rule = @table_rules[raw[:name]]
        check_table_name_length!(raw[:name])
        pk_col = primary_key_column(raw)

        TableSchema.new(
          name:              raw[:name],
          primary_key:       raw[:primary_key],
          pk_type:           convert_pk_type(raw[:name], pk_col),
          pk_limit:          convert_pk_limit(pk_col),
          comment:           raw[:comment].presence,
          columns:           convert_columns(data_columns(raw), raw[:name], rule, fk_columns),
          indexes:           convert_indexes(raw[:indexes], raw[:name], rule),
          foreign_keys:      convert_foreign_keys(raw),
          check_constraints: build_check_constraints(raw, rule)
        )
      end

      def primary_key_column(raw)
        pk = raw[:primary_key]
        pk.is_a?(String) ? raw[:columns].find { |c| c[:name] == pk } : nil
      end

      # A single-column PK is rendered via create_table's id: option, so it is
      # excluded from the column list. Composite PK columns must stay:
      # primary_key: [...] does not create them.
      def data_columns(raw)
        raw[:columns].reject { |c| c[:name] == raw[:primary_key] }
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
        ignored = @table_rules[raw[:name]].ignored_columns
        raw[:foreign_keys]
          .reject { |fk| @ignored_tables.include?(fk[:to_table]) }
          .reject { |fk| ignored.include?(fk[:column]) }
      end

      # MySQL BIGINT comes through AR as :integer with limit 8, so the sql_type
      # is the only reliable source for the id: option.
      def convert_pk_type(table_name, pk_col)
        return nil if pk_col.nil?
        return pk_col[:type] unless pk_col[:type] == :integer

        sql_type = pk_col[:sql_type].to_s
        if sql_type.include?("unsigned")
          if sql_type.start_with?("bigint")
            emit_warning "table #{table_name}: BIGINT UNSIGNED primary key has no PostgreSQL " \
                         "equivalent; using signed bigint (values above 2^63-1 will not fit)."
          end
          :bigint
        elsif sql_type.start_with?("bigint")
          :bigint
        else
          :integer
        end
      end

      def convert_pk_limit(pk_col)
        pk_col[:limit] if pk_col && pk_col[:type] == :string
      end

      def convert_columns(raw_columns, table_name, rule, fk_columns)
        raw_columns
          .reject { |c| rule.ignored_columns.include?(c[:name]) }
          .map do |c|
            check_spatial_type!(c, table_name, rule)
            @column_converter.call(c, table_name, rule, fk_columns)
          end
      end

      def check_spatial_type!(raw, table_name, rule)
        return if rule.column_type_overrides.key?(raw[:name]) # handled downstream, like any other override

        if raw[:sql_type].to_s.match?(SPATIAL_SQL_TYPES)
          raise ConversionError, "#{table_name}.#{raw[:name]}: MySQL #{raw[:sql_type]} columns have no " \
                                 "PostgreSQL equivalent without PostGIS, which schema_ferry does not " \
                                 "manage. Exclude it with ignore_column :#{raw[:name]}."
        end
      end

      def convert_indexes(raw_indexes, table_name, rule)
        raw_indexes
          .reject { |idx| rule.ignored_indexes.include?(idx[:name]) }
          .reject { |idx| idx[:columns].intersect?(rule.ignored_columns) }
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
        IndexSchema.new(
          name:    shorten_identifier(raw[:name], kind: "index", table: table_name),
          columns: raw[:columns],
          unique:  raw[:unique],
          using:   raw[:using],
          # AR reports "no prefix lengths / orders" as an empty hash; rendering
          # a literal lengths: {} would make ridgepole re-create the index on
          # every run.
          lengths: raw[:lengths].presence,
          orders:  raw[:orders].presence
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
          name:        shorten_identifier(raw[:name], kind: "foreign key", table: raw[:from_table])
        )
      end

      def build_check_constraints(raw, rule)
        return [] unless @enum_check

        @enum_check.call(raw, rule)
      end
    end
  end
end
