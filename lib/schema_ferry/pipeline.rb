# frozen_string_literal: true

module SchemaFerry
  class Pipeline
    def initialize(config)
      @config = config
    end

    def dry_run
      Target::RidgepoleRunner.new(@config.target_url).run(schemafile, dry_run: true)
    end

    def apply!
      Target::RidgepoleRunner.new(@config.target_url).run(schemafile, dry_run: false)
    end

    def schemafile
      mysql_tables = Source::MysqlReader.new(@config.source_url).read_all
      pg_tables    = Converter::SchemaConverter.new(@config).convert(mysql_tables)
      Target::SchemafileRenderer.new.render(pg_tables)
    end
  end
end
