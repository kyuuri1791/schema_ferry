# frozen_string_literal: true

module SchemaFerry
  class Pipeline
    def initialize(config)
      @config = config
    end

    def dry_run
      RidgepoleRunner.new(@config.target_url).run(schemafile, dry_run: true)
    end

    def apply!
      RidgepoleRunner.new(@config.target_url).run(schemafile, dry_run: false)
    end

    # Returns the generated Schemafile content without touching the target DB.
    def schemafile
      raw    = MysqlReader.new(@config.source_url).read_all
      tables = SchemaConverter.new(@config).convert(raw)
      RidgepoleWriter.new.write(tables)
    end
  end
end
