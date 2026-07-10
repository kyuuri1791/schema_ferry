# frozen_string_literal: true

module SchemaFerry
  module Core
    class TableConverter
      include Support::Warnings
      include IdentifierShortenable

      UNSUPPORTED_INDEX_TYPES = %i[fulltext spatial].freeze
      SPATIAL_SQL_TYPES = /\A(?:geometry|point|linestring|polygon|multipoint|multilinestring|multipolygon|
                              geometrycollection)\z/ix

      def initialize(raw, rule:, foreign_keys:, fk_columns:, column_converter:, enum_check:)
        @raw              = raw
        @name             = raw[:name]
        @rule             = rule
        @foreign_keys     = foreign_keys
        @fk_columns       = fk_columns
        @column_converter = column_converter
        @enum_check       = enum_check
      end

      def convert
        check_table_name_length!

        TableSchema.new(
          name:              @name,
          primary_key:       @raw[:primary_key],
          pk_type:           convert_pk_type,
          pk_limit:          convert_pk_limit,
          comment:           @raw[:comment].presence,
          columns:           convert_columns,
          indexes:           convert_indexes,
          foreign_keys:      convert_foreign_keys,
          check_constraints: build_check_constraints
        )
      end

      private

      def check_table_name_length!
        return if @name.bytesize <= MAX_BYTES

        raise ConversionError, "table name #{@name.inspect} exceeds PostgreSQL's #{MAX_BYTES}-byte " \
                               "identifier limit. Exclude it with ignore_table :#{@name}, or rename it in MySQL."
      end

      def pk_column
        pk = @raw[:primary_key]
        pk.is_a?(String) ? @raw[:columns].find { |c| c[:name] == pk } : nil
      end

      # A single-column PK is rendered via create_table's id: option, so it is
      # excluded from the column list. Composite PK columns must stay:
      # primary_key: [...] does not create them.
      def data_columns
        @raw[:columns].reject { |c| c[:name] == @raw[:primary_key] }
      end

      # MySQL BIGINT comes through AR as :integer with limit 8, so the sql_type
      # is the only reliable source for the id: option.
      def convert_pk_type
        col = pk_column
        return nil if col.nil?
        return col[:type] unless col[:type] == :integer

        sql_type = col[:sql_type].to_s
        if sql_type.include?("unsigned")
          if sql_type.start_with?("bigint")
            emit_warning "table #{@name}: BIGINT UNSIGNED primary key has no PostgreSQL " \
                         "equivalent; using signed bigint (values above 2^63-1 will not fit)."
          end
          :bigint
        elsif sql_type.start_with?("bigint")
          :bigint
        else
          :integer
        end
      end

      def convert_pk_limit
        col = pk_column
        col[:limit] if col && col[:type] == :string
      end

      def convert_columns
        data_columns
          .reject { |c| @rule.ignored_columns.include?(c[:name]) }
          .map do |c|
            check_spatial_type!(c)
            @column_converter.call(c, @name, @rule, @fk_columns)
          end
      end

      def check_spatial_type!(col)
        return if @rule.column_type_overrides.key?(col[:name]) # handled downstream, like any other override

        if col[:sql_type].to_s.match?(SPATIAL_SQL_TYPES)
          raise ConversionError, "#{@name}.#{col[:name]}: MySQL #{col[:sql_type]} columns have no " \
                                 "PostgreSQL equivalent without PostGIS, which schema_ferry does not " \
                                 "manage. Exclude it with ignore_column :#{col[:name]}."
        end
      end

      def convert_indexes
        @raw[:indexes]
          .reject { |idx| @rule.ignored_indexes.include?(idx[:name]) }
          .reject { |idx| idx[:columns].intersect?(@rule.ignored_columns) }
          .map do |idx|
            check_unsupported_index_type!(idx)
            build_index_schema(idx)
          end
      end

      def check_unsupported_index_type!(idx)
        if UNSUPPORTED_INDEX_TYPES.include?(idx[:type])
          raise ConversionError, "#{@name}: #{idx[:type].to_s.upcase} index #{idx[:name].inspect} " \
                                 "has no PostgreSQL equivalent. Exclude it with ignore_index :#{idx[:name]}."
        end
      end

      def build_index_schema(idx)
        IndexSchema.new(
          name:    shorten_identifier(idx[:name], kind: "index", table: @name),
          columns: idx[:columns],
          unique:  idx[:unique],
          using:   idx[:using],
          # AR reports "no prefix lengths / orders" as an empty hash; rendering
          # a literal lengths: {} would make ridgepole re-create the index on
          # every run.
          lengths: idx[:lengths].presence,
          orders:  idx[:orders].presence
        )
      end

      def convert_foreign_keys
        @foreign_keys.map { |fk| build_fk_schema(fk) }
      end

      def build_fk_schema(foreign_key)
        ForeignKeySchema.new(
          from_table:  foreign_key[:from_table],
          to_table:    foreign_key[:to_table],
          column:      foreign_key[:column],
          primary_key: foreign_key[:primary_key],
          on_update:   foreign_key[:on_update],
          on_delete:   foreign_key[:on_delete],
          name:        shorten_identifier(foreign_key[:name], kind: "foreign key", table: foreign_key[:from_table])
        )
      end

      def build_check_constraints
        return [] unless @enum_check

        @enum_check.call(@raw, @rule)
      end
    end
  end
end
