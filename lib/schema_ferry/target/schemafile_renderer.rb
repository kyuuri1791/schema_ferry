# frozen_string_literal: true

module SchemaFerry
  module Target
    class SchemafileRenderer
      TIMESTAMP_COLS = %w[created_at updated_at].freeze

      def render(tables)
        table_blocks = tables.map { |t| render_table(t) }
        fkey_lines   = tables.flat_map { |t| t.foreign_keys.map { |fk| render_foreign_key(fk) } }

        parts = table_blocks
        parts += fkey_lines unless fkey_lines.empty?
        parts.join("\n\n")
      end

      private

      def render_table(table)
        lines = []
        lines << "create_table #{table.name.inspect}#{pk_options(table)} do |t|"
        lines.concat(render_columns(table.columns))
        table.indexes.each { |idx| lines << render_index(idx) }
        Array(table.check_constraints).each { |chk| lines << render_check_constraint(chk) }
        lines << "end"
        lines.join("\n")
      end

      def pk_options(table)
        opts = []
        case table.primary_key
        when nil
          opts << "id: false"
        when String
          opts << "primary_key: #{table.primary_key.inspect}" if table.primary_key != "id"
          if table.pk_type && table.pk_type != :bigint
            opts << "id: #{table.pk_type.inspect}"
            opts << "limit: #{table.pk_limit.inspect}" if table.pk_limit
          end
        when Array
          opts << "primary_key: #{table.primary_key.inspect}"
        end
        opts.unshift("force: :cascade")
        opts << "comment: #{table.comment.inspect}" if table.comment
        ", #{opts.join(", ")}"
      end

      def render_columns(columns)
        ts_created  = columns.find { |c| c.name == "created_at" }
        ts_updated  = columns.find { |c| c.name == "updated_at" }
        use_timestamps = collapsible_timestamps?(ts_created, ts_updated)

        lines      = []
        emitted_ts = false

        columns.each do |col|
          if TIMESTAMP_COLS.include?(col.name) && use_timestamps
            unless emitted_ts
              lines << render_timestamps(ts_created)
              emitted_ts = true
            end
            next
          end
          lines << render_column(col)
        end

        lines
      end

      def collapsible_timestamps?(created_at, updated_at)
        return false unless created_at && updated_at
        return false unless created_at.type == :datetime && updated_at.type == :datetime

        created_at.null == updated_at.null &&
          created_at.precision == updated_at.precision &&
          created_at.default.nil? && updated_at.default.nil? &&
          created_at.default_function.nil? && updated_at.default_function.nil?
      end

      def render_timestamps(col)
        opts = []
        opts << "null: false" if col.null == false
        opts << "precision: #{col.precision}" if col.precision
        opts.empty? ? "  t.timestamps" : "  t.timestamps #{opts.join(", ")}"
      end

      def render_column(col)
        parts = [col.name.inspect]
        opts  = column_options(col)
        parts << opts unless opts.empty?
        "  t.#{col.type} #{parts.join(", ")}"
      end

      def column_options(col)
        pairs = []
        pairs << "limit: #{col.limit.inspect}"         if col.limit
        pairs << "precision: #{col.precision.inspect}" if col.precision
        pairs << "scale: #{col.scale.inspect}"         if col.scale
        pairs << render_default(col)                   if render_default(col)
        pairs << "null: false"                         if col.null == false
        pairs << "comment: #{col.comment.inspect}"     if col.comment
        pairs.join(", ")
      end

      def render_default(col)
        return "default: #{col.default.inspect}" unless col.default.nil?

        "default: -> { #{col.default_function.inspect} }" if col.default_function
      end

      def render_index(idx)
        cols  = idx.columns.inspect
        parts = ["name: #{idx.name.inspect}"]
        parts << "unique: true" if idx.unique
        parts << "using: #{idx.using.inspect}" if idx.using
        parts << "opclass: #{idx.opclass.inspect}" if idx.opclass
        parts << "where: #{idx.where.inspect}" if idx.where
        parts << "order: #{idx.orders.inspect}" if idx.orders
        "  t.index #{cols}, #{parts.join(", ")}"
      end

      def render_check_constraint(chk)
        "  t.check_constraint #{chk.expression.inspect}, name: #{chk.name.inspect}"
      end

      def render_foreign_key(foreign_key)
        parts = [foreign_key.from_table.inspect, foreign_key.to_table.inspect]
        parts << "column: #{foreign_key.column.inspect}" if custom_fk_column?(foreign_key)
        non_default_pk = foreign_key.primary_key && foreign_key.primary_key != "id"
        parts << "primary_key: #{foreign_key.primary_key.inspect}" if non_default_pk
        parts << "name: #{foreign_key.name.inspect}"               if foreign_key.name
        parts << "on_update: #{foreign_key.on_update.inspect}"     if foreign_key.on_update
        parts << "on_delete: #{foreign_key.on_delete.inspect}"     if foreign_key.on_delete
        "add_foreign_key #{parts.join(", ")}"
      end

      # ridgepole's PostgreSQL export omits column: when it follows the Rails
      # convention, and it compares foreign keys by their literal options —
      # emitting column: for conventional names re-creates the FK every run.
      def custom_fk_column?(foreign_key)
        foreign_key.column && foreign_key.column != "#{foreign_key.to_table.singularize}_id"
      end
    end
  end
end
