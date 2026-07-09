# frozen_string_literal: true

require "active_record"

require_relative "schema_ferry/version"
require_relative "schema_ferry/errors"
require_relative "schema_ferry/warnings"
require_relative "schema_ferry/schema_model"
require_relative "schema_ferry/dsl/table_rule"
require_relative "schema_ferry/dsl/config"
require_relative "schema_ferry/source/mysql_reader"
require_relative "schema_ferry/converter/type_mapper"
require_relative "schema_ferry/converter/identifier_shortenable"
require_relative "schema_ferry/converter/column_converter"
require_relative "schema_ferry/converter/enum_check_builder"
require_relative "schema_ferry/converter/schema_converter"
require_relative "schema_ferry/target/schemafile_renderer"
require_relative "schema_ferry/target/ridgepole_runner"
require_relative "schema_ferry/target/drop_guard"
require_relative "schema_ferry/pipeline"

module SchemaFerry
  def self.define(&)
    Pipeline.new(DSL::Config.build(&))
  end
end
