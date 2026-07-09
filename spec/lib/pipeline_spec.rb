# frozen_string_literal: true

RSpec.describe SchemaFerry::Pipeline do
  let(:pipeline) do
    described_class.new(
      SchemaFerry::DSL::Config.build do
        source "mysql2://localhost/mydb"
        target "postgresql://localhost/pgdb"
      end
    )
  end

  let(:runner) { instance_double(SchemaFerry::Target::RidgepoleRunner) }

  before do
    allow(SchemaFerry::Target::RidgepoleRunner).to receive(:new).and_return(runner)
    allow(pipeline).to receive(:schemafile).and_return("create_table \"users\" do |t|\nend")
  end

  describe "#apply!" do
    context "when allow_drops is true (default)" do
      it "applies directly without a dry-run pre-check" do
        allow(runner).to receive(:run).with(anything, dry_run: false).and_return("applied")

        expect(pipeline.apply!).to eq("applied")
        expect(runner).not_to have_received(:run).with(anything, dry_run: true)
      end
    end

    context "when allow_drops is false and the dry-run reports no destructive changes" do
      it "runs the real apply after the pre-check" do
        allow(runner).to receive(:run).with(anything, dry_run: true)
                                      .and_return('add_column("users", "x", :string, {})')
        allow(runner).to receive(:run).with(anything, dry_run: false).and_return("applied")

        expect(pipeline.apply!(allow_drops: false)).to eq("applied")
      end
    end

    context "when allow_drops is false and the dry-run reports a destructive change" do
      it "raises DropNotAllowedError without running the real apply" do
        allow(runner).to receive(:run).with(anything, dry_run: true)
                                      .and_return('remove_column("users", "legacy_field")')

        expect { pipeline.apply!(allow_drops: false) }
          .to raise_error(SchemaFerry::DropNotAllowedError, /remove_column\("users", "legacy_field"\)/)
        expect(runner).not_to have_received(:run).with(anything, dry_run: false)
      end
    end
  end
end
