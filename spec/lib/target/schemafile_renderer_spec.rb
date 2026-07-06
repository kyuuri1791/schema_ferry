# frozen_string_literal: true

RSpec.describe SchemaFerry::Target::SchemafileRenderer do
  include Fixtures

  subject(:renderer) { described_class.new }

  def render(tables)
    renderer.render(tables.is_a?(Array) ? tables : [tables])
  end

  describe "basic table rendering" do
    it "renders a simple create_table block" do
      table = build_table(
        name:    "users",
        columns: [build_column(name: "email", type: :string, limit: 255, null: false)]
      )
      output = render(table)
      expect(output).to include('create_table "users", force: :cascade do |t|')
      expect(output).to include('t.string "email", limit: 255, null: false')
      expect(output).to include("end")
    end

    it "renders a table comment" do
      table  = build_table(name: "users", comment: "registered users")
      output = render(table)
      expect(output).to include('create_table "users", force: :cascade, comment: "registered users" do |t|')
    end
  end

  describe "timestamps collapsing" do
    let(:created_at) { build_column(name: "created_at", type: :datetime, null: false) }
    let(:updated_at) { build_column(name: "updated_at", type: :datetime, null: false) }

    it "collapses created_at + updated_at into t.timestamps" do
      table  = build_table(name: "posts", columns: [created_at, updated_at])
      output = render(table)
      expect(output).to include("t.timestamps")
      expect(output).not_to include('t.datetime "created_at"')
      expect(output).not_to include('t.datetime "updated_at"')
    end

    it "respects null: false on timestamps" do
      table  = build_table(name: "posts", columns: [created_at, updated_at])
      output = render(table)
      expect(output).to include("t.timestamps null: false")
    end

    it "does NOT collapse when only created_at exists" do
      table  = build_table(name: "posts", columns: [created_at])
      output = render(table)
      expect(output).to include('t.datetime "created_at"')
      expect(output).not_to include("t.timestamps")
    end

    it "does NOT collapse when null values differ" do
      ts_null = build_column(name: "updated_at", type: :datetime, null: true)
      table   = build_table(name: "posts", columns: [created_at, ts_null])
      output  = render(table)
      expect(output).not_to include("t.timestamps")
    end

    it "does NOT collapse when types differ" do
      ts_date = build_column(name: "updated_at", type: :date, null: false)
      table   = build_table(name: "posts", columns: [created_at, ts_date])
      output  = render(table)
      expect(output).not_to include("t.timestamps")
    end

    it "does NOT collapse when a default function is present" do
      ts_func = build_column(name: "updated_at", type: :datetime, null: false,
                             default_function: "CURRENT_TIMESTAMP")
      table   = build_table(name: "posts", columns: [created_at, ts_func])
      output  = render(table)
      expect(output).not_to include("t.timestamps")
    end
  end

  describe "primary key options" do
    it "uses id: false when primary_key is nil" do
      table = build_table(name: "join_table", primary_key: nil, pk_type: nil)
      output = render(table)
      expect(output).to include("id: false")
    end

    it "emits primary_key: option for non-default PK name" do
      table = build_table(name: "items", primary_key: "uid")
      output = render(table)
      expect(output).to include('primary_key: "uid"')
    end

    it "emits composite primary key" do
      table = build_table(name: "memberships", primary_key: %w[user_id group_id])
      output = render(table)
      expect(output).to include('primary_key: ["user_id", "group_id"]')
    end

    it "emits id type when not bigint" do
      table = build_table(name: "items", pk_type: :integer)
      output = render(table)
      expect(output).to include("id: :integer")
    end

    it "does NOT emit id option when pk_type is :bigint (default)" do
      table = build_table(name: "items", pk_type: :bigint)
      output = render(table)
      expect(output).not_to include("id: :bigint")
    end

    it "emits id: :string with limit for string PKs" do
      table = build_table(name: "items", pk_type: :string, pk_limit: 36)
      output = render(table)
      expect(output).to include("id: :string, limit: 36")
    end
  end

  describe "check constraints" do
    it "renders t.check_constraint inside the table block" do
      chk   = SchemaFerry::CheckConstraintSchema.new(expression: "kind IN ('a', 'b')", name: "chk_users_kind")
      table = build_table(name: "users", check_constraints: [chk])
      output = render(table)
      expect(output).to include(%(  t.check_constraint "kind IN ('a', 'b')", name: "chk_users_kind"))
    end
  end

  describe "timestamptz columns" do
    it "renders t.timestamptz" do
      col    = build_column(name: "happened_at", type: :timestamptz)
      table  = build_table(name: "events", columns: [col])
      output = render(table)
      expect(output).to include('t.timestamptz "happened_at"')
    end
  end

  describe "default functions" do
    it "renders default_function as a lambda" do
      col    = build_column(name: "created_at", type: :datetime, default_function: "CURRENT_TIMESTAMP")
      table  = build_table(name: "events", columns: [col])
      output = render(table)
      expect(output).to include('t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }')
    end

    it "prefers a literal default over default_function" do
      col    = build_column(name: "status", type: :integer, default: 0, default_function: "now()")
      table  = build_table(name: "events", columns: [col])
      output = render(table)
      expect(output).to include('t.integer "status", default: 0')
      expect(output).not_to include("now()")
    end
  end

  describe "indexes" do
    it "renders index inside the table block" do
      idx   = build_index(name: "index_users_on_email", columns: ["email"], unique: true)
      table = build_table(name: "users", indexes: [idx])
      output = render(table)
      expect(output).to include('t.index ["email"], name: "index_users_on_email", unique: true')
    end

    it "renders index with using clause" do
      idx   = build_index(name: "idx_data_gin", columns: ["data"], using: :gin)
      table = build_table(name: "items", indexes: [idx])
      output = render(table)
      expect(output).to include("using: :gin")
    end

    it "renders index column orders" do
      orders = { "created_at" => :desc }
      idx    = build_index(name: "idx_recent", columns: ["created_at"], orders: orders)
      table  = build_table(name: "events", indexes: [idx])
      output = render(table)
      expect(output).to include("order: #{orders.inspect}")
    end
  end

  describe "foreign keys" do
    it "renders add_foreign_key after all table blocks" do
      fk     = build_fk(from_table: "posts", to_table: "users", column: "user_id")
      table  = build_table(name: "posts", foreign_keys: [fk])
      output = render(table)
      table_pos = output.index("create_table")
      fk_pos    = output.index("add_foreign_key")
      expect(fk_pos).to be > table_pos
    end

    it "omits column: when it follows the Rails convention (matches ridgepole's export)" do
      fk     = build_fk(from_table: "posts", to_table: "users", column: "user_id")
      table  = build_table(name: "posts", foreign_keys: [fk])
      output = render(table)
      expect(output).to include('add_foreign_key "posts", "users"')
      expect(output).not_to include("column:")
    end

    it "renders column: when it differs from the convention" do
      fk     = build_fk(from_table: "posts", to_table: "users", column: "author_id")
      table  = build_table(name: "posts", foreign_keys: [fk])
      output = render(table)
      expect(output).to include('add_foreign_key "posts", "users", column: "author_id"')
    end

    it "renders on_delete option" do
      fk     = build_fk(from_table: "comments", to_table: "posts", column: "post_id", on_delete: :cascade)
      table  = build_table(name: "comments", foreign_keys: [fk])
      output = render(table)
      expect(output).to include("on_delete: :cascade")
    end
  end

  describe "multiple tables" do
    it "separates tables with blank lines" do
      t1 = build_table(name: "users")
      t2 = build_table(name: "posts")
      output = render([t1, t2])
      expect(output).to include("create_table \"users\"")
      expect(output).to include("create_table \"posts\"")
    end

    it "collects all foreign keys at the end" do
      fk1 = build_fk(from_table: "posts",    to_table: "users",  column: "user_id")
      fk2 = build_fk(from_table: "comments", to_table: "posts",  column: "post_id")
      t1  = build_table(name: "posts",    foreign_keys: [fk1])
      t2  = build_table(name: "comments", foreign_keys: [fk2])
      output = render([t1, t2])

      last_table_end = output.rindex("end")
      first_fk_pos   = output.index("add_foreign_key")
      expect(first_fk_pos).to be > last_table_end
    end
  end
end
