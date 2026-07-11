# frozen_string_literal: true

RSpec.describe SchemaFerry::Core::Translator do
  include Fixtures

  def make_config(&block)
    config = SchemaFerry::Config.new
    config.instance_eval(&block) if block
    config
  end

  subject(:translator) { described_class.new(config) }

  let(:config) { make_config }

  describe "ignore_table" do
    let(:config) { make_config { ignore_table :old_sessions } }
    let(:raw_tables) { [build_raw_table(name: "users"), build_raw_table(name: "old_sessions")] }

    it "excludes the ignored table from the schemafile" do
      schemafile = translator.translate(raw_tables)
      expect(schemafile).to include('create_table "users"')
      expect(schemafile).not_to include('create_table "old_sessions"')
    end
  end

  describe "foreign key survival" do
    let(:config) do
      make_config do
        ignore_table :old_sessions
        table(:users) { ignore_column :legacy }
      end
    end

    let(:raw_tables) do
      [build_raw_table(
        name:         "users",
        columns:      [
          build_raw_column(name: "legacy"),
          build_raw_column(name: "session_id"),
          build_raw_column(name: "profile_id")
        ],
        foreign_keys: [
          build_raw_fk(from_table: "users", to_table: "accounts", column: "legacy"),
          build_raw_fk(from_table: "users", to_table: "old_sessions", column: "session_id"),
          build_raw_fk(from_table: "users", to_table: "profiles", column: "profile_id")
        ]
      )]
    end

    it "keeps foreign keys unrelated to any ignore rule" do
      expect(translator.translate(raw_tables)).to include('add_foreign_key "users", "profiles"')
    end

    it "drops foreign keys on an ignored column" do
      expect(translator.translate(raw_tables)).not_to include('add_foreign_key "users", "accounts"')
    end

    it "drops foreign keys pointing at an ignored table" do
      expect(translator.translate(raw_tables)).not_to include('add_foreign_key "users", "old_sessions"')
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
      schemafile = nil
      expect { schemafile = translator.translate(raw_tables) }
        .to output(/takes part in a foreign key/).to_stderr
      expect(schemafile).to include('t.bigint "user_id"')
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
        schemafile = nil
        expect { schemafile = translator.translate(raw_tables) }
          .to output(/takes part in a foreign key/).to_stderr
        expect(schemafile).to include('t.bigint "ref"')
      end
    end

    it "keeps decimal(20, 0) when the foreign key is dropped by ignore_table" do
      config.ignore_table :users
      schemafile = nil
      expect { schemafile = translator.translate(raw_tables) }
        .to output(/decimal\(20, 0\)/).to_stderr
      expect(schemafile).to include('t.decimal "user_id", precision: 20')
    end
  end
end
