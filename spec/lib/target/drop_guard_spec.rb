# frozen_string_literal: true

RSpec.describe SchemaFerry::Target::DropGuard do
  describe ".check!" do
    it "does not raise when the dry-run output has no drops" do
      output = <<~OUTPUT
        Apply `Schemafile` (dry-run)
        add_column("users", "nickname", :string, {})
      OUTPUT

      expect { described_class.check!(output) }.not_to raise_error
    end

    it "raises DropNotAllowedError for a column removal" do
      output = <<~OUTPUT
        Apply `Schemafile` (dry-run)
        remove_column("users", "legacy_field")
      OUTPUT

      expect { described_class.check!(output) }
        .to raise_error(SchemaFerry::DropNotAllowedError, /remove_column\("users", "legacy_field"\)/)
    end

    it "raises for an index removal" do
      output = 'remove_index("posts", name: "index_posts_on_body")'

      expect { described_class.check!(output) }
        .to raise_error(SchemaFerry::DropNotAllowedError, /remove_index/)
    end

    it "raises for a foreign key removal" do
      output = 'remove_foreign_key("orders", "users")'

      expect { described_class.check!(output) }
        .to raise_error(SchemaFerry::DropNotAllowedError, /remove_foreign_key/)
    end

    it "raises for a check constraint removal" do
      output = 'remove_check_constraint("orders", "total >= 0", **{name: "chk_total"})'

      expect { described_class.check!(output) }
        .to raise_error(SchemaFerry::DropNotAllowedError, /remove_check_constraint/)
    end

    it "raises for a table drop" do
      output = 'drop_table("old_sessions")'

      expect { described_class.check!(output) }
        .to raise_error(SchemaFerry::DropNotAllowedError, /drop_table/)
    end

    it "lists every drop when there are multiple" do
      output = <<~OUTPUT
        remove_column("users", "legacy_field")
        remove_index("posts", name: "index_posts_on_body")
      OUTPUT

      expect { described_class.check!(output) }
        .to raise_error(SchemaFerry::DropNotAllowedError) { |e|
          expect(e.message).to include('remove_column("users", "legacy_field")')
          expect(e.message).to include('remove_index("posts", name: "index_posts_on_body")')
        }
    end

    it "does not false-positive on unrelated lines mentioning a drop operation" do
      output = "# remove_column is used to drop a column\nadd_column(\"users\", \"nickname\", :string, {})\n"

      expect { described_class.check!(output) }.not_to raise_error
    end
  end
end
