# frozen_string_literal: true

module SchemaFerry
  class Pipeline
    include Support::DropDetectable

    def initialize(config)
      @config = config
    end

    def dry_run
      sync_schema(dry_run: true)
    end

    def apply!(allow_drops: true)
      unless allow_drops
        drops = detect_drops(sync_schema(dry_run: true))
        unless drops.empty?
          raise DropNotAllowedError,
                "refused: the diff contains drop(s):\n#{drops.join("\n")}"
        end
      end

      sync_schema(dry_run: false)
    end

    private

    def sync_schema(dry_run:)
      IO::MysqlReader.new(@config.source_url).read_all
        .then { |mysql_tables| MysqlToPg::SchemaConverter.new(@config).convert(mysql_tables) }
        .then { |pg_tables| Support::SchemafileRenderer.new.render(pg_tables) }
        .then { |schemafile| IO::PostgresWriter.new(@config.target_url).run(schemafile, dry_run: dry_run) }
    end
  end
end
