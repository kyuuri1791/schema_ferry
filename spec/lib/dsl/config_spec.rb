# frozen_string_literal: true

require "tempfile"

RSpec.describe SchemaFerry::Config do
  subject(:config) { described_class.new }

  describe ".build" do
    it "evaluates the block and returns a validated config" do
      built = described_class.build do
        source "mysql2://localhost/mydb"
        target "postgresql://localhost/pgdb"
      end
      expect(built.source_url).to eq("mysql2://localhost/mydb")
    end

    it "raises ConfigError when the block leaves the config incomplete" do
      expect { described_class.build { source "mysql2://localhost/mydb" } }
        .to raise_error(SchemaFerry::ConfigError, /target is not configured/)
    end
  end

  describe ".load_file" do
    it "evaluates a definition file and returns a validated config" do
      Tempfile.create(["schema_ferry", ".rb"]) do |f|
        f.write(<<~RUBY)
          source "mysql2://localhost/mydb"
          target "postgresql://localhost/pgdb"
        RUBY
        f.flush
        config = described_class.load_file(f.path)
        expect(config.source_url).to eq("mysql2://localhost/mydb")
      end
    end

    it "raises ConfigError when the file leaves the config incomplete" do
      Tempfile.create(["schema_ferry", ".rb"]) do |f|
        f.write('target "postgresql://localhost/pgdb"')
        f.flush
        expect { described_class.load_file(f.path) }
          .to raise_error(SchemaFerry::ConfigError, /source is not configured/)
      end
    end
  end

  describe "#source" do
    it "captures the MySQL URL" do
      config.source "mysql2://localhost/mydb"
      expect(config.source_url).to eq("mysql2://localhost/mydb")
    end
  end

  describe "#target" do
    it "captures the PostgreSQL URL" do
      config.target "postgresql://localhost/pgdb"
      expect(config.target_url).to eq("postgresql://localhost/pgdb")
    end
  end

  describe "#map_type" do
    it "records a global type override" do
      config.map_type(:json, to: :jsonb)
      expect(config.global_type_overrides).to eq(json: :jsonb)
    end
  end

  describe "#table" do
    it "creates a TableRule and stores it by name" do
      config.table(:users) do
        ignore_column :legacy
      end
      expect(config.table_rules["users"]).to be_a(SchemaFerry::TableRule)
      expect(config.table_rules["users"].ignored_columns).to include("legacy")
    end
  end

  describe "#ignore_table" do
    it "appends to ignored_tables list" do
      config.ignore_table(:old_sessions)
      config.ignore_table(:archive)
      expect(config.ignored_tables).to contain_exactly("old_sessions", "archive")
    end
  end

  describe "#enum_as" do
    it "defaults to :string" do
      expect(config.enum_mode).to eq(:string)
    end

    it "accepts :check" do
      config.enum_as(:check)
      expect(config.enum_mode).to eq(:check)
    end

    it "rejects unknown modes" do
      expect { config.enum_as(:native) }
        .to raise_error(SchemaFerry::ConfigError, /enum_as accepts/)
    end
  end

  describe "#validate!" do
    it "raises ConfigError when source is missing" do
      config.target "postgresql://localhost/pgdb"
      expect { config.validate! }
        .to raise_error(SchemaFerry::ConfigError, /source is not configured/)
    end

    it "raises ConfigError when target is missing" do
      config.source "mysql2://localhost/mydb"
      expect { config.validate! }
        .to raise_error(SchemaFerry::ConfigError, /target is not configured/)
    end

    it "does not raise when both are configured" do
      config.source "mysql2://localhost/mydb"
      config.target "postgresql://localhost/pgdb"
      expect { config.validate! }.not_to raise_error
    end
  end
end
