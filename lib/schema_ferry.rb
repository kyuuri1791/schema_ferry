# frozen_string_literal: true

require "active_record"

require_relative "schema_ferry/version"
require_relative "schema_ferry/errors"
require_relative "schema_ferry/support/warnings"
require_relative "schema_ferry/support/drop_detectable"
require_relative "schema_ferry/config"
require_relative "schema_ferry/config/table_rule"
require_relative "schema_ferry/io/mysql_reader"
require_relative "schema_ferry/core/schema_model"
require_relative "schema_ferry/core/type_mapper"
require_relative "schema_ferry/core/identifier_shortenable"
require_relative "schema_ferry/core/column_converter"
require_relative "schema_ferry/core/enum_check_builder"
require_relative "schema_ferry/core/schema_converter"
require_relative "schema_ferry/core/schemafile_renderer"
require_relative "schema_ferry/core/translate"
require_relative "schema_ferry/io/postgres_writer"
require_relative "schema_ferry/pipeline"

module SchemaFerry
  def self.define(&)
    Pipeline.new(Config.build(&))
  end
end
