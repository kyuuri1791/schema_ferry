# frozen_string_literal: true

require "optparse"

module SchemaFerry
  # Minimal command-line interface: `schema_ferry <apply|dry-run> [-c FILE]`.
  # #run returns a process exit code instead of calling Kernel#exit so the
  # class stays testable.
  class CLI
    DEFAULT_CONFIG_PATH = "Ferryfile"
    COMMANDS = %w[apply dry-run].freeze

    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
    end

    def run(argv)
      args = parser.parse(argv)
      return print_and_succeed(parser.to_s) if @mode == :help
      return print_and_succeed(VERSION) if @mode == :version

      command = args.first
      return usage_error("missing command") if command.nil?
      return usage_error("unknown command: #{command}") unless COMMANDS.include?(command)

      run_command(command)
    rescue Error, OptionParser::ParseError => e
      @stderr.puts "schema_ferry: #{e.message}"
      1
    end

    private

    def run_command(command)
      config     = load_config
      schemafile = Pipeline.new(config).schemafile
      dry_run    = command == "dry-run"
      output     = RidgepoleRunner.new(config.target_url).run(schemafile, dry_run: dry_run)

      @stdout.puts output
      @stdout.puts summary(schemafile, output, dry_run: dry_run)
      0
    end

    def summary(schemafile, output, dry_run:)
      tables  = schemafile.scan(/^create_table /).count
      changes = count_changes(output)
      detail  =
        if changes.zero?
          "no changes"
        else
          "#{changes} #{pluralize(changes, "change")} #{dry_run ? "pending" : "applied"}"
        end
      "#{tables} #{pluralize(tables, "table")} #{dry_run ? "checked" : "synced"}, #{detail}"
    end

    # `--apply` echoes each executed operation as a "-- op(...)" line;
    # `--dry-run` prints the pending operations as top-level DSL calls.
    def count_changes(output)
      return 0 if output.include?("No change")

      applied = output.scan(/^-- /).count
      applied.positive? ? applied : output.scan(/^\w+\(/).count
    end

    def pluralize(count, word)
      count == 1 ? word : "#{word}s"
    end

    def load_config
      path = @config_path || DEFAULT_CONFIG_PATH
      raise ConfigError, "definition file not found: #{path}" unless File.exist?(path)

      Config.load_file(path)
    end

    def parser
      @parser ||= OptionParser.new do |o|
        o.banner = "Usage: schema_ferry <apply|dry-run> [options]"
        o.on("-c", "--config FILE", "Definition file (default: #{DEFAULT_CONFIG_PATH})") { |v| @config_path = v }
        o.on("-h", "--help", "Show this help") { @mode = :help }
        o.on("--version", "Show version") { @mode = :version }
      end
    end

    def print_and_succeed(text)
      @stdout.puts text
      0
    end

    def usage_error(message)
      @stderr.puts "schema_ferry: #{message}"
      @stderr.puts parser
      1
    end
  end
end
