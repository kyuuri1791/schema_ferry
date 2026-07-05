# frozen_string_literal: true

require "schema_ferry/cli"
require "open3"
require "tempfile"

RSpec.describe SchemaFerry::CLI do
  before do
    skip "Set INTEGRATION=true to run integration tests" unless ENV["INTEGRATION"]
  end

  it "runs dry-run end to end via the executable" do
    Tempfile.create(["schema_ferry_config", ".rb"]) do |f|
      f.write(<<~RUBY)
        source "mysql2://root:password@127.0.0.1:3307/schema_ferry_source"
        target "postgresql://postgres:password@127.0.0.1:5433/schema_ferry_target"
      RUBY
      f.flush

      out, _err, status = Open3.capture3("ruby", "-Ilib", "exe/schema_ferry", "dry-run", "-c", f.path)
      expect(status).to be_success
      expect(out).to include("(dry-run)")
      expect(out).to match(/\d+ tables? checked/)
    end
  end

  it "exits non-zero for a broken definition file" do
    Tempfile.create(["schema_ferry_config", ".rb"]) do |f|
      f.write('source "mysql2://localhost/only_source"')
      f.flush

      _out, err, status = Open3.capture3("ruby", "-Ilib", "exe/schema_ferry", "apply", "-c", f.path)
      expect(status.exitstatus).to eq(1)
      expect(err).to include("target is not configured")
    end
  end
end
