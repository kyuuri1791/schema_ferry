# frozen_string_literal: true

RSpec.describe SchemaFerry do
  it "has a version number" do
    expect(SchemaFerry::VERSION).not_to be_nil
  end

  describe ".define" do
    it "returns a Pipeline" do
      pipeline = described_class.define do
        source "mysql2://localhost/src"
        target "postgresql://localhost/dst"
      end
      expect(pipeline).to be_a(SchemaFerry::Pipeline)
    end

    it "passes custom rules through to the pipeline config" do
      pipeline = described_class.define do
        source "mysql2://localhost/src"
        target "postgresql://localhost/dst"
        map_type :json, to: :jsonb
        ignore_table :old_logs
        table(:users) { ignore_column :legacy_col }
      end
      expect(pipeline).to be_a(SchemaFerry::Pipeline)
    end

    it "raises ConfigError when source is not configured" do
      expect do
        described_class.define do
          target "postgresql://localhost/dst"
        end
      end.to raise_error(SchemaFerry::ConfigError, /source is not configured/)
    end

    it "raises ConfigError when target is not configured" do
      expect do
        described_class.define do
          source "mysql2://localhost/src"
        end
      end.to raise_error(SchemaFerry::ConfigError, /target is not configured/)
    end
  end
end
