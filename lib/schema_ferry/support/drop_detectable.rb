# frozen_string_literal: true

module SchemaFerry
  module Support
    module DropDetectable
      DROP_LINE = /^(?:drop_table|remove_column|remove_index|remove_foreign_key|
                      remove_check_constraint|remove_exclusion_constraint|
                      remove_unique_constraint)\(.*\)$/x

      private

      def detect_drops(ddl)
        ddl.each_line.map(&:chomp).grep(DROP_LINE)
      end
    end
  end
end
