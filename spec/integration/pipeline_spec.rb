# frozen_string_literal: true

MYSQL_URL    = "mysql2://root:password@127.0.0.1:3307/schema_ferry_source"
POSTGRES_URL = "postgresql://postgres:password@127.0.0.1:5433/schema_ferry_target"

RSpec.describe SchemaFerry::Pipeline do
  before(:all) do
    skip "Set INTEGRATION=true to run integration tests" unless ENV["INTEGRATION"]
    setup_source_schema
  end

  after(:all) do
    next unless ENV["INTEGRATION"]

    teardown_source_schema
    teardown_target_schema
  end

  let(:pipeline) do
    SchemaFerry.define do
      source MYSQL_URL
      target POSTGRES_URL
      table(:posts) do
        ignore_column :location
        ignore_index :index_posts_on_body
      end
    end
  end

  describe "#dry_run" do
    it "returns a DDL string without applying changes" do
      ddl = pipeline.dry_run
      expect(ddl).to include("create_table")
      expect(ddl).to include("users")
      expect(ddl).to include("posts")
    end
  end

  describe "POINT columns" do
    it "raises ConversionError unless the column is explicitly ignored" do
      pipeline_without_ignore = SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
      end
      expect { pipeline_without_ignore.schemafile }
        .to raise_error(SchemaFerry::ConversionError, /point columns have no PostgreSQL equivalent/)
    end
  end

  describe "FULLTEXT indexes" do
    it "raises ConversionError unless the index is explicitly ignored" do
      pipeline_without_ignore = SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        table(:posts) { ignore_column :location }
      end
      expect { pipeline_without_ignore.schemafile }
        .to raise_error(SchemaFerry::ConversionError, /FULLTEXT index .* has no PostgreSQL equivalent/)
    end
  end

  describe "#apply!" do
    before(:all) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
      end.apply!
    end

    it "creates tables in PostgreSQL" do
      with_pg do |conn|
        expect(conn.tables).to include("users", "posts")
      end
    end

    it "maps json columns to jsonb" do
      with_pg do |conn|
        col = conn.columns("users").find { |c| c.name == "metadata" }
        expect(col.sql_type).to eq("jsonb")
      end
    end

    it "collapses created_at and updated_at into t.timestamps" do
      expect(pipeline.schemafile).to include("t.timestamps")
    end

    it "creates indexes" do
      with_pg do |conn|
        index_names = conn.indexes("users").map(&:name)
        expect(index_names).to include("index_users_on_email")
      end
    end

    it "preserves null constraints" do
      with_pg do |conn|
        name_col = conn.columns("users").find { |c| c.name == "name" }
        expect(name_col.null).to be false
      end
    end

    it "preserves string primary keys" do
      with_pg do |conn|
        id_col = conn.columns("api_keys").find { |c| c.name == "id" }
        expect(id_col.sql_type).to eq("character varying(255)")
      end
    end

    it "creates composite primary key tables with their columns" do
      with_pg do |conn|
        expect(conn.primary_key("memberships")).to eq(%w[user_id group_id])
        expect(conn.columns("memberships").map(&:name)).to include("user_id", "group_id")
      end
    end

    it "preserves default functions" do
      with_pg do |conn|
        col = conn.columns("events").find { |c| c.name == "logged_at" }
        expect(col.default_function).to match(/current_timestamp/i)
      end
    end

    it "keeps bigint primary keys as bigint" do
      with_pg do |conn|
        id_col = conn.columns("users").find { |c| c.name == "id" }
        expect(id_col.sql_type).to eq("bigint")
      end
    end

    it "bumps INT UNSIGNED to bigint" do
      with_pg do |conn|
        counter = conn.columns("users").find { |c| c.name == "counter" }
        expect(counter.sql_type).to eq("bigint")
      end
    end

    it "maps BIGINT UNSIGNED to numeric(20,0)" do
      with_pg do |conn|
        visits = conn.columns("users").find { |c| c.name == "visits" }
        expect(visits.sql_type).to eq("numeric(20,0)")
      end
    end

    it "carries over a BIGINT UNSIGNED default onto the decimal(20,0) column" do
      with_pg do |conn|
        points = conn.columns("users").find { |c| c.name == "points" }
        expect(points.default).to eq(0)
      end
    end

    it "carries over a plain DECIMAL column's default" do
      with_pg do |conn|
        balance = conn.columns("users").find { |c| c.name == "balance" }
        expect(balance.sql_type).to eq("numeric(12,2)")
        expect(balance.default).to eq(BigDecimal("0.0"))
      end
    end

    it "strips the limit from DOUBLE columns" do
      with_pg do |conn|
        score = conn.columns("users").find { |c| c.name == "score" }
        expect(score.sql_type).to eq("double precision")
      end
    end

    it "maps BIGINT UNSIGNED foreign key columns to bigint and keeps the foreign key" do
      with_pg do |conn|
        order_id = conn.columns("order_items").find { |c| c.name == "order_id" }
        expect(order_id.sql_type).to eq("bigint")
        expect(conn.foreign_keys("order_items").map(&:to_table)).to include("orders")
      end
    end

    it "excludes the ignored FULLTEXT index from output" do
      with_pg do |conn|
        expect(conn.indexes("posts").map(&:name)).not_to include("index_posts_on_body")
      end
    end

    it "excludes the ignored POINT column from output" do
      with_pg do |conn|
        expect(conn.columns("posts").map(&:name)).not_to include("location")
      end
    end

    it "creates prefix indexes without the length option" do
      with_pg do |conn|
        expect(conn.indexes("posts").map(&:name)).to include("index_posts_on_title_prefix")
      end
    end

    it "shortens index names beyond PostgreSQL's 63-byte limit" do
      with_pg do |conn|
        names = conn.indexes("users").map(&:name)
        expect(names).to include(match(/\Aindex_users_on_status_x{32}_[0-9a-f]{8}\z/))
      end
    end

    it "drops zero-date defaults" do
      with_pg do |conn|
        legacy = conn.columns("events").find { |c| c.name == "legacy_at" }
        expect(legacy.default).to be_nil
      end
    end

    it "converts enum columns to varchar by default" do
      with_pg do |conn|
        kind = conn.columns("users").find { |c| c.name == "kind" }
        expect(kind.sql_type).to eq("character varying")
        expect(kind.default).to eq("active")
      end
    end

    it "is idempotent: a second run reports no change" do
      expect(pipeline.dry_run).to include("No change")
    end
  end

  describe "timestamptz via map_type" do
    let(:timestamptz_pipeline) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        map_type :datetime, to: :timestamptz
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
      end
    end

    before(:all) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        map_type :datetime, to: :timestamptz
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
      end.apply!
    end

    it "converts datetime columns to timestamptz" do
      with_pg do |conn|
        col = conn.columns("users").find { |c| c.name == "created_at" }
        expect(col.sql_type).to eq("timestamp with time zone")
      end
    end

    it "is idempotent: a second run reports no change" do
      expect(timestamptz_pipeline.dry_run).to include("No change")
    end
  end

  describe "enum_as :check" do
    let(:check_pipeline) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        enum_as :check
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
      end
    end

    before(:all) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        enum_as :check
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
      end.apply!
    end

    it "adds a CHECK constraint for enum values" do
      with_pg do |conn|
        chk = conn.check_constraints("users").find { |c| c.name == "chk_users_kind" }
        expect(chk).not_to be_nil
      end
    end

    it "is idempotent: a second run reports no change" do
      expect(check_pipeline.dry_run).to include("No change")
    end
  end

  def with_pg(&)
    SchemaFerry::Source::ConnectionRegistry.with_connection(POSTGRES_URL, &)
  end

  def setup_source_schema
    SchemaFerry::Source::ConnectionRegistry.with_connection(MYSQL_URL) do |conn|
      conn.create_table :users, force: true do |t|
        t.string  :name,     null: false
        t.string  :email,    null: false
        t.integer :status,   default: 0
        t.integer :counter,  unsigned: true
        t.bigint  :visits,   unsigned: true
        t.bigint  :points,   unsigned: true, default: 0
        t.decimal :balance,  precision: 12, scale: 2, default: "0.0"
        t.float   :score
        t.column  :kind, "enum('active','archived')", default: "active", null: false
        t.json    :metadata
        t.timestamps null: false
      end
      conn.add_index :users, :email, unique: true, name: "index_users_on_email"
      conn.add_index :users, :status, name: "index_users_on_status_#{"x" * 42}"

      conn.create_table :posts, force: true do |t|
        t.bigint  :user_id,  null: false
        t.string  :title,    null: false
        t.text    :body
        t.column  :location, "point"
        t.timestamps null: false
      end
      conn.add_index :posts, :body, type: :fulltext, name: "index_posts_on_body"
      conn.add_index :posts, :title, length: 10, name: "index_posts_on_title_prefix"

      conn.create_table :api_keys, id: :string, force: true do |t|
        t.string :label
      end

      conn.create_table :memberships, primary_key: %i[user_id group_id], force: true do |t|
        t.bigint :user_id
        t.bigint :group_id
      end

      # The standard Rails-on-MySQL layout: BIGINT UNSIGNED primary keys with
      # a real FOREIGN KEY between them (raw SQL — AR cannot declare them).
      conn.execute("DROP TABLE IF EXISTS order_items, orders")
      conn.execute(<<~SQL)
        CREATE TABLE orders (
          id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
          total BIGINT UNSIGNED
        )
      SQL
      conn.execute(<<~SQL)
        CREATE TABLE order_items (
          id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
          order_id BIGINT UNSIGNED NOT NULL,
          CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders (id)
        )
      SQL

      conn.create_table :events, force: true do |t|
        t.datetime :logged_at, precision: nil, default: -> { "CURRENT_TIMESTAMP" }
      end
      conn.execute("SET SESSION sql_mode = ''")
      conn.execute("ALTER TABLE events ADD COLUMN legacy_at DATETIME DEFAULT '0000-00-00 00:00:00'")
    end
  end

  def all_tables
    %i[order_items orders posts users api_keys memberships events]
  end

  def teardown_source_schema
    SchemaFerry::Source::ConnectionRegistry.with_connection(MYSQL_URL) do |conn|
      all_tables.each { |t| conn.drop_table(t, if_exists: true) }
    end
  end

  def teardown_target_schema
    SchemaFerry::Source::ConnectionRegistry.with_connection(POSTGRES_URL) do |conn|
      all_tables.each { |t| conn.drop_table(t, if_exists: true) }
    end
  end
end
