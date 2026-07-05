# frozen_string_literal: true

require "open3"
require "tempfile"

module SchemaFerry
  module Target
    # Runs ridgepole as a subprocess rather than via Ridgepole::Client:
    # the client calls ActiveRecord::Base.establish_connection and patches AR
    # in-process, which would hijack a host Rails app's database connection.
    # The tempfile exists because the CLI only reads the schema from -f FILE.
    class RidgepoleRunner
      def initialize(target_url)
        @target_url = target_url
      end

      def run(schema_content, dry_run: false)
        bin = find_ridgepole!

        Tempfile.create(["schema_ferry_", ".rb"]) do |f|
          f.write(schema_content)
          f.flush

          cmd = [bin, "--apply", "-c", @target_url, "-f", f.path]
          cmd << "--dry-run" if dry_run

          stdout, stderr, status = Open3.capture3(*cmd)
          raise RidgepoleError, [stdout, stderr].reject { |s| s.strip.empty? }.join("\n") unless status.success?

          stdout
        end
      end

      private

      def find_ridgepole!
        Gem.bin_path("ridgepole", "ridgepole")
      rescue Gem::GemNotFoundException
        raise RidgepoleNotFoundError,
              "ridgepole binary not found. Add gem 'ridgepole' to your Gemfile."
      end
    end
  end
end
