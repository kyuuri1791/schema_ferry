# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
