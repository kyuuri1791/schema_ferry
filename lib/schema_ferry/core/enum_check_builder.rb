# frozen_string_literal: true

module SchemaFerry
  module Core
    # Builds CHECK constraints enforcing MySQL enum values on varchar columns
    # (enum_as :check).
    class EnumCheckBuilder
      include IdentifierShortenable

      def call(raw_table, rule)
        raw_table[:columns].filter_map do |col|
          next if rule.ignored_columns.include?(col[:name])
          # A type override takes the column away from varchar; the caller owns
          # any constraint then.
          next if rule.column_type_overrides.key?(col[:name])

          values = enum_values(col[:sql_type])
          next if values.nil?

          build_constraint(raw_table[:name], col[:name], values)
        end
      end

      private

      def build_constraint(table_name, col_name, values)
        CheckConstraintSchema.new(
          expression: expression(col_name, values),
          name:       shorten_identifier("chk_#{table_name}_#{col_name}",
                                         kind: "check constraint", table: table_name)
        )
      end

      # "enum('a','b')" → ["a", "b"] (values keep MySQL's quote escaping).
      def enum_values(sql_type)
        return nil unless sql_type.to_s.start_with?("enum(")

        sql_type.scan(/'((?:[^']|'')*)'/).flatten
      end

      # PG stores CHECK expressions normalized; this is the fixed point of that
      # normalization for a varchar column (verified on PG 16). Anything else —
      # e.g. "kind IN ('a', 'b')" — makes ridgepole re-create it on every run.
      def expression(column, values)
        list = values.map { |v| "'#{v}'::character varying::text" }.join(", ")
        "#{column}::text = ANY (ARRAY[#{list}])"
      end
    end
  end
end
