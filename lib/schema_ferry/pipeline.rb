# frozen_string_literal: true

module SchemaFerry
  class Pipeline
    def initialize(config)
      @config = config
      @runner = Target::RidgepoleRunner.new(config.target_url)
    end

    def dry_run
      @runner.run(compile_schemafile, dry_run: true)
    end

    def apply!(allow_drops: true)
      Target::DropGuard.check!(@runner.run(compile_schemafile, dry_run: true)) unless allow_drops

      @runner.run(compile_schemafile, dry_run: false)
    end

    def schemafile
      compile_schemafile
    end

    private

    def compile_schemafile
      @compile_schemafile ||= begin
        mysql_tables = Source::MysqlReader.new(@config.source_url).read_all
        pg_tables    = Converter::SchemaConverter.new(@config).convert(mysql_tables)
        Target::SchemafileRenderer.new.render(pg_tables)
      end
    end
  end
end
