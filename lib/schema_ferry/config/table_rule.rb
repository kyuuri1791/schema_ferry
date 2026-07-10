# frozen_string_literal: true

module SchemaFerry
  class Config
    class TableRule
      UNSET = Object.new.freeze
      private_constant :UNSET

      attr_reader :table_name, :column_type_overrides,
                  :column_default_overrides, :ignored_columns, :ignored_indexes

      def initialize(table_name)
        @table_name               = table_name.to_s
        @column_type_overrides    = {}
        @column_default_overrides = {}
        @ignored_columns          = []
        @ignored_indexes          = []
      end

      def column(column_name, map_type_to:, default: UNSET)
        @column_type_overrides[column_name.to_s] = map_type_to.to_sym
        @column_default_overrides[column_name.to_s] = default unless default.equal?(UNSET)
      end

      def ignore_column(column_name)
        @ignored_columns << column_name.to_s
      end

      def ignore_index(index_name)
        @ignored_indexes << index_name.to_s
      end
    end
  end
end
