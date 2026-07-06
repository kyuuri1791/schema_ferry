# frozen_string_literal: true

require "bigdecimal"

RSpec.describe SchemaFerry::Converter::TypeMapper do
  subject(:mapper) { described_class.new }

  describe "identity mappings" do
    {
      string:   :string,
      integer:  :integer,
      bigint:   :bigint,
      float:    :float,
      decimal:  :decimal,
      datetime: :datetime,
      date:     :date,
      time:     :time,
      boolean:  :boolean
    }.each do |from, to|
      it "maps :#{from} to :#{to}" do
        pg_type, = mapper.call(from)
        expect(pg_type).to eq(to)
      end
    end
  end

  describe "default overrides" do
    it "maps :json to :jsonb" do
      pg_type, = mapper.call(:json)
      expect(pg_type).to eq(:jsonb)
    end
  end

  describe "limit stripping" do
    it "strips limit from :text columns" do
      _, opts = mapper.call(:text, limit: 65_535, null: false)
      expect(opts).not_to have_key(:limit)
      expect(opts[:null]).to be(false)
    end

    it "strips limit from :binary columns" do
      _, opts = mapper.call(:binary, limit: 16_777_215)
      expect(opts).not_to have_key(:limit)
    end

    it "preserves limit for :string columns" do
      _, opts = mapper.call(:string, limit: 255)
      expect(opts[:limit]).to eq(255)
    end

    it "strips limit from :float columns" do
      # MySQL DOUBLE is read by AR as limit: 53 (its internal bit width), but
      # a PG column never reports a limit back — declaring one never converges.
      _, opts = mapper.call(:float, limit: 53)
      expect(opts).not_to have_key(:limit)
    end
  end

  describe "integer width normalization (PG has smallint/integer/bigint only)" do
    it "maps limit 1 (tinyint) to limit 2 (smallint)" do
      pg_type, opts = mapper.call(:integer, limit: 1)
      expect([pg_type, opts[:limit]]).to eq([:integer, 2])
    end

    it "keeps limit 2 (smallint)" do
      pg_type, opts = mapper.call(:integer, limit: 2)
      expect([pg_type, opts[:limit]]).to eq([:integer, 2])
    end

    it "drops limit 4 (PG default integer width)" do
      pg_type, opts = mapper.call(:integer, limit: 4)
      expect([pg_type, opts[:limit]]).to eq([:integer, nil])
    end

    it "maps limit 8 to :bigint without limit" do
      pg_type, opts = mapper.call(:integer, limit: 8)
      expect([pg_type, opts[:limit]]).to eq([:bigint, nil])
    end

    it "strips limit from :bigint columns" do
      _, opts = mapper.call(:bigint, limit: 8)
      expect(opts).not_to have_key(:limit)
    end
  end

  describe "decimal scale normalization" do
    it "drops scale 0 (PG numeric(20) equals numeric(20,0))" do
      _, opts = mapper.call(:decimal, precision: 20, scale: 0)
      expect(opts[:scale]).to be_nil
    end

    it "keeps non-zero scale" do
      _, opts = mapper.call(:decimal, precision: 10, scale: 2)
      expect(opts[:scale]).to eq(2)
    end
  end

  describe "decimal default stringification" do
    it "renders a BigDecimal default as a string, matching AR's schema dumper" do
      # ridgepole compares against the dumped form, which is always a string
      # for decimal columns (e.g. `default: "0.0"`) — a BigDecimal/Integer
      # default never matches it and gets re-applied on every run.
      _, opts = mapper.call(:decimal, precision: 12, scale: 2, default: BigDecimal("0.0"))
      expect(opts[:default]).to eq("0.0")
    end

    it "leaves a nil default alone" do
      _, opts = mapper.call(:decimal, precision: 12, scale: 2, default: nil)
      expect(opts[:default]).to be_nil
    end
  end

  describe "timestamp precision normalization" do
    it "drops precision 6 from :datetime (PG default)" do
      _, opts = mapper.call(:datetime, precision: 6)
      expect(opts[:precision]).to be_nil
    end

    it "keeps non-default datetime precision" do
      _, opts = mapper.call(:datetime, precision: 3)
      expect(opts[:precision]).to eq(3)
    end

    it "always drops precision from :timestamptz overrides" do
      # ActiveRecord's PostgreSQL adapter never honors a precision option on
      # :timestamptz (unlike :datetime/:timestamp/:time); declaring one
      # produces a schema ridgepole can never converge on.
      tz_mapper = described_class.new(datetime: :timestamptz)
      _, opts_at_default = tz_mapper.call(:datetime, precision: 6)
      _, opts_at_zero    = tz_mapper.call(:datetime, precision: 0)
      _, opts_nonzero    = tz_mapper.call(:datetime, precision: 3)
      expect([opts_at_default[:precision], opts_at_zero[:precision], opts_nonzero[:precision]])
        .to eq([nil, nil, nil])
    end
  end

  describe "custom global overrides" do
    it "respects user-supplied overrides" do
      custom_mapper = described_class.new(string: :text)
      pg_type, = custom_mapper.call(:string)
      expect(pg_type).to eq(:text)
    end

    it "user override wins over built-in default" do
      custom_mapper = described_class.new(json: :json)
      pg_type, = custom_mapper.call(:json)
      expect(pg_type).to eq(:json)
    end
  end

  describe "unknown type" do
    it "raises ConversionError for unrecognised types" do
      expect { mapper.call(:unknown_mysql_type) }
        .to raise_error(SchemaFerry::ConversionError, /unknown_mysql_type/)
    end
  end
end
