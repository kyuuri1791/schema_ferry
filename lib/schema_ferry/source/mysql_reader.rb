# frozen_string_literal: true

module SchemaFerry
  module Source
    class MysqlReader
      def initialize(url)
        @url = url
      end

      def read_all
        ConnectionRegistry.with_connection(@url) do |conn|
          conn.tables.sort.map { |table_name| read_table(conn, table_name) }
        end
      rescue ConnectionError
        raise
      rescue StandardError => e
        raise ReadError, e.message
      end

      private

      def read_table(conn, name)
        columns = conn.columns(name)
        pk      = conn.primary_key(name)
        pk_col  = pk.is_a?(String) ? columns.find { |c| c.name == pk } : nil
        {
          name:         name,
          primary_key:  pk,
          pk_type:      pk_col&.type,
          pk_limit:     pk_col&.type == :string ? pk_col.limit : nil,
          pk_sql_type:  pk_col&.sql_type,
          comment:      conn.table_comment(name).presence,
          columns:      serialize_columns(columns, pk),
          indexes:      serialize_indexes(conn.indexes(name)),
          foreign_keys: serialize_foreign_keys(conn.foreign_keys(name), name)
        }
      end

      # A single-column PK is rendered via create_table's id: option, so it is
      # excluded here. Composite PK columns must stay: primary_key: [...] does
      # not create them.
      def serialize_columns(columns, primary_key)
        columns.reject { |c| c.name == primary_key }.map do |c|
          {
            name:             c.name,
            type:             c.type,
            sql_type:         c.sql_type,
            limit:            c.limit,
            precision:        c.precision,
            scale:            c.scale,
            null:             c.null,
            default:          c.default,
            default_function: c.default_function,
            comment:          c.comment
          }
        end
      end

      def serialize_indexes(indexes)
        indexes.map do |idx|
          {
            name:    idx.name,
            columns: Array(idx.columns),
            unique:  idx.unique,
            using:   idx.using,
            type:    idx.type, # :fulltext | :spatial | nil
            lengths: idx.lengths.presence,
            orders:  idx.orders.presence
          }
        end
      end

      def serialize_foreign_keys(fkeys, from_table)
        fkeys.map do |fk|
          {
            from_table:  from_table,
            to_table:    fk.to_table,
            column:      fk.column,
            primary_key: fk.primary_key,
            on_update:   fk.on_update,
            on_delete:   fk.on_delete,
            name:        fk.name
          }
        end
      end
    end
  end
end
