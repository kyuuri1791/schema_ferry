# frozen_string_literal: true

# Plain data structs for the converted (PostgreSQL-side) schema: SchemaConverter
# builds these, SchemafileRenderer reads them.
module SchemaFerry
  TableSchema = Struct.new(
    :name,              # String
    :primary_key,       # String | Array<String> | nil
    :pk_type,           # Symbol: :bigint, :integer, :string, etc. (single-column PK only)
    :pk_limit,          # Integer | nil (limit of a string PK column)
    :comment,           # String | nil
    :columns,           # Array<ColumnSchema>
    :indexes,           # Array<IndexSchema>
    :foreign_keys,      # Array<ForeignKeySchema>
    :check_constraints, # Array<CheckConstraintSchema>
    keyword_init: true
  )

  ColumnSchema = Struct.new(
    :name,       # String
    :type,       # Symbol (:string, :integer, :jsonb, …)
    :limit,      # Integer | nil
    :precision,  # Integer | nil
    :scale,      # Integer | nil
    :null,             # Boolean
    :default,          # Object | nil
    :default_function, # String | nil (e.g. "CURRENT_TIMESTAMP")
    :comment,          # String | nil
    keyword_init: true
  )

  IndexSchema = Struct.new(
    :name,    # String
    :columns, # Array<String>
    :unique,  # Boolean
    :using,   # Symbol | nil
    :lengths, # Integer | Hash | nil
    :orders,  # Symbol | Hash | nil
    keyword_init: true
  )

  CheckConstraintSchema = Struct.new(
    :expression, # String (e.g. "kind IN ('a', 'b')")
    :name,       # String
    keyword_init: true
  )

  ForeignKeySchema = Struct.new(
    :from_table,  # String
    :to_table,    # String
    :column,      # String
    :primary_key, # String
    :on_update,   # Symbol | nil
    :on_delete,   # Symbol | nil
    :name,        # String | nil
    keyword_init: true
  )
end
