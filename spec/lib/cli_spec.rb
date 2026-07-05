# frozen_string_literal: true

require "schema_ferry/cli"
require "stringio"
require "tmpdir"

RSpec.describe SchemaFerry::CLI do
  subject(:cli) { described_class.new(stdout: stdout, stderr: stderr) }

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def write_config(dir)
    File.join(dir, "Ferryfile").tap do |path|
      File.write(path, <<~RUBY)
        source "mysql2://localhost/src"
        target "postgresql://localhost/dst"
      RUBY
    end
  end

  describe "--version" do
    it "prints the version and succeeds" do
      expect(cli.run(["--version"])).to eq(0)
      expect(stdout.string).to include(SchemaFerry::VERSION)
    end
  end

  describe "--help" do
    it "prints usage and succeeds" do
      expect(cli.run(["--help"])).to eq(0)
      expect(stdout.string).to include("Usage: schema_ferry")
    end
  end

  describe "command validation" do
    it "fails without a command" do
      expect(cli.run([])).to eq(1)
      expect(stderr.string).to include("missing command")
    end

    it "fails on an unknown command" do
      expect(cli.run(["sync"])).to eq(1)
      expect(stderr.string).to include("unknown command: sync")
    end

    it "fails on an unknown option" do
      expect(cli.run(["apply", "--nope"])).to eq(1)
      expect(stderr.string).to include("invalid option")
    end
  end

  describe "definition file loading" do
    it "fails when the file does not exist" do
      expect(cli.run(["apply", "-c", "/no/such/file.rb"])).to eq(1)
      expect(stderr.string).to include("definition file not found")
    end

    it "fails when the definition is incomplete" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "Ferryfile")
        File.write(path, 'source "mysql2://localhost/src"')
        expect(cli.run(["apply", "-c", path])).to eq(1)
        expect(stderr.string).to include("target is not configured")
      end
    end
  end

  describe "commands" do
    let(:schemafile) do
      <<~RUBY
        create_table "users", force: :cascade do |t|
        end

        create_table "posts", force: :cascade do |t|
        end
      RUBY
    end
    let(:pipeline) { instance_double(SchemaFerry::Pipeline, schemafile: schemafile) }
    let(:runner)   { instance_double(SchemaFerry::RidgepoleRunner) }

    before do
      allow(SchemaFerry::Pipeline).to receive(:new).and_return(pipeline)
      allow(SchemaFerry::RidgepoleRunner).to receive(:new).and_return(runner)
    end

    it "dry-run prints the diff and a summary" do
      allow(runner).to receive(:run).with(schemafile, dry_run: true)
                                    .and_return(%(Apply `x` (dry-run)\ncreate_table("users") do |t|\nend))
      Dir.mktmpdir do |dir|
        expect(cli.run(["dry-run", "-c", write_config(dir)])).to eq(0)
        expect(stdout.string).to include("(dry-run)")
        expect(stdout.string).to include("2 tables checked, 1 change pending")
      end
    end

    it "apply prints the result and a summary" do
      allow(runner).to receive(:run).with(schemafile, dry_run: false)
                                    .and_return("Apply `x`\n-- create_table(\"users\")\n   -> 0.1s\n" \
                                                "-- add_index(\"users\")\n   -> 0.1s")
      Dir.mktmpdir do |dir|
        expect(cli.run(["apply", "-c", write_config(dir)])).to eq(0)
        expect(stdout.string).to include("2 tables synced, 2 changes applied")
      end
    end

    it "reports no changes when the target is already in sync" do
      allow(runner).to receive(:run).and_return("Apply `x`\nNo change")
      Dir.mktmpdir do |dir|
        expect(cli.run(["apply", "-c", write_config(dir)])).to eq(0)
        expect(stdout.string).to include("2 tables synced, no changes")
      end
    end

    it "translates SchemaFerry errors into exit code 1" do
      allow(runner).to receive(:run).and_raise(SchemaFerry::RidgepoleError, "boom")
      Dir.mktmpdir do |dir|
        expect(cli.run(["apply", "-c", write_config(dir)])).to eq(1)
        expect(stderr.string).to include("boom")
      end
    end
  end
end
