# frozen_string_literal: true

module SchemaFerry
  class Config
    attr_reader :source_url, :target_url,
                :global_type_overrides,
                :table_rules,
                :ignored_tables,
                :enum_mode

    class << self
      # Ruby entry point
      def build(&block)
        evaluate { |config| config.instance_eval(&block) }
      end

      # CLI entry point
      def load_file(path)
        evaluate { |config| config.instance_eval(File.read(path), path.to_s, 1) }
      end

      private

      def evaluate
        new.tap do |config|
          yield config
          config.validate!
        end
      end
    end

    def initialize
      @global_type_overrides = {}
      @table_rules           = Hash.new(TableRule::EMPTY)
      @ignored_tables        = []
      @enum_mode             = :string
    end

    def source(url)
      @source_url = url
    end

    def target(url)
      @target_url = url
    end

    def map_type(mysql_type, to:)
      @global_type_overrides[mysql_type.to_sym] = to.to_sym
    end

    def table(table_name, &)
      rule = TableRule.new(table_name)
      rule.instance_eval(&)
      @table_rules[table_name.to_s] = rule
    end

    def ignore_table(table_name)
      @ignored_tables << table_name.to_s
    end

    # How to convert MySQL enum columns:
    #   :string — plain varchar, values not enforced (default)
    #   :check  — varchar plus a CHECK constraint restricting the values
    def enum_as(mode)
      modes = %i[string check]
      unless modes.include?(mode.to_sym)
        raise ConfigError, "enum_as accepts #{modes.map(&:inspect).join(" or ")}, got #{mode.inspect}"
      end

      @enum_mode = mode.to_sym
    end

    def validate!
      raise ConfigError, 'source is not configured. Add: source "mysql2://..."' unless @source_url
      raise ConfigError, 'target is not configured. Add: target "postgresql://..."' unless @target_url
    end

    # Vocabulary available inside a `table :name do ... end` block.
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

      # Null object for tables without a `table ... do` block.
      EMPTY = new("").freeze
    end
  end
end
