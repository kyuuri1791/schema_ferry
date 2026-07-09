# frozen_string_literal: true

module SchemaFerry
  module Warnings
    private

    def emit_warning(message)
      Kernel.warn("[schema_ferry] #{message}")
    end
  end
end
