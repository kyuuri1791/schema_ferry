# frozen_string_literal: true

module SchemaFerry
  # Mix in (include for classes, extend for module_function modules) to emit
  # "[schema_ferry]"-prefixed warnings to stderr.
  module Warnings
    private

    def emit_warning(message)
      Kernel.warn("[schema_ferry] #{message}")
    end
  end
end
