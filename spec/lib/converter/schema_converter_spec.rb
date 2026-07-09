# frozen_string_literal: true

RSpec.describe SchemaFerry::Converter::SchemaConverter do
  include Fixtures

  def make_config(_overrides = {}, &block)
    config = SchemaFerry::DSL::Config.new
    config.instance_eval(&block) if block
    config
  end

  subject(:converter) { described_class.new(config) }

  let(:config) { make_config }
  let(:raw_tables) do
    [
      build_raw_table(
        name:         "users",
        columns:      [
          build_raw_column(name: "name",   type: :string,  sql_type: "varchar(255)", limit: 255),
          build_raw_column(name: "bio",    type: :text,    sql_type: "text",         limit: 65_535),
          build_raw_column(name: "status", type: :integer, sql_type: "int(11)"),
          build_raw_column(name: "data",   type: :json,    sql_type: "json")
        ],
        indexes:      [
          { name: "index_users_on_name", columns: ["name"], unique: true,
            using: nil, lengths: nil, orders: nil }
        ],
        foreign_keys: []
      ),
      build_raw_table(name: "old_sessions", columns: [], indexes: [], foreign_keys: [])
    ]
  end

  describe "ignore_table" do
    let(:config) do
      make_config { ignore_table :old_sessions }
    end

    it "excludes the ignored table from output" do
      result = converter.convert(raw_tables)
      expect(result.map(&:name)).to contain_exactly("users")
    end
  end

  describe "type mapping" do
    it "converts :json columns to :jsonb by default" do
      result  = converter.convert(raw_tables)
      users   = result.find { |t| t.name == "users" }
      data_col = users.columns.find { |c| c.name == "data" }
      expect(data_col.type).to eq(:jsonb)
    end

    it "strips limits from :text columns" do
      result   = converter.convert(raw_tables)
      users    = result.find { |t| t.name == "users" }
      bio_col  = users.columns.find { |c| c.name == "bio" }
      expect(bio_col.limit).to be_nil
    end

    it "preserves limits on :string columns" do
      result   = converter.convert(raw_tables)
      users    = result.find { |t| t.name == "users" }
      name_col = users.columns.find { |c| c.name == "name" }
      expect(name_col.limit).to eq(255)
    end
  end

  describe "table-level rules" do
    let(:config) do
      make_config do
        table :users do
          ignore_column :bio
          column :status, map_type_to: :boolean
          ignore_index "index_users_on_name"
        end
      end
    end

    it "removes ignored columns" do
      result  = converter.convert(raw_tables)
      users   = result.find { |t| t.name == "users" }
      expect(users.columns.map(&:name)).not_to include("bio")
    end

    it "overrides column type" do
      result  = converter.convert(raw_tables)
      users   = result.find { |t| t.name == "users" }
      status  = users.columns.find { |c| c.name == "status" }
      expect(status.type).to eq(:boolean)
    end

    it "removes ignored indexes" do
      result  = converter.convert(raw_tables)
      users   = result.find { |t| t.name == "users" }
      expect(users.indexes).to be_empty
    end
  end

  describe "index lengths/orders passthrough" do
    it "passes through scalar lengths/orders (single-column index)" do
      raw = [build_raw_table(
        name:    "users",
        columns: [build_raw_column(name: "name")],
        indexes: [build_raw_index(name: "idx_name_prefix", columns: ["name"], lengths: 10, orders: :desc)]
      )]
      idx = converter.convert(raw).first.indexes.first
      expect(idx.lengths).to eq(10)
      expect(idx.orders).to eq(:desc)
    end
  end

  describe "ignore propagation" do
    let(:config) do
      make_config do
        ignore_table :old_sessions
        table :users do
          ignore_column :legacy
        end
      end
    end

    let(:raw_tables) do
      [
        build_raw_table(
          name:         "users",
          columns:      [build_raw_column(name: "legacy"), build_raw_column(name: "name")],
          indexes:      [
            build_raw_index(name: "index_users_on_legacy_and_name", columns: %w[legacy name]),
            build_raw_index(name: "index_users_on_name", columns: ["name"])
          ],
          foreign_keys: [
            build_raw_fk(from_table: "users", to_table: "accounts", column: "legacy"),
            build_raw_fk(from_table: "users", to_table: "old_sessions", column: "session_id")
          ]
        )
      ]
    end

    it "drops indexes that reference an ignored column" do
      users = converter.convert(raw_tables).first
      expect(users.indexes.map(&:name)).to eq(["index_users_on_name"])
    end

    it "drops foreign keys on an ignored column" do
      users = converter.convert(raw_tables).first
      expect(users.foreign_keys.map(&:column)).not_to include("legacy")
    end

    it "drops foreign keys pointing at an ignored table" do
      users = converter.convert(raw_tables).first
      expect(users.foreign_keys.map(&:to_table)).not_to include("old_sessions")
    end
  end

  describe "unsigned integers" do
    let(:raw_tables) do
      [build_raw_table(
        name:    "counters",
        columns: [
          build_raw_column(name: "small", type: :integer, sql_type: "smallint unsigned", limit: 2),
          build_raw_column(name: "medium", type: :integer, sql_type: "int unsigned", limit: 4),
          build_raw_column(name: "large", type: :integer, sql_type: "bigint unsigned", limit: 8),
          build_raw_column(name: "plain", type: :integer, sql_type: "int", limit: 4)
        ]
      )]
    end

    def column(name)
      converter.convert(raw_tables).first.columns.find { |c| c.name == name }
    end

    it "bumps unsigned integers one size up" do
      expect([column("small").type, column("small").limit]).to eq([:integer, nil])
      expect(column("medium").type).to eq(:bigint)
    end

    it "maps BIGINT UNSIGNED to decimal(20) with a warning" do
      col = nil
      expect { col = column("large") }.to output(/BIGINT UNSIGNED/).to_stderr
      expect([col.type, col.precision, col.scale]).to eq([:decimal, 20, nil])
    end

    it "does not widen signed integers" do
      expect([column("plain").type, column("plain").limit]).to eq([:integer, nil])
    end

    context "when a BIGINT UNSIGNED column has a default" do
      let(:raw_tables) do
        [build_raw_table(
          name:    "counters",
          columns: [build_raw_column(name: "points", type: :integer, sql_type: "bigint unsigned",
                                     limit: 8, default: 0)]
        )]
      end

      it "renders the default as a string, matching how AR's schema dumper renders decimal defaults" do
        col = nil
        expect { col = column("points") }.to output(/BIGINT UNSIGNED/).to_stderr
        expect(col.default).to eq("0")
      end
    end
  end

  describe "BIGINT UNSIGNED columns on a foreign key" do
    let(:raw_tables) do
      [
        build_raw_table(
          name:         "posts",
          pk_sql_type:  "bigint unsigned",
          columns:      [
            build_raw_column(name: "user_id", type: :integer, sql_type: "bigint unsigned", limit: 8)
          ],
          foreign_keys: [build_raw_fk(from_table: "posts", to_table: "users", column: "user_id")]
        ),
        build_raw_table(name: "users", pk_sql_type: "bigint unsigned")
      ]
    end

    it "maps the referencing column to signed bigint so it matches the referenced primary key" do
      col = nil
      expect { col = converter.convert(raw_tables).first.columns.first }
        .to output(/takes part in a foreign key/).to_stderr
      expect([col.type, col.limit, col.precision]).to eq([:bigint, nil, nil])
    end

    context "when the foreign key references a non-primary-key column" do
      let(:raw_tables) do
        [
          build_raw_table(
            name:         "posts",
            columns:      [
              build_raw_column(name: "user_ref", type: :integer, sql_type: "bigint unsigned", limit: 8)
            ],
            foreign_keys: [build_raw_fk(from_table: "posts", to_table: "users",
                                        column: "user_ref", primary_key: "ref")]
          ),
          build_raw_table(
            name:    "users",
            columns: [build_raw_column(name: "ref", type: :integer, sql_type: "bigint unsigned", limit: 8)]
          )
        ]
      end

      it "maps the referenced column to signed bigint as well" do
        ref = nil
        expect { ref = converter.convert(raw_tables).last.columns.first }
          .to output(/takes part in a foreign key/).to_stderr
        expect(ref.type).to eq(:bigint)
      end
    end

    it "keeps decimal(20, 0) when the foreign key is dropped by ignore_table" do
      config.ignore_table :users
      col = nil
      expect { col = converter.convert(raw_tables).first.columns.first }
        .to output(/decimal\(20, 0\)/).to_stderr
      expect([col.type, col.precision]).to eq([:decimal, 20])
    end
  end

  describe "primary key type" do
    def pk_type_for(pk_sql_type)
      raw = [build_raw_table(name: "t", pk_type: :integer, pk_sql_type: pk_sql_type)]
      converter.convert(raw).first.pk_type
    end

    it "maps BIGINT primary keys to :bigint (AR reports them as :integer)" do
      expect(pk_type_for("bigint")).to eq(:bigint)
    end

    it "keeps INT primary keys as :integer" do
      expect(pk_type_for("int")).to eq(:integer)
    end

    it "bumps INT UNSIGNED primary keys to :bigint" do
      expect(pk_type_for("int unsigned")).to eq(:bigint)
    end

    it "maps BIGINT UNSIGNED primary keys to :bigint with a warning" do
      expect { expect(pk_type_for("bigint unsigned")).to eq(:bigint) }
        .to output(/BIGINT UNSIGNED primary key/).to_stderr
    end
  end

  describe "FULLTEXT / SPATIAL indexes" do
    let(:raw_tables) do
      [build_raw_table(
        name:    "posts",
        columns: [build_raw_column(name: "body", type: :text, sql_type: "text")],
        indexes: [build_raw_index(name: "ft_body", columns: ["body"], type: :fulltext)]
      )]
    end

    it "raises ConversionError" do
      expect { converter.convert(raw_tables) }
        .to raise_error(SchemaFerry::ConversionError, /FULLTEXT index "ft_body" has no PostgreSQL equivalent/)
    end

    context "when the index is explicitly ignored" do
      let(:config) do
        make_config { table(:posts) { ignore_index :ft_body } }
      end

      it "excludes it without raising" do
        posts = converter.convert(raw_tables).first
        expect(posts.indexes).to be_empty
      end
    end

    context "when its column is ignored" do
      let(:config) do
        make_config { table(:posts) { ignore_column :body } }
      end

      it "excludes it without raising" do
        posts = converter.convert(raw_tables).first
        expect(posts.indexes).to be_empty
      end
    end
  end

  describe "spatial columns" do
    let(:raw_tables) do
      [build_raw_table(
        name:    "places",
        columns: [
          build_raw_column(name: "name", type: :string, sql_type: "varchar(255)"),
          # ActiveRecord's mysql2 adapter misreports POINT as plain :integer;
          # only sql_type reveals what it actually is.
          build_raw_column(name: "location", type: :integer, sql_type: "point")
        ]
      )]
    end

    it "raises ConversionError for POINT columns, despite AR reporting them as :integer" do
      expect { converter.convert(raw_tables) }
        .to raise_error(SchemaFerry::ConversionError, /point columns have no PostgreSQL equivalent/)
    end

    context "when the column is explicitly ignored" do
      let(:config) { make_config { table(:places) { ignore_column :location } } }

      it "excludes it without raising" do
        places = converter.convert(raw_tables).first
        expect(places.columns.map(&:name)).to eq(["name"])
      end
    end

    context "when the column has a column override" do
      let(:config) { make_config { table(:places) { column :location, map_type_to: :binary } } }

      it "uses the override instead of raising" do
        places = converter.convert(raw_tables).first
        location = places.columns.find { |c| c.name == "location" }
        expect(location.type).to eq(:binary)
      end
    end

    # Other spatial types aren't specially handled: ActiveRecord's mysql2
    # adapter reports them as an unrecognized type (nil), which is already
    # caught by TypeMapper's general "unknown MySQL type" safety net. Only
    # POINT needs its own check, because it slips past that net.
    %w[geometry linestring polygon multipoint multilinestring multipolygon geometrycollection].each do |sql_type|
      it "raises ConversionError for #{sql_type.upcase} columns, same as any other unrecognized type" do
        raw = [build_raw_table(
          name:    "places",
          columns: [build_raw_column(name: "geo", type: nil, sql_type: sql_type)]
        )]
        expect { converter.convert(raw) }.to raise_error(SchemaFerry::ConversionError, /unknown mysql ar type/i)
      end
    end
  end

  describe "identifier length" do
    let(:long_name) { "index_users_on_#{"a" * 60}" }
    let(:raw_tables) do
      [build_raw_table(
        name:    "users",
        columns: [build_raw_column(name: "name")],
        indexes: [build_raw_index(name: long_name, columns: ["name"])]
      )]
    end

    it "shortens index names over 63 bytes deterministically, with a warning" do
      shortened = nil
      expect do
        shortened = converter.convert(raw_tables).first.indexes.first.name
      end.to output(/exceeds PostgreSQL's 63-byte identifier limit/).to_stderr

      digest = Digest::MD5.hexdigest(long_name)[0, 8]
      expect(shortened).to eq("#{long_name.byteslice(0, 54)}_#{digest}")
    end

    it "leaves names at 63 bytes or below untouched" do
      raw = [build_raw_table(
        name:    "users",
        columns: [build_raw_column(name: "name")],
        indexes: [build_raw_index(name: "i#{"x" * 62}", columns: ["name"])]
      )]
      expect(converter.convert(raw).first.indexes.first.name.bytesize).to eq(63)
    end
  end

  describe "zero-date defaults" do
    let(:raw_tables) do
      [build_raw_table(
        name:    "events",
        columns: [build_raw_column(name: "happened_at", type: :datetime, sql_type: "datetime",
                                   default: "0000-00-00 00:00:00")]
      )]
    end

    it "drops them with a warning" do
      expect do
        col = converter.convert(raw_tables).first.columns.first
        expect(col.default).to be_nil
      end.to output(/invalid on PostgreSQL/).to_stderr
    end
  end

  describe "type override and boolean defaults" do
    let(:raw_tables) do
      [build_raw_table(
        name:    "users",
        columns: [build_raw_column(name: "tri", type: :boolean, sql_type: "tinyint(1)", default: true)]
      )]
    end

    context "when the type is overridden away from :boolean" do
      let(:config) do
        make_config { table(:users) { column :tri, map_type_to: :integer } }
      end

      it "drops the AR-coerced boolean default with a warning" do
        expect do
          col = converter.convert(raw_tables).first.columns.first
          expect(col.type).to eq(:integer)
          expect(col.default).to be_nil
        end.to output(/dropping default true/).to_stderr
      end
    end

    context "when column supplies an explicit default" do
      let(:config) do
        make_config { table(:users) { column :tri, map_type_to: :integer, default: 2 } }
      end

      it "uses the explicit default without warning" do
        col = nil
        expect { col = converter.convert(raw_tables).first.columns.first }.not_to output.to_stderr
        expect(col.default).to eq(2)
      end
    end

    context "when the override keeps :boolean" do
      let(:config) do
        make_config { table(:users) { column :tri, map_type_to: :boolean } }
      end

      it "keeps the boolean default" do
        expect(converter.convert(raw_tables).first.columns.first.default).to be(true)
      end
    end
  end

  describe "enum conversion" do
    let(:raw_tables) do
      [build_raw_table(
        name:    "users",
        columns: [
          build_raw_column(name: "kind", type: :string, sql_type: "enum('a','b')"),
          build_raw_column(name: "name", type: :string)
        ]
      )]
    end

    it "emits no check constraints by default" do
      expect(converter.convert(raw_tables).first.check_constraints).to be_empty
    end

    context "with enum_as :check" do
      let(:config) { make_config { enum_as :check } }

      it "builds a CHECK constraint from the enum values (PG-normalized form)" do
        chk = converter.convert(raw_tables).first.check_constraints.first
        expect(chk.expression)
          .to eq("kind::text = ANY (ARRAY['a'::character varying::text, 'b'::character varying::text])")
        expect(chk.name).to eq("chk_users_kind")
      end

      it "skips ignored columns" do
        config.table(:users) { ignore_column :kind }
        expect(converter.convert(raw_tables).first.check_constraints).to be_empty
      end

      it "skips columns whose type is overridden" do
        config.table(:users) { column :kind, map_type_to: :integer }
        expect(converter.convert(raw_tables).first.check_constraints).to be_empty
      end
    end
  end

  describe "timestamptz via map_type" do
    let(:config) { make_config { map_type :datetime, to: :timestamptz } }
    let(:raw_tables) do
      [build_raw_table(
        name:    "events",
        columns: [build_raw_column(name: "happened_at", type: :datetime, sql_type: "datetime")]
      )]
    end

    it "converts datetime columns to timestamptz" do
      expect(converter.convert(raw_tables).first.columns.first.type).to eq(:timestamptz)
    end
  end
end
