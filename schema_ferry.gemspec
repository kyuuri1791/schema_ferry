# frozen_string_literal: true

require_relative "lib/schema_ferry/version"

Gem::Specification.new do |spec|
  spec.name     = "schema_ferry"
  spec.version  = SchemaFerry::VERSION
  spec.authors  = ["kyuuri1791"]
  spec.homepage = "https://github.com/kyuuri1791/schema_ferry"
  spec.summary  = "Continuously sync MySQL schema definitions to PostgreSQL via a declarative DSL."
  spec.license  = "MIT"
  spec.description = "schema_ferry keeps a PostgreSQL schema in sync with a MySQL source during a gradual " \
                     "migration. It reads the MySQL schema through ActiveRecord, converts it to PostgreSQL " \
                     "equivalents — with a declarative DSL for type mappings, enum handling, and per-table " \
                     "overrides — and applies only the diff, idempotently, via ridgepole. Ships a Ruby API " \
                     "and a cron-friendly CLI."

  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"]          = spec.homepage
  spec.metadata["source_code_uri"]       = spec.homepage
  spec.metadata["changelog_uri"]         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.bindir        = "exe"
  spec.executables   = ["schema_ferry"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.1"
  spec.add_dependency "mysql2",       "~> 0.5"
  spec.add_dependency "pg",           "~> 1.5"
  spec.add_dependency "ridgepole",    "~> 3.0"
end
