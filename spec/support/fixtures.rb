# frozen_string_literal: true

module Fixtures
  def build_column(name:, type: :string, **opts)
    SchemaFerry::Support::ColumnSchema.new(
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
    SchemaFerry::Support::IndexSchema.new(
      name:    name.to_s,
      columns: Array(columns).map(&:to_s),
      unique:  unique,
      using:   nil,
      lengths: nil,
      orders:  nil,
      **opts
    )
  end

  def build_fk(from_table:, to_table:, column:, **opts)
    SchemaFerry::Support::ForeignKeySchema.new(
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
    SchemaFerry::Support::TableSchema.new(
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

  # The raw hash mirrors MysqlReader's output: a faithful transcription where
  # columns include the PK column. The pk_* args describe that column.
  def build_raw_table(name:, columns: [], indexes: [], foreign_keys: [],
                      primary_key: "id", pk_type: :bigint, pk_limit: nil,
                      pk_sql_type: "bigint", comment: nil)
    pk_column =
      if primary_key.is_a?(String)
        build_raw_column(name: primary_key, type: pk_type, sql_type: pk_sql_type, limit: pk_limit)
      end
    {
      name:         name.to_s,
      primary_key:  primary_key,
      comment:      comment,
      columns:      [pk_column, *columns].compact,
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
