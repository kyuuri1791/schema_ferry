# frozen_string_literal: true

module SchemaFerry
  module Core
    def self.translate(config, mysql_tables)
      pg_tables = SchemaConverter.new(config).convert(mysql_tables)
      SchemafileRenderer.new.render(pg_tables)
    end
  end
end
