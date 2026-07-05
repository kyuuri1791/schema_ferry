# frozen_string_literal: true

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

  describe "timestamp precision normalization" do
    it "drops precision 6 from :datetime (PG default)" do
      _, opts = mapper.call(:datetime, precision: 6)
      expect(opts[:precision]).to be_nil
    end

    it "keeps non-default datetime precision" do
      _, opts = mapper.call(:datetime, precision: 3)
      expect(opts[:precision]).to eq(3)
    end

    it "drops precision 6 from :timestamptz overrides" do
      tz_mapper = described_class.new(datetime: :timestamptz)
      pg_type, opts = tz_mapper.call(:datetime, precision: 6)
      expect([pg_type, opts[:precision]]).to eq([:timestamptz, nil])
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
