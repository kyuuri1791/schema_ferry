# frozen_string_literal: true

module SchemaFerry
  class Pipeline
    def initialize(config)
      @config = config
      @runner = Target::RidgepoleRunner.new(config.target_url)
    end

    def dry_run
      @runner.run(schemafile, dry_run: true)
    end

    def apply!(allow_drops: true)
      content = schemafile

      Target::DropGuard.check!(@runner.run(content, dry_run: true)) unless allow_drops

      @runner.run(content, dry_run: false)
    end

    def schemafile
      mysql_tables = Source::MysqlReader.new(@config.source_url).read_all
      pg_tables    = Converter::SchemaConverter.new(@config).convert(mysql_tables)
      Target::SchemafileRenderer.new.render(pg_tables)
    end
  end
end
