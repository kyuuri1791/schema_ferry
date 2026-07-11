# frozen_string_literal: true

module SchemaFerry
  class Pipeline
    include Support::DropDetectable

    def initialize(config)
      @config = config
    end

    def dry_run
      write(build_schemafile, dry_run: true)
    end

    def apply!(allow_drops: true)
      schemafile = build_schemafile

      unless allow_drops
        drops = detect_drops(write(schemafile, dry_run: true))
        unless drops.empty?
          raise DropNotAllowedError,
                "refused: the diff contains drop(s):\n#{drops.join("\n")}"
        end
      end

      write(schemafile, dry_run: false)
    end

    private

    def build_schemafile
      IO::MysqlReader.new(@config.source_url).read_all
        .then { |mysql_tables| Core::Translator.new(@config).translate(mysql_tables) }
    end

    def write(schemafile, dry_run:)
      IO::PostgresWriter.new(@config.target_url).run(schemafile, dry_run: dry_run)
    end
  end
end
