# schema_ferry

A Ruby gem for migrating from MySQL to PostgreSQL: it keeps the PostgreSQL schema in sync with a MySQL schema that keeps evolving while the migration is underway, via a declarative DSL.

- **Incremental by design** — if the source schema changes mid-migration, just run it again; no manual diffing needed
- **Sensible defaults, fully customizable** — built-in type mappings handle most cases; override anything with a declarative DSL
- **Safe to iterate** — `dry_run` shows the exact changes that would be applied, before touching anything

schema_ferry is designed to run repeatedly (e.g. via cron) until the cutover is done. Data migration is out of scope — handle it separately with a dedicated tool that loads rows into the tables schema_ferry has created: e.g. [pgloader](https://pgloader.io/) in data-only mode for a one-shot bulk copy, or CDC-based replication (AWS DMS, [Debezium](https://debezium.io/), etc.) if you want the data to keep following along until cutover, just like the schema does.

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

pipeline.dry_run     # returns the changes that would be applied, without applying them
pipeline.apply!      # applies the schema to PostgreSQL
pipeline.schemafile  # the full generated schema, no target DB needed — handy while
                     # iterating on rules, or to review/apply it yourself
```

> [!WARNING]
> `apply!` delegates to [ridgepole](https://github.com/ridgepole/ridgepole), which makes the target match the generated schema. For tables it manages, **columns and indexes that are missing from the generated schema are dropped from the target** (e.g. a column excluded via `ignore_column`, or an index created by hand on the target — declare those with `add_index` instead); tables absent from the generated schema are themselves left untouched.
>
> Review `dry_run` output before your first `apply!` and whenever you change the conversion rules — those are the moments that introduce drops. Unattended runs in between only mirror changes made to the MySQL schema; if even those need review, schedule `dry-run` instead and apply by hand.

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
| `add_index :col, ...options` | Declare a PostgreSQL-only index (options: `name`, `unique`, `using`, `opclass`, `where`, `order`) |

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
| `BIGINT UNSIGNED` | `numeric(20)` | PostgreSQL has no unsigned 8-byte integer; emitted with a warning |
| `FLOAT` / `DOUBLE` | `double precision` | |
| `DECIMAL(p,s)` | `numeric(p,s)` | |
| `DATETIME` / `TIMESTAMP` | `timestamp` | use `map_type :datetime, to: :timestamptz` for `timestamptz` |
| `DATE` / `TIME` | `date` / `time` | |
| `BINARY` / `BLOB` family | `bytea` | |
| `JSON` | `jsonb` | opt out with `map_type :json, to: :json` |
| `ENUM(...)` | `varchar` | add `enum_as :check` to enforce the values with a CHECK constraint |

`map_type` / `map_column` take Rails-style abstract type symbols (`:string`, `:integer`, `:jsonb`, …), not raw SQL type names.

### Automatic adjustments (with warnings)

Some MySQL constructs have no PostgreSQL equivalent. schema_ferry handles them and prints a `[schema_ferry]` warning to stderr:

- **FULLTEXT / SPATIAL indexes** are skipped. Declare a replacement with `add_index` (e.g. `add_index :body, using: :gin, opclass: :gin_trgm_ops` — requires `CREATE EXTENSION pg_trgm` on the target, done once by hand) and silence the warning with `ignore_index`. Don't create replacement indexes by hand: anything not in the generated schema is dropped on the next run.
- **Index prefix lengths** (`KEY (col(10))`) are dropped silently — PostgreSQL indexes the full column.
- **Identifiers over 63 bytes** (MySQL allows 64): index and foreign key names are shortened deterministically (`first 54 bytes + _ + 8-char digest`), so repeated runs stay stable. Overlong table names are only warned about — rename those yourself.
- **Zero-date defaults** (`'0000-00-00 00:00:00'`) are invalid in PostgreSQL and are dropped.

## How it works

Each run executes a three-stage pipeline:

1. **Read** — connects to MySQL and reads table definitions (columns, indexes, foreign keys) via ActiveRecord, using a connection pool isolated from any host Rails app
2. **Convert** — applies the default type mappings and your custom rules to build a PostgreSQL-ready schema
3. **Apply** — renders the schema as a [ridgepole](https://github.com/ridgepole/ridgepole) Schemafile and runs `ridgepole --apply` (or `--dry-run`) against the target database. ridgepole compares the declared schema with the target's current state and applies only the difference — that diffing is what makes runs incremental and idempotent, so schema_ferry never has to track what it applied before

## Development

```bash
bundle install
bundle exec rubocop  # linter
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
