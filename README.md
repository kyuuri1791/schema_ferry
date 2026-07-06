# schema_ferry

You're migrating a production MySQL database to PostgreSQL. Moving the data takes days or weeks — and meanwhile, developers keep shipping schema changes to MySQL. schema_ferry is a Ruby gem that keeps the PostgreSQL schema continuously in sync until cutover, driven by a declarative DSL.

- **Incremental by design** — if the source schema changes mid-migration, just run it again; no manual diffing needed
- **Sensible defaults, fully customizable** — built-in type mappings handle most cases; override anything with a few DSL rules
- **Safe to iterate** — `dry_run` shows the exact changes that would be applied, before touching anything

schema_ferry is designed to run repeatedly (e.g. via cron). Data migration is out of scope — pair it with [pgloader](https://github.com/dimitri/pgloader) (one-shot bulk copy) or CDC replication (AWS DMS, [Debezium](https://github.com/debezium/debezium), …), which load rows into the tables schema_ferry keeps in sync.

## Requirements

- Ruby >= 3.1
- ActiveRecord >= 7.1

## Installation

Add to your Gemfile:

```ruby
gem "schema_ferry"
```

```bash
bundle install
```

## Usage

### Basic

```ruby
require "schema_ferry"

pipeline = SchemaFerry.define do
  source "mysql2://user:password@host:3306/source_db"
  target "postgresql://user:password@host:5432/target_db"
end

pipeline.dry_run  # returns the changes that would be applied, without applying them
pipeline.apply!   # applies the schema to PostgreSQL
```

There is also `pipeline.schemafile`, which returns the generated schema as a string without connecting to the target.

`apply!` makes the target match the generated schema — including **dropping** columns and indexes from the target that are not part of it. Before running against a target that holds data, read [Coverage](#coverage) below.

### CLI

For cron jobs — or whenever you'd rather not write a runner script — there is a small CLI. Put the same DSL (without the `SchemaFerry.define` wrapper) in a `Ferryfile`:

```ruby
source "mysql2://user:password@host:3306/source_db"
target "postgresql://user:password@host:5432/target_db"
```

Then:

```bash
schema_ferry dry-run                     # show what would change (reads ./Ferryfile)
schema_ferry apply                       # apply to PostgreSQL
schema_ferry apply -c path/to/Ferryfile  # explicit definition file path
```

Each command prints the changes it applied (or would apply) followed by a one-line summary (`118 tables synced, 3 changes applied`). The exit status is 0 on success and 1 on any error, so cron mail and monitoring can rely on it.

### Custom conversion rules

```ruby
pipeline = SchemaFerry.define do
  source "mysql2://user:password@host:3306/source_db"
  target "postgresql://user:password@host:5432/target_db"

  map_type :datetime, to: :timestamptz # override a default mapping (datetime → timestamp) globally
  map_type :json, to: :json            # e.g. opt out of the default json → jsonb conversion

  table :users do
    map_column :is_admin, type: :boolean # override a specific column's type
    ignore_column :legacy_field          # exclude a column
    ignore_index :idx_old_legacy         # exclude an index
  end

  ignore_table :old_sessions  # exclude an entire table
end
```

The same rules work in a CLI definition file.

### Coverage

schema_ferry syncs what can be done automatically — exactly where possible, or as an approximation with a warning where it isn't — and leaves the rest to add by hand, later. Where there's no reasonable equivalent at all, it raises instead of guessing. Add the column or index by hand once you're fully cut over to PostgreSQL — not before, since `apply!` delegates to [ridgepole](https://github.com/ridgepole/ridgepole), which drops anything missing from the generated schema on a managed table, including something added by hand as a stand-in — but never drops a table that's absent from it entirely.

Review `dry_run` output before your first `apply!` and whenever you change the conversion rules — those are the moments that introduce drops. Unattended runs in between only mirror changes made to the MySQL schema; if even those need review, schedule `dry-run` instead and apply by hand.

Normalized automatically, with a warning to stderr:

- **Index prefix lengths** (`KEY (col(10))`) are dropped silently — PostgreSQL indexes the full column.
- **Identifiers over 63 bytes** (MySQL allows 64): index and foreign key names are shortened deterministically (`first 54 bytes + _ + 8-char digest`), so repeated runs stay stable. Overlong table names are only warned about — rename those yourself.
- **Zero-date defaults** (`'0000-00-00 00:00:00'`) are invalid in PostgreSQL and are dropped.
- **BIGINT UNSIGNED columns on a foreign key** (either side) become signed `bigint` instead of `numeric(20)` — a numeric column cannot reference a bigint primary key. Values above 2⁶³−1 will not fit, the same trade-off as for `BIGINT UNSIGNED` primary keys.

Raises instead:

- **FULLTEXT indexes** — PostgreSQL has no equivalent construct (a `pg_trgm` GIN index is a common approximation, but it's not the same search semantics, so schema_ferry doesn't create one for you). Because of the drop behavior above, you can't pre-create a replacement during the sync period — add one once you're fully cut over to PostgreSQL. `ignore_index` them.
- **Spatial columns** (`POINT`, `GEOMETRY`, `POLYGON`, `LINESTRING`, …) — PostgreSQL has no built-in equivalent without PostGIS, which schema_ferry does not manage. `ignore_column` them.

## DSL reference

### Top-level

| Method | Description |
|---|---|
| `source "mysql2://..."` | Source MySQL connection string |
| `target "postgresql://..."` | Target PostgreSQL connection string |
| `map_type :from, to: :to` | Override a type globally (e.g. `map_type :datetime, to: :timestamptz`) |
| `enum_as :check` | Convert enum columns to varchar **plus a CHECK constraint** (default `:string` = plain varchar) |
| `ignore_table :name` | Exclude a table from conversion |
| `table :name do ... end` | Define per-table rules |

### Inside a `table` block

| Method | Description |
|---|---|
| `map_column :col, type: :type` | Override a column's type |
| `map_column :col, type: :type, default: value` | …and give it an explicit default |
| `ignore_column :col` | Exclude a column |
| `ignore_index :index_name` | Exclude an index |

Ignoring a column also drops indexes and foreign keys that reference it. Renaming tables or columns is out of scope — clean up names after the cutover with a regular migration.

**tinyint(1) caveat:** ActiveRecord reads `tinyint(1)` as boolean, including its default (`DEFAULT 2` is read as `true`). If a `tinyint(1)` column actually holds 0/1/2-style values, override both the type and the default: `map_column :flags, type: :integer, default: 2`. Without an explicit default, schema_ferry drops the unreliable boolean default and warns.

## Default type mapping

| MySQL | PostgreSQL | Notes |
|---|---|---|
| `VARCHAR(n)` / `CHAR(n)` | `varchar(n)` | length preserved |
| `TEXT` / `MEDIUMTEXT` / `LONGTEXT` | `text` | size classes dropped — PostgreSQL `text` is unbounded |
| `TINYINT(1)` | `boolean` | see the caveat above if a column holds more than 0/1 |
| `TINYINT`…`BIGINT` (signed) | `smallint` / `integer` / `bigint` | widths normalized to PostgreSQL's three integer sizes |
| `TINYINT`…`INT` `UNSIGNED` | one size larger | e.g. `INT UNSIGNED` → `bigint` |
| `BIGINT UNSIGNED` | `numeric(20)` | PostgreSQL has no unsigned 8-byte integer; emitted with a warning. Columns on a foreign key become signed `bigint` instead — see above |
| `FLOAT` / `DOUBLE` | `double precision` | |
| `DECIMAL(p,s)` | `numeric(p,s)` | |
| `DATETIME` / `TIMESTAMP` | `timestamp` | use `map_type :datetime, to: :timestamptz` for `timestamptz` |
| `DATE` / `TIME` | `date` / `time` | |
| `BINARY` / `BLOB` family | `bytea` | |
| `JSON` | `jsonb` | opt out with `map_type :json, to: :json` |
| `ENUM(...)` | `varchar` | add `enum_as :check` to enforce the values with a CHECK constraint |

`map_type` / `map_column` take Rails-style abstract type symbols (`:string`, `:integer`, `:jsonb`, …), not raw SQL type names.

## How it works

Each run executes a three-stage pipeline:

```
MySQL schema
     │
     │  1. Read (ActiveRecord)
     ▼
table definitions
     │
     │  2. Convert (default mappings + your DSL rules)
     ▼
Schemafile
     │
     │  3. Apply (ridgepole, diff only)
     ▼
PostgreSQL schema
```

1. **Read** — connects to MySQL and reads table definitions (columns, indexes, foreign keys) via ActiveRecord, using a connection pool isolated from any host Rails app
2. **Convert** — applies the default type mappings and your custom rules to build a PostgreSQL-ready schema
3. **Apply** — renders the schema as a [ridgepole](https://github.com/ridgepole/ridgepole) Schemafile and runs `ridgepole --apply` (or `--dry-run`) against the target database. ridgepole compares the declared schema with the target's current state and applies only the difference — that diffing is what makes runs incremental and idempotent, so schema_ferry never has to track what it applied before

## Development

```bash
bundle install
bundle exec rubocop
```

### Unit tests

Cover the DSL, conversion rules, and schema rendering. No database needed:

```bash
bundle exec rspec spec/lib/
```

### Integration tests

Run the full pipeline against real MySQL and PostgreSQL containers:

```bash
docker compose up -d --wait
INTEGRATION=true bundle exec rspec spec/integration/
docker compose down
```

## License

[MIT License](https://opensource.org/licenses/MIT)
