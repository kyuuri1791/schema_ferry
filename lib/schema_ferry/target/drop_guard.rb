# frozen_string_literal: true

module SchemaFerry
  module Target
    module DropGuard
      DROP_LINE = /^(?:drop_table|remove_column|remove_index|remove_foreign_key|
                      remove_check_constraint|remove_exclusion_constraint|
                      remove_unique_constraint)\(.*\)$/x

      def self.check!(dry_run_output)
        drops = dry_run_output.each_line.map(&:chomp).grep(DROP_LINE)
        return if drops.empty?

        raise DropNotAllowedError,
              "refused: the diff contains destructive change(s):\n#{drops.join("\n")}"
      end
    end
  end
end
