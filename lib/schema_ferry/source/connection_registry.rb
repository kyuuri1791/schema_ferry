# frozen_string_literal: true

module SchemaFerry
  module ConnectionRegistry
    # Uses a fresh ConnectionHandler per call so the pool is fully isolated
    # from ActiveRecord::Base and any host Rails app connections.
    # AR 7.2+ banned anonymous AR subclasses, so we bypass that path entirely.
    def self.with_connection(url)
      handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
      begin
        pool = handler.establish_connection(url, owner_name: "schema_ferry")
        conn = pool.checkout
        conn.verify!
      rescue ActiveRecord::ActiveRecordError => e
        raise ConnectionError, e.message
      end

      begin
        yield conn
      ensure
        pool.checkin(conn)
      end
    ensure
      handler&.clear_all_connections!
    end
  end
end
