# frozen_string_literal: true

module SchemaFerry
  # Base class so the CLI can rescue every schema_ferry error in one clause.
  class Error               < StandardError; end
  class ConfigError         < Error; end
  class ConnectionError     < Error; end
  class ReadError           < Error; end
  class ConversionError     < Error; end
  class RidgepoleNotFoundError < Error; end
  class RidgepoleError < Error; end
  class DropNotAllowedError < Error; end
end
