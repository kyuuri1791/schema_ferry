# frozen_string_literal: true

module SchemaFerry
  module Core
    class Translator
      def initialize(config)
        @config           = config
        @column_converter = ColumnConverter.new(TypeMapper.new(config.global_type_overrides))
        @enum_check       = (EnumCheckBuilder.new if config.enum_mode == :check)
      end

      def translate(raw_tables)
        kept_tables  = raw_tables.reject { |t| @config.ignored_tables.include?(t[:name]) }
        foreign_keys = kept_tables.to_h { |t| [t[:name], surviving_foreign_keys(t)] }
        fk_columns   = collect_fk_columns(foreign_keys)

        pg_tables = kept_tables.map do |raw|
          TableConverter.new(
            raw,
            rule:             @config.table_rules[raw[:name]],
            foreign_keys:     foreign_keys.fetch(raw[:name]),
            fk_columns:       fk_columns.fetch(raw[:name], []),
            column_converter: @column_converter,
            enum_check:       @enum_check
          ).convert
        end

        SchemafileRenderer.new.render(pg_tables)
      end

      private

      def surviving_foreign_keys(raw)
        ignored = @config.table_rules[raw[:name]].ignored_columns
        raw[:foreign_keys]
          .reject { |fk| @config.ignored_tables.include?(fk[:to_table]) }
          .reject { |fk| ignored.include?(fk[:column]) }
      end

      # Columns on either side of a surviving foreign key must land in
      # PostgreSQL's integer type family: a numeric(20, 0) column cannot
      # reference a bigint key.
      def collect_fk_columns(foreign_keys_by_table)
        foreign_keys_by_table.each_with_object({}) do |(table_name, fks), acc|
          fks.each do |fk|
            (acc[table_name] ||= []) << fk[:column]
            (acc[fk[:to_table]] ||= []) << fk[:primary_key]
          end
        end
      end
    end
  end
end
