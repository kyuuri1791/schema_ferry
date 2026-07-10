# schema_ferry

You're migrating a production MySQL database to PostgreSQL. Moving the data takes days or weeks — and meanwhile, developers keep shipping schema changes to MySQL. schema_ferry is a Ruby gem that keeps the PostgreSQL schema continuously in sync until cutover, driven by a declarative DSL.

- **Incremental by design** — if the source schema changes mid-migration, just run it again; no manual diffing needed
- **Sensible defaults, fully customizable** — built-in type mappings handle most cases; override anything with a few DSL rules
- **Safe to iterate** — `dry_run` shows the exact changes that would be applied, before touching anything

schema_ferry is designed to run repeatedly — as a step in whatever CI/CD pipeline you already have (Jenkins, Step Functions, GitHub Actions, …). Data migration is out of scope — pair it with [pgloader](https://github.com/dimitri/pgloader) (one-shot bulk copy) or CDC replication (AWS DMS, [Debezium](https://github.com/debezium/debezium), …), which load rows into the tables schema_ferry keeps in sync.

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

`apply!` makes the target match the generated schema — including **dropping** columns, indexes, foreign keys, and constraints from the target that are not part of it. Before running against a target that holds data, read [Handoff](#handoff) below.

### CLI

As a step in an existing pipeline, or whenever you'd rather not write a runner script, there is a small CLI. Put the same DSL (without the `SchemaFerry.define` wrapper) in a `Ferryfile`:

```ruby
source "mysql2://user:password@host:3306/source_db"
target "postgresql://user:password@host:5432/target_db"
```

Then:

```bash
schema_ferry dry-run                     # show what would change (reads ./Ferryfile)
schema_ferry apply                       # apply to PostgreSQL
schema_ferry apply -c path/to/Ferryfile  # explicit definition file path
schema_ferry apply --disable-drops       # refuse instead of applying if the diff contains a drop
```

Each command prints the changes it applied (or would apply) followed by a one-line summary (`118 tables synced, 3 changes applied`). The exit status is 0 on success and 1 on any error, so your monitoring can rely on it.

### Custom conversion rules

```ruby
pipeline = SchemaFerry.define do
  source "mysql2://user:password@host:3306/source_db"
  target "postgresql://user:password@host:5432/target_db"

  map_type :datetime, to: :timestamptz # override a default mapping (datetime → timestamp) globally
  map_type :json, to: :json            # e.g. opt out of the default json → jsonb conversion

  table :users do
    column :is_admin, map_type_to: :boolean # override a specific column's type
    ignore_column :legacy_field          # exclude a column
    ignore_index :idx_old_legacy         # exclude an index
  end

  ignore_table :old_sessions  # exclude an entire table
end
```

The same rules work in a `Ferryfile`.

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
| `column :col, map_type_to: :type` | Override a column's type |
| `column :col, map_type_to: :type, default: value` | …and give it an explicit default |
| `ignore_column :col` | Exclude a column |
| `ignore_index :index_name` | Exclude an index |

Ignoring a column also drops indexes and foreign keys that reference it.

**tinyint(1) caveat:** ActiveRecord reads `tinyint(1)` as boolean, including its default (`DEFAULT 2` is read as `true`). If a `tinyint(1)` column actually holds 0/1/2-style values, override both the type and the default: `column :flags, map_type_to: :integer, default: 2`. Without an explicit default, schema_ferry drops the unreliable boolean default and warns.

## Default type mapping

| MySQL | PostgreSQL | Notes |
|---|---|---|
| `VARCHAR(n)` / `CHAR(n)` | `varchar(n)` | length preserved |
| `TEXT` / `MEDIUMTEXT` / `LONGTEXT` | `text` | size classes dropped — PostgreSQL `text` is unbounded |
| `TINYINT(1)` | `boolean` | see the caveat above if a column holds more than 0/1 |
| `TINYINT`…`BIGINT` (signed) | `smallint` / `integer` / `bigint` | widths normalized to PostgreSQL's three integer sizes |
| `TINYINT`…`INT` `UNSIGNED` | one size larger | e.g. `INT UNSIGNED` → `bigint` |
| `BIGINT UNSIGNED` | `numeric(20)` | PostgreSQL has no unsigned 8-byte integer; emitted with a warning. Columns on a foreign key become signed `bigint` instead — see [Handoff](#handoff) below |
| `FLOAT` / `DOUBLE` | `double precision` | |
| `DECIMAL(p,s)` | `numeric(p,s)` | |
| `DATETIME` / `TIMESTAMP` | `timestamp` | use `map_type :datetime, to: :timestamptz` for `timestamptz` |
| `DATE` / `TIME` | `date` / `time` | |
| `BINARY` / `BLOB` family | `bytea` | |
| `JSON` | `jsonb` | opt out with `map_type :json, to: :json` |
| `ENUM(...)` | `varchar` | add `enum_as :check` to enforce the values with a CHECK constraint |

`map_type` / `column`'s `map_type_to:` take Rails-style abstract type symbols (`:string`, `:integer`, `:jsonb`, …), not raw SQL type names.

## Handoff

MySQL is the source of truth: `apply!` makes PostgreSQL match the generated schema exactly, so anything else on the target — including a column or index added by hand as an early stand-in — gets dropped. That's intentional. Add the real thing by hand once you're fully cut over to PostgreSQL, not before. The one exception is a table absent from the generated schema entirely — that's left alone.

Though that's the philosophy, if you don't want it, you can switch it off with `apply!(allow_drops: false)`: `apply!` then only goes through when the diff is drop-free; otherwise it raises `SchemaFerry::DropNotAllowedError` instead of applying anything to the target.

Within that generated schema, schema_ferry syncs what can be done automatically — exactly where possible, or as an approximation with a warning where it isn't — and leaves the rest to add by hand, later. Where there's no reasonable equivalent at all, it raises instead of guessing.

Normalized automatically, with a warning to stderr:

- **Index prefix lengths** (`KEY (col(10))`) are dropped silently — PostgreSQL indexes the full column.
- **Index and foreign key names over 63 bytes** (MySQL allows 64) are shortened deterministically (`first 54 bytes + _ + 8-char digest`), so repeated runs stay stable.
- **Zero-date defaults** (`'0000-00-00 00:00:00'`) are invalid in PostgreSQL and are dropped.
- **BIGINT UNSIGNED columns on a foreign key** (either side) become signed `bigint` instead of `numeric(20)` — a numeric column cannot reference a bigint primary key. Values above 2⁶³−1 will not fit, the same trade-off as for `BIGINT UNSIGNED` primary keys.

Raises instead:

- **FULLTEXT indexes** — PostgreSQL has no equivalent construct (a `pg_trgm` GIN index is a common approximation, but it's not the same search semantics, so schema_ferry doesn't create one for you). Because of the drop behavior above, you can't pre-create a replacement during the sync period — add one once you're fully cut over to PostgreSQL. `ignore_index` them.
- **Spatial columns** (`POINT`, `GEOMETRY`, `POLYGON`, `LINESTRING`, …) — PostgreSQL has no built-in equivalent without PostGIS, which schema_ferry does not manage. `ignore_column` them.
- **Table names over 63 bytes** (MySQL allows 64) — unlike index and foreign key names, schema_ferry won't rename a table for you (too invasive to do silently). `ignore_table` it, or rename it in MySQL.

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
