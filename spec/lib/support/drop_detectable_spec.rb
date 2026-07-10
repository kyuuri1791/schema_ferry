# frozen_string_literal: true

RSpec.describe SchemaFerry::Support::DropDetectable do
  subject(:detector) { Class.new { include SchemaFerry::Support::DropDetectable }.new }

  def detect(ddl)
    detector.send(:detect_drops, ddl)
  end

  describe "#detect_drops" do
    it "returns an empty array when the DDL has no drops" do
      ddl = <<~DDL
        Apply `Schemafile` (dry-run)
        add_column("users", "nickname", :string, {})
      DDL

      expect(detect(ddl)).to be_empty
    end

    it "detects a column removal" do
      ddl = <<~DDL
        Apply `Schemafile` (dry-run)
        remove_column("users", "legacy_field")
      DDL

      expect(detect(ddl)).to eq(['remove_column("users", "legacy_field")'])
    end

    it "detects an index removal" do
      ddl = 'remove_index("posts", name: "index_posts_on_body")'

      expect(detect(ddl)).to eq([ddl])
    end

    it "detects a foreign key removal" do
      ddl = 'remove_foreign_key("orders", "users")'

      expect(detect(ddl)).to eq([ddl])
    end

    it "detects a check constraint removal" do
      ddl = 'remove_check_constraint("orders", "total >= 0", **{name: "chk_total"})'

      expect(detect(ddl)).to eq([ddl])
    end

    it "detects a table drop" do
      ddl = 'drop_table("old_sessions")'

      expect(detect(ddl)).to eq([ddl])
    end

    it "lists every drop when there are multiple" do
      ddl = <<~DDL
        remove_column("users", "legacy_field")
        remove_index("posts", name: "index_posts_on_body")
      DDL

      expect(detect(ddl)).to eq([
                                  'remove_column("users", "legacy_field")',
                                  'remove_index("posts", name: "index_posts_on_body")'
                                ])
    end

    it "does not false-positive on unrelated lines mentioning a drop operation" do
      ddl = "# remove_column is used to drop a column\nadd_column(\"users\", \"nickname\", :string, {})\n"

      expect(detect(ddl)).to be_empty
    end
  end
end
