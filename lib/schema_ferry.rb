# frozen_string_literal: true

require "active_record"

require_relative "schema_ferry/version"
require_relative "schema_ferry/errors"
require_relative "schema_ferry/support/warnings"
require_relative "schema_ferry/support/schema_model"
require_relative "schema_ferry/support/drop_detectable"
require_relative "schema_ferry/config"
require_relative "schema_ferry/config/table_rule"
require_relative "schema_ferry/io/mysql_reader"
require_relative "schema_ferry/mysql_to_pg/type_mapper"
require_relative "schema_ferry/mysql_to_pg/identifier_shortenable"
require_relative "schema_ferry/mysql_to_pg/column_converter"
require_relative "schema_ferry/mysql_to_pg/enum_check_builder"
require_relative "schema_ferry/mysql_to_pg/schema_converter"
require_relative "schema_ferry/support/schemafile_renderer"
require_relative "schema_ferry/io/postgres_writer"
require_relative "schema_ferry/pipeline"

module SchemaFerry
  def self.define(&)
    Pipeline.new(Config.build(&))
  end
end
