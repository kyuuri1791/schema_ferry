# frozen_string_literal: true

module SchemaFerry
  class TableRule
    UNSET = Object.new.freeze
    private_constant :UNSET

    EXTRA_INDEX_OPTIONS = %i[name unique using where opclass order].freeze

    attr_reader :table_name, :column_type_overrides,
                :column_default_overrides, :ignored_columns, :ignored_indexes,
                :extra_indexes

    def initialize(table_name)
      @table_name               = table_name.to_s
      @column_type_overrides    = {}
      @column_default_overrides = {}
      @ignored_columns          = []
      @ignored_indexes          = []
      @extra_indexes            = []
    end

    def map_column(column_name, type:, default: UNSET)
      @column_type_overrides[column_name.to_s] = type.to_sym
      @column_default_overrides[column_name.to_s] = default unless default.equal?(UNSET)
    end

    def ignore_column(column_name)
      @ignored_columns << column_name.to_s
    end

    def ignore_index(index_name)
      @ignored_indexes << index_name.to_s
    end

    # Declares a PostgreSQL-side index that does not exist in MySQL (e.g. a
    # pg_trgm GIN index replacing a skipped FULLTEXT index). Declared indexes
    # are part of the generated schema, so sync keeps them.
    def add_index(*columns, **options)
      unknown = options.keys - EXTRA_INDEX_OPTIONS
      unless unknown.empty?
        raise ConfigError, "add_index: unknown option(s) #{unknown.map(&:inspect).join(", ")} " \
                           "(allowed: #{EXTRA_INDEX_OPTIONS.map(&:inspect).join(", ")})"
      end

      @extra_indexes << { columns: columns.map(&:to_s), options: options }
    end
  end
end
