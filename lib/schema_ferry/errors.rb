# frozen_string_literal: true

module SchemaFerry
  class Error               < StandardError; end
  class ConfigError         < Error; end
  class ConnectionError     < Error; end
  class ReadError           < Error; end
  class ConversionError     < Error; end
  class RidgepoleNotFoundError < Error; end
  class RidgepoleError < Error; end
end
