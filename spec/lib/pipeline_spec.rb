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

  let(:reader)    { instance_double(SchemaFerry::IO::MysqlReader, read_all: []) }
  let(:converter) { instance_double(SchemaFerry::Converter::SchemaConverter, convert: [build_table(name: "users")]) }
  let(:writer)    { instance_double(SchemaFerry::IO::PostgresWriter) }

  before do
    allow(SchemaFerry::IO::MysqlReader).to receive(:new).and_return(reader)
    allow(SchemaFerry::Converter::SchemaConverter).to receive(:new).and_return(converter)
    allow(SchemaFerry::IO::PostgresWriter).to receive(:new).and_return(writer)
  end

  describe "#dry_run" do
    it "renders the converted tables and runs the writer in dry-run mode" do
      allow(writer).to receive(:run).with(/create_table "users"/, dry_run: true).and_return("diff")

      expect(pipeline.dry_run).to eq("diff")
    end
  end

  describe "#apply!" do
    context "when allow_drops is true (default)" do
      it "applies directly without a dry-run pre-check" do
        allow(writer).to receive(:run).with(anything, dry_run: false).and_return("applied")

        expect(pipeline.apply!).to eq("applied")
        expect(writer).not_to have_received(:run).with(anything, dry_run: true)
      end
    end

    context "when allow_drops is false and the dry-run reports no drops" do
      it "runs the real apply after the pre-check" do
        allow(writer).to receive(:run).with(anything, dry_run: true)
                                      .and_return('add_column("users", "x", :string, {})')
        allow(writer).to receive(:run).with(anything, dry_run: false).and_return("applied")

        expect(pipeline.apply!(allow_drops: false)).to eq("applied")
      end
    end

    context "when allow_drops is false and the dry-run reports a drop" do
      it "raises DropNotAllowedError without running the real apply" do
        allow(writer).to receive(:run).with(anything, dry_run: true)
                                      .and_return('remove_column("users", "legacy_field")')

        expect { pipeline.apply!(allow_drops: false) }
          .to raise_error(SchemaFerry::DropNotAllowedError, /remove_column\("users", "legacy_field"\)/)
        expect(writer).not_to have_received(:run).with(anything, dry_run: false)
      end
    end
  end
end
