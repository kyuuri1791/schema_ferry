# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `apply!(allow_drops: false)` — refuses to apply anything (raising `SchemaFerry::DropNotAllowedError` instead) whenever the diff contains a column, index, foreign key, or constraint drop. The default remains `allow_drops: true`, matching the gem's "MySQL is the source of truth" philosophy, but this gives an escape hatch for handoff periods where a target-only addition might otherwise get swept up in a legitimate MySQL-driven drop. The CLI exposes the same behavior via `schema_ferry apply --disable-drops`.

### Changed

- `map_column :col, type: :type` is now `column :col, map_type_to: :type`. `map_column` implied a mapping between two columns, which isn't what it does — it overrides one column's own type in place. `column` pairs with the existing `table` block, and `map_type_to:` mirrors `map_type`'s `to:` keyword for the same kind of type override.
- `apply!` now wraps the whole migration in a single transaction (via ridgepole's `--pre-query`/`--post-query`), so a failure partway through no longer leaves a half-applied schema on the target.
- A table name over 63 bytes now raises `SchemaFerry::ConversionError` instead of just warning. `apply!` was never actually going to succeed for it anyway — ActiveRecord's own PostgreSQL schema statements reject an over-length `create_table` outright — so the warning was misleading about how far the pipeline would actually get. `ignore_table` it, or rename it in MySQL.

### Removed

- `Pipeline#schemafile` — it exposed the generated ridgepole Schemafile as a string without connecting to the target. That text is an internal hand-off format between schema_ferry and ridgepole, and keeping it public meant committing to a stable, human-friendly rendering of it forever. Pipeline's API is now just `dry_run` and `apply!`; to preview what a run would do, use `dry_run` — it shows the actual diff against the target rather than the full declared schema.

### Fixed

- A MySQL `MULTIPOINT` column silently passed through as a plain PostgreSQL integer instead of raising. ActiveRecord misdetects `MULTIPOINT` as `:integer`, the same bug that already affected `POINT` — the check only matched `POINT` by name, so `MULTIPOINT` slipped past it. All eight MySQL spatial types (`GEOMETRY`, `POINT`, `LINESTRING`, `POLYGON`, `MULTIPOINT`, `MULTILINESTRING`, `MULTIPOLYGON`, `GEOMETRYCOLLECTION`) are now matched directly by `sql_type`, so they all raise the same explicit "no PostgreSQL equivalent without PostGIS" error instead of some going through a generic "unknown type" message.

## [0.2.0] - 2026-07-06

### Removed

- `add_index` — declaring a PostgreSQL-only index existed solely as a replacement path for skipped FULLTEXT indexes, but that undermined the tool's own "faithful mirror of MySQL" design: it was the only way to declare something with no MySQL counterpart. It also had its own bug — an index with a `where:` clause was dropped and re-created on every single run, because PostgreSQL rewrites predicates (operators, casts, parenthesization) when it stores them, so a declared clause can never reliably match what's on the target. A `pg_trgm` GIN index (or similar) is still the way to replace a FULLTEXT index, but only by hand, once you're fully cut over to PostgreSQL.

### Changed

- `FULLTEXT`/`SPATIAL` indexes and spatial columns (`POINT`, `GEOMETRY`, `POLYGON`, `LINESTRING`, …) now raise `ConversionError` instead of printing a warning and silently excluding themselves. A warning is easy to miss in an unattended cron run's output; raising fails the same way any other error does — a non-zero exit status a monitor can catch. Exclude them explicitly with `ignore_index` / `ignore_column`.

### Fixed

- `POINT` columns are now caught and raise `ConversionError`, like other unsupported spatial types (`GEOMETRY`/`POLYGON`/`LINESTRING`/etc.), instead of silently becoming a meaningless `integer NOT NULL` column. ActiveRecord's mysql2 adapter misreports `POINT` as plain `:integer` — the string "point" happens to match an unanchored `/int/i` pattern deep in ActiveRecord's generic type map — unlike the others, which already came through as an unrecognized type and were rejected.

## [0.1.3] - 2026-07-06

### Fixed

- The 0.1.2 fix only covered the two reported cases, not the underlying pattern: any type/option combination that PostgreSQL can't actually reproduce back to ActiveRecord causes `apply!` to re-run `change_column` forever, because ridgepole compares the declaration against a state it can never match.
  - `DOUBLE` columns (`:float`) are read with `limit: 53` (the type's internal bit width), but a PostgreSQL column never reports a limit back. `limit` is no longer emitted for `:float` columns.
  - Plain `DECIMAL` columns with a default (not just ones bumped from `BIGINT UNSIGNED`) now render their default as a string, matching the form ActiveRecord's schema dumper uses for decimal defaults — the same fix from 0.1.2, generalized to `TypeMapper` so it applies to every decimal column instead of only the unsigned-bigint conversion path.

## [0.1.2] - 2026-07-06

### Fixed

- `map_type :datetime, to: :timestamptz` no longer produces a schema that never converges: ActiveRecord's PostgreSQL adapter silently ignores a `precision:` option on `:timestamptz` columns (unlike `:datetime`/`:timestamp`/`:time`, where it's honored), so declaring one caused `apply!` to re-run `change_column` on every single run. `precision` is no longer emitted for `:timestamptz` columns.
- `BIGINT UNSIGNED` columns with a default value (e.g. `DEFAULT 0`) no longer cause `apply!` to re-run `change_column` on every run after the initial `apply!`. The default is now converted to match the string form ActiveRecord's schema dumper uses for decimal defaults, so it matches ridgepole's exported state instead of diffing against it forever.

## [0.1.1] - 2026-07-06

### Fixed

- `apply!` no longer fails with `PG::DatatypeMismatch` when a `BIGINT UNSIGNED` column takes part in a foreign key — the standard Rails-on-MySQL primary key layout. Such columns are now mapped to signed `bigint` (matching the referenced primary key) instead of `numeric(20)`, with a warning.
- Foreign keys whose column follows the Rails naming convention (`<table>_id`) are no longer dropped and re-created on every run: the generated `add_foreign_key` now omits `column:` for conventional names, matching ridgepole's export format.

## [0.1.0] - 2026-07-06

### Added

- Initial release
- `SchemaFerry.define` DSL — `source` / `target`, `map_type`, `enum_as :check`, `ignore_table`, and per-table rules (`map_column`, `ignore_column`, `ignore_index`, `add_index`)
- `Pipeline#dry_run` / `#apply!` — reads the MySQL schema via ActiveRecord, converts it with the default type mappings plus your rules, and applies the diff to PostgreSQL via ridgepole
- `schema_ferry` CLI (`apply` / `dry-run`) driven by a `Ferryfile`, with a one-line summary and cron-friendly exit status
- Automatic adjustments with warnings: unsigned integer widening, FULLTEXT/SPATIAL index skipping, 63-byte identifier shortening, zero-date default removal
