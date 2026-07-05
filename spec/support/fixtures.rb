# frozen_string_literal: true

module Fixtures
  def build_column(name:, type: :string, **opts)
    SchemaFerry::ColumnSchema.new(
      name:             name.to_s,
      type:             type,
      limit:            nil,
      precision:        nil,
      scale:            nil,
      null:             true,
      default:          nil,
      default_function: nil,
      comment:          nil,
      **opts
    )
  end

  def build_index(name:, columns:, unique: false, **opts)
    SchemaFerry::IndexSchema.new(
      name:    name.to_s,
      columns: Array(columns).map(&:to_s),
      unique:  unique,
      using:   nil,
      opclass: nil,
      where:   nil,
      lengths: nil,
      orders:  nil,
      **opts
    )
  end

  def build_fk(from_table:, to_table:, column:, **opts)
    SchemaFerry::ForeignKeySchema.new(
      from_table:  from_table.to_s,
      to_table:    to_table.to_s,
      column:      column.to_s,
      primary_key: "id",
      on_update:   nil,
      on_delete:   nil,
      name:        nil,
      **opts
    )
  end

  def build_table(name:, columns: [], indexes: [], foreign_keys: [], **opts)
    SchemaFerry::TableSchema.new(
      name:              name.to_s,
      primary_key:       "id",
      pk_type:           :bigint,
      pk_limit:          nil,
      comment:           nil,
      columns:           columns,
      indexes:           indexes,
      foreign_keys:      foreign_keys,
      check_constraints: [],
      **opts
    )
  end

  def build_raw_table(name:, columns: [], indexes: [], foreign_keys: [],
                      primary_key: "id", pk_type: :bigint, pk_limit: nil,
                      pk_sql_type: "bigint", comment: nil)
    {
      name:         name.to_s,
      primary_key:  primary_key,
      pk_type:      pk_type,
      pk_limit:     pk_limit,
      pk_sql_type:  pk_sql_type,
      comment:      comment,
      columns:      columns,
      indexes:      indexes,
      foreign_keys: foreign_keys
    }
  end

  def build_raw_index(name:, columns:, **opts)
    {
      name:    name.to_s,
      columns: Array(columns).map(&:to_s),
      unique:  false,
      using:   nil,
      type:    nil,
      where:   nil,
      lengths: nil,
      orders:  nil
    }.merge(opts)
  end

  def build_raw_fk(from_table:, to_table:, column:, **opts)
    {
      from_table:  from_table.to_s,
      to_table:    to_table.to_s,
      column:      column.to_s,
      primary_key: "id",
      on_update:   nil,
      on_delete:   nil,
      name:        nil
    }.merge(opts)
  end

  def build_raw_column(name:, type: :string, sql_type: "varchar(255)", **opts)
    {
      name:             name.to_s,
      type:             type,
      sql_type:         sql_type,
      limit:            nil,
      precision:        nil,
      scale:            nil,
      null:             true,
      default:          nil,
      default_function: nil,
      comment:          nil
    }.merge(opts)
  end
end
