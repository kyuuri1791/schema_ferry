# frozen_string_literal: true

RSpec.describe SchemaFerry::DSL::TableRule do
  subject(:rule) { described_class.new(:users) }

  it "stores the table name as a string" do
    expect(rule.table_name).to eq("users")
  end

  describe "#column" do
    it "records a type override" do
      rule.column(:is_admin, map_type_to: :boolean)
      expect(rule.column_type_overrides).to eq("is_admin" => :boolean)
    end

    it "records an explicit default when given" do
      rule.column(:tri, map_type_to: :integer, default: 2)
      expect(rule.column_default_overrides).to eq("tri" => 2)
    end

    it "records an explicit nil default" do
      rule.column(:tri, map_type_to: :integer, default: nil)
      expect(rule.column_default_overrides).to eq("tri" => nil)
    end

    it "records no default override when not given" do
      rule.column(:tri, map_type_to: :integer)
      expect(rule.column_default_overrides).to be_empty
    end
  end

  describe "#ignore_column" do
    it "records ignored columns" do
      rule.ignore_column(:legacy_field)
      rule.ignore_column(:another_field)
      expect(rule.ignored_columns).to contain_exactly("legacy_field", "another_field")
    end
  end

  describe "#ignore_index" do
    it "records ignored indexes" do
      rule.ignore_index(:idx_old)
      expect(rule.ignored_indexes).to contain_exactly("idx_old")
    end
  end
end
