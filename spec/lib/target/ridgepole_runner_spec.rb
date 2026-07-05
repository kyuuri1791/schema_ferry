# frozen_string_literal: true

RSpec.describe SchemaFerry::Target::RidgepoleRunner do
  subject(:runner) { described_class.new("postgresql://localhost/pgdb") }

  describe "#run" do
    context "when ridgepole binary is not found" do
      before do
        allow(Gem).to receive(:bin_path).and_raise(Gem::GemNotFoundException, "not found")
      end

      it "raises RidgepoleNotFoundError" do
        expect { runner.run("", dry_run: true) }
          .to raise_error(SchemaFerry::RidgepoleNotFoundError, /ridgepole/)
      end
    end

    context "when ridgepole exits with non-zero status" do
      let(:fake_status) { instance_double(Process::Status, success?: false) }

      before do
        allow(Gem).to receive(:bin_path).and_return("/usr/bin/ridgepole")
        allow(Open3).to receive(:capture3).and_return(["", "error output", fake_status])
      end

      it "raises RidgepoleError" do
        expect { runner.run("schema content") }
          .to raise_error(SchemaFerry::RidgepoleError, "error output")
      end

      it "includes both stdout and stderr in the error message when stdout has content" do
        allow(Open3).to receive(:capture3).and_return(["partial apply log", "error output", fake_status])
        expect { runner.run("schema content") }
          .to raise_error(SchemaFerry::RidgepoleError, "partial apply log\nerror output")
      end
    end

    context "when ridgepole succeeds" do
      let(:fake_status) { instance_double(Process::Status, success?: true) }

      before do
        allow(Gem).to receive(:bin_path).and_return("/usr/bin/ridgepole")
        allow(Open3).to receive(:capture3).and_return(["-- Apply\n", "", fake_status])
      end

      it "returns stdout" do
        result = runner.run("schema content")
        expect(result).to eq("-- Apply\n")
      end

      it "passes --dry-run flag when dry_run: true" do
        runner.run("schema content", dry_run: true)
        expect(Open3).to have_received(:capture3) do |*cmd|
          expect(cmd).to include("--dry-run")
        end
      end

      it "does NOT pass --dry-run flag when dry_run: false" do
        runner.run("schema content", dry_run: false)
        expect(Open3).to have_received(:capture3) do |*cmd|
          expect(cmd).not_to include("--dry-run")
        end
      end

      it "always passes --apply" do
        runner.run("schema content")
        expect(Open3).to have_received(:capture3) do |*cmd|
          expect(cmd).to include("--apply")
        end
      end

      it "passes the target URL" do
        runner.run("schema content")
        expect(Open3).to have_received(:capture3) do |*cmd|
          idx = cmd.index("-c")
          expect(cmd[idx + 1]).to eq("postgresql://localhost/pgdb")
        end
      end
    end
  end
end
