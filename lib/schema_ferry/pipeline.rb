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

    # Returns the generated Schemafile content without touching the target DB.
    def schemafile
      raw    = Source::MysqlReader.new(@config.source_url).read_all
      tables = Converter::SchemaConverter.new(@config).convert(raw)
      Target::RidgepoleWriter.new.write(tables)
    end
  end
end
