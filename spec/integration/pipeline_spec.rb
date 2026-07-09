# frozen_string_literal: true

MYSQL_URL    = "mysql2://root:password@127.0.0.1:3307/schema_ferry_source"
POSTGRES_URL = "postgresql://postgres:password@127.0.0.1:5433/schema_ferry_target"

# Exercises both the >63-byte table-name ConversionError and MySQL's own
# 64-byte identifier limit, so kept out of every applied pipeline via ignore_table.
LONG_TABLE_NAME = "table_name_over_pg_limit_#{"x" * 39}".freeze
LONG_FK_NAME    = "fk_reviews_author_ref_over_pg_limit_#{"x" * 28}".freeze

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
      table(:users) do
        column :flags, map_type_to: :integer, default: 2
      end
      table(:posts) do
        ignore_column :location
        ignore_index :index_posts_on_body
      end
      ignore_table :old_sessions
      ignore_table LONG_TABLE_NAME
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

  describe "map_type :json, to: :json" do
    let(:json_pipeline) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
        ignore_table LONG_TABLE_NAME
        map_type :json, to: :json
      end
    end

    it "opts out of the default json -> jsonb conversion" do
      expect(json_pipeline.schemafile).to include('t.json "metadata"')
    end
  end

  describe "overlong table names" do
    let(:long_name_pipeline) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
      end
    end

    it "raises without shortening, unlike index/foreign key names" do
      expect { long_name_pipeline.schemafile }
        .to raise_error(SchemaFerry::ConversionError,
                        /table name #{Regexp.escape(LONG_TABLE_NAME.inspect)} exceeds PostgreSQL's 63-byte/)
    end
  end

  describe "#apply!" do
    before(:all) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        table(:users) do
          column :flags, map_type_to: :integer, default: 2
        end
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
        ignore_table :old_sessions
        ignore_table LONG_TABLE_NAME
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

    it "overrides a column's type and default via `column`, away from the tinyint(1)-as-boolean default" do
      with_pg do |conn|
        flags = conn.columns("users").find { |c| c.name == "flags" }
        expect(flags.sql_type).to eq("integer")
        expect(flags.default).to eq(2)
      end
    end

    it "converts enum columns to varchar by default" do
      with_pg do |conn|
        kind = conn.columns("users").find { |c| c.name == "kind" }
        expect(kind.sql_type).to eq("character varying")
        expect(kind.default).to eq("active")
      end
    end

    it "keeps a native tinyint(1) column as boolean when not overridden" do
      with_pg do |conn|
        is_admin = conn.columns("users").find { |c| c.name == "is_admin" }
        expect(is_admin.sql_type).to eq("boolean")
        expect(is_admin.default).to be(false)
      end
    end

    it "excludes the ignored table from output" do
      with_pg do |conn|
        expect(conn.tables).not_to include("old_sessions")
      end
    end

    it "creates a table without a primary key" do
      with_pg do |conn|
        expect(conn.primary_key("audit_trail")).to be_nil
      end
    end

    it "maps DATE and TIME columns" do
      with_pg do |conn|
        cols = conn.columns("audit_trail")
        expect(cols.find { |c| c.name == "occurred_on" }.sql_type).to eq("date")
        expect(cols.find { |c| c.name == "occurred_at" }.sql_type).to eq("time(0) without time zone")
      end
    end

    it "maps BLOB to bytea" do
      with_pg do |conn|
        payload = conn.columns("audit_trail").find { |c| c.name == "payload" }
        expect(payload.sql_type).to eq("bytea")
      end
    end

    it "maps MEDIUMTEXT to text, dropping the size class" do
      with_pg do |conn|
        notes = conn.columns("audit_trail").find { |c| c.name == "notes" }
        expect(notes.sql_type).to eq("text")
      end
    end

    it "maps a signed SMALLINT to smallint" do
      with_pg do |conn|
        severity = conn.columns("audit_trail").find { |c| c.name == "severity" }
        expect(severity.sql_type).to eq("smallint")
      end
    end

    it "preserves a HASH index" do
      with_pg do |conn|
        idx = conn.indexes("lookup_cache").find { |i| i.name == "index_lookup_cache_on_token" }
        expect(idx.using).to eq(:hash)
      end
    end

    it "keeps a foreign key's on_delete/on_update actions and non-conventional column name" do
      with_pg do |conn|
        fk = conn.foreign_keys("reviews").first
        expect(fk.column).to eq("author_ref")
        expect(fk.on_delete).to eq(:cascade)
        expect(fk.on_update).to eq(:cascade)
      end
    end

    it "shortens foreign key names beyond PostgreSQL's 63-byte limit" do
      with_pg do |conn|
        fk = conn.foreign_keys("reviews").first
        expect(fk.name).to match(/\Afk_reviews_author_ref_over_pg_limit_x{18}_[0-9a-f]{8}\z/)
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
        table(:users) do
          column :flags, map_type_to: :integer, default: 2
        end
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
        ignore_table :old_sessions
        ignore_table LONG_TABLE_NAME
      end
    end

    before(:all) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        map_type :datetime, to: :timestamptz
        table(:users) do
          column :flags, map_type_to: :integer, default: 2
        end
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
        ignore_table :old_sessions
        ignore_table LONG_TABLE_NAME
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
        table(:users) do
          column :flags, map_type_to: :integer, default: 2
        end
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
        ignore_table :old_sessions
        ignore_table LONG_TABLE_NAME
      end
    end

    before(:all) do
      SchemaFerry.define do
        source MYSQL_URL
        target POSTGRES_URL
        enum_as :check
        table(:users) do
          column :flags, map_type_to: :integer, default: 2
        end
        table(:posts) do
          ignore_column :location
          ignore_index :index_posts_on_body
        end
        ignore_table :old_sessions
        ignore_table LONG_TABLE_NAME
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

  # No host app to protect here (unlike SchemaFerry::Source::MysqlReader's own
  # connection handling), so plain ActiveRecord::Base is fine for fixture setup.
  def with_connection(url)
    ActiveRecord::Base.establish_connection(url)
    yield ActiveRecord::Base.connection
  ensure
    ActiveRecord::Base.remove_connection
  end

  def with_pg(&)
    with_connection(POSTGRES_URL, &)
  end

  def setup_source_schema
    with_connection(MYSQL_URL) do |conn|
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
        t.column  :flags, "tinyint(1)", default: 2
        t.boolean :is_admin, default: false
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

      # Only ever referenced via ignore_table — proves ignore_table actually
      # keeps a table off the target.
      conn.create_table :old_sessions, force: true do |t|
        t.string :token
      end

      # id: false, plus the MySQL types that had no fixture coverage yet:
      # DATE, TIME, BLOB (-> bytea), MEDIUMTEXT (-> text), and a genuinely
      # signed SMALLINT (as opposed to the UNSIGNED-bump path above).
      conn.create_table :audit_trail, id: false, force: true do |t|
        t.string  :event_type, limit: 50
        t.date    :occurred_on
        t.time    :occurred_at
        t.binary  :payload
        t.column  :notes, "mediumtext"
        t.integer :severity, limit: 2
      end

      # MySQL only honors USING HASH on the MEMORY engine (InnoDB silently
      # ignores it) — this is the only way to get a real using: :hash index.
      conn.execute("DROP TABLE IF EXISTS lookup_cache")
      conn.execute(<<~SQL)
        CREATE TABLE lookup_cache (
          id BIGINT PRIMARY KEY,
          token INT,
          INDEX index_lookup_cache_on_token (token) USING HASH
        ) ENGINE=MEMORY
      SQL

      # A foreign key with a non-conventional column name (author_ref, not
      # user_id), ON DELETE/UPDATE actions, and a name over PostgreSQL's
      # 63-byte identifier limit — none of which order_items/orders above
      # exercises.
      conn.create_table :reviews, force: true do |t|
        t.bigint  :author_ref, null: false
        t.integer :rating
      end
      conn.execute(<<~SQL)
        ALTER TABLE reviews
          ADD CONSTRAINT #{LONG_FK_NAME}
          FOREIGN KEY (author_ref) REFERENCES users (id)
          ON DELETE CASCADE ON UPDATE CASCADE
      SQL

      # Only ever referenced via ignore_table — proves the >63-byte
      # table-name warning fires without ridgepole ever seeing the table.
      conn.execute("DROP TABLE IF EXISTS `#{LONG_TABLE_NAME}`")
      conn.execute("CREATE TABLE `#{LONG_TABLE_NAME}` (id BIGINT PRIMARY KEY)")
    end
  end

  def all_tables
    %i[order_items orders reviews posts users api_keys memberships events
       old_sessions audit_trail lookup_cache] + [LONG_TABLE_NAME.to_sym]
  end

  def teardown_source_schema
    with_connection(MYSQL_URL) do |conn|
      all_tables.each { |t| conn.drop_table(t, if_exists: true) }
    end
  end

  def teardown_target_schema
    with_connection(POSTGRES_URL) do |conn|
      all_tables.each { |t| conn.drop_table(t, if_exists: true) }
    end
  end
end
