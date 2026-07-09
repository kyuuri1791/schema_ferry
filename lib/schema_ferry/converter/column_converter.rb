# frozen_string_literal: true

module SchemaFerry
  module Converter
    class ColumnConverter
      include Warnings

      # PG has no unsigned integers: bump to the next size that holds the full
      # unsigned range. Keys/values are AR byte limits.
      UNSIGNED_LIMIT_BUMP = { 1 => 2, 2 => 4, 3 => 4, 4 => 8 }.freeze

      def initialize(type_mapper)
        @type_mapper = type_mapper
      end

      def call(raw, table_name, rule, fk_columns = [])
        raw      = bump_unsigned_integer(raw, table_name, fk_columns.include?(raw[:name]))
        raw      = drop_zero_date_default(raw, table_name)
        override = rule&.column_type_overrides&.[](raw[:name])
        col_opts = raw.slice(:limit, :precision, :scale, :null, :default, :default_function, :comment)

        if override
          col_opts[:default] = override_default(raw, rule, override)
          ColumnSchema.new(name: raw[:name], type: override, **col_opts)
        else
          pg_type, pg_opts = @type_mapper.call(raw[:type], col_opts)
          ColumnSchema.new(name: raw[:name], type: pg_type, **pg_opts)
        end
      end

      private

      def bump_unsigned_integer(raw, table_name, fk_column)
        return raw unless raw[:type] == :integer && raw[:sql_type].to_s.include?("unsigned")

        if raw[:limit] != 8
          raw.merge(limit: UNSIGNED_LIMIT_BUMP.fetch(raw[:limit], raw[:limit]))
        elsif fk_column
          # decimal(20, 0) cannot be a foreign key to a bigint primary key, so
          # FK columns follow the primary-key conversion (signed bigint) instead.
          emit_warning "#{table_name}.#{raw[:name]}: BIGINT UNSIGNED takes part in a foreign key; " \
                       "mapped to signed bigint to match the referenced key " \
                       "(values above 2^63-1 will not fit)."
          raw
        else
          emit_warning "column #{raw[:name].inspect}: BIGINT UNSIGNED has no PostgreSQL " \
                       "integer equivalent; mapped to decimal(20, 0)."
          raw.merge(type: :decimal, limit: nil, precision: 20, scale: 0)
        end
      end

      # MySQL zero dates ('0000-00-00' …) are invalid on PostgreSQL. AR already
      # nils out zero DATE defaults, but zero DATETIME defaults come through as
      # strings.
      def drop_zero_date_default(raw, table_name)
        return raw unless raw[:default].is_a?(String) && raw[:default].start_with?("0000-00-00")

        emit_warning "#{table_name}.#{raw[:name]}: default #{raw[:default].inspect} is " \
                     "invalid on PostgreSQL; the default was dropped."
        raw.merge(default: nil)
      end

      # AR reads tinyint(1) defaults as booleans (DEFAULT 2 becomes true), so a
      # default is unreliable once the type is overridden away from :boolean.
      def override_default(raw, rule, override)
        defaults = rule.column_default_overrides
        return defaults[raw[:name]] if defaults.key?(raw[:name])

        default = raw[:default]
        if [true, false].include?(default) && override != :boolean
          emit_warning "#{rule.table_name}.#{raw[:name]}: dropping default #{default.inspect} — " \
                       "MySQL reported a tinyint(1) default as boolean, which is unreliable under " \
                       "a type override. Restore it explicitly: " \
                       "column :#{raw[:name]}, map_type_to: :#{override}, default: <value>"
          return nil
        end
        default
      end
    end
  end
end
