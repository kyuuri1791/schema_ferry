# frozen_string_literal: true

module SchemaFerry
  module IO
    class MysqlReader
      def initialize(url)
        @url = url
      end

      def read_all
        with_connection do |conn|
          conn.tables.sort.map { |table_name| read_table(conn, table_name) }
        end
      rescue ConnectionError
        raise
      rescue StandardError => e
        raise ReadError, e.message
      end

      private

      # Uses a fresh ConnectionHandler per call so the pool is fully isolated
      # from ActiveRecord::Base and any host Rails app connections.
      # AR 7.2+ banned anonymous AR subclasses, so we bypass that path entirely.
      def with_connection
        handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
        begin
          pool = handler.establish_connection(@url, owner_name: "schema_ferry")
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

      def read_table(conn, name)
        {
          name:         name,
          primary_key:  conn.primary_key(name),
          comment:      conn.table_comment(name),
          columns:      serialize_columns(conn.columns(name)),
          indexes:      serialize_indexes(conn.indexes(name)),
          foreign_keys: serialize_foreign_keys(conn.foreign_keys(name))
        }
      end

      def serialize_columns(columns)
        fields = %i[name type sql_type limit precision scale null default default_function comment]
        columns.map { |c| fields.to_h { |field| [field, c.public_send(field)] } }
      end

      def serialize_indexes(indexes)
        indexes.map do |idx|
          {
            name:    idx.name,
            columns: Array(idx.columns), # idx.columns can be an Array or a String
            unique:  idx.unique,
            using:   idx.using,
            type:    idx.type,
            lengths: idx.lengths,
            orders:  idx.orders
          }
        end
      end

      def serialize_foreign_keys(fkeys)
        fields = %i[from_table to_table column primary_key on_update on_delete name]
        fkeys.map { |fk| fields.to_h { |field| [field, fk.public_send(field)] } }
      end
    end
  end
end
