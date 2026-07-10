# frozen_string_literal: true

module SchemaFerry
  module Support
    class SchemafileRenderer
      Call = Struct.new(:name, :args, :opts, :children)
      Raw = Struct.new(:source)

      def render(tables)
        calls = tables.map { |table| table_call(table) }
        calls += tables.flat_map { |table| table.foreign_keys.map { |fk| foreign_key_call(fk) } }
        calls.map { |call| serialize(call) }.join("\n\n")
      end

      private

      def table_call(table)
        children = table.columns.map { |col| column_call(col) }
        children += table.indexes.map { |idx| index_call(idx) }
        children += Array(table.check_constraints).map { |chk| check_constraint_call(chk) }
        Call.new("create_table", [table.name], table_options(table), children)
      end

      def table_options(table)
        opts = { force: :cascade }
        case table.primary_key
        when nil
          opts[:id] = false
        when String
          opts[:primary_key] = table.primary_key if table.primary_key != "id"
          if table.pk_type && table.pk_type != :bigint
            opts[:id]    = table.pk_type
            opts[:limit] = table.pk_limit
          end
        when Array
          opts[:primary_key] = table.primary_key
        end
        opts[:comment] = table.comment
        opts
      end

      def column_call(col)
        Call.new("t.#{col.type}", [col.name], {
                   limit:     col.limit,
                   precision: col.precision,
                   scale:     col.scale,
                   default:   default_option(col),
                   null:      (false if col.null == false),
                   comment:   col.comment
                 })
      end

      def default_option(col)
        return col.default unless col.default.nil?

        Raw.new("-> { #{col.default_function.inspect} }") if col.default_function
      end

      def index_call(idx)
        Call.new("t.index", [idx.columns], {
                   name:   idx.name,
                   unique: (true if idx.unique),
                   using:  idx.using,
                   order:  idx.orders
                 })
      end

      def check_constraint_call(chk)
        Call.new("t.check_constraint", [chk.expression], { name: chk.name })
      end

      def foreign_key_call(foreign_key)
        Call.new("add_foreign_key", [foreign_key.from_table, foreign_key.to_table], {
                   column:      (foreign_key.column if custom_fk_column?(foreign_key)),
                   primary_key: (foreign_key.primary_key if foreign_key.primary_key && foreign_key.primary_key != "id"),
                   name:        foreign_key.name,
                   on_update:   foreign_key.on_update,
                   on_delete:   foreign_key.on_delete
                 })
      end

      # ridgepole's PostgreSQL export omits column: when it follows the Rails
      # convention, and it compares foreign keys by their literal options —
      # emitting column: for conventional names re-creates the FK every run.
      def custom_fk_column?(foreign_key)
        foreign_key.column && foreign_key.column != "#{foreign_key.to_table.singularize}_id"
      end

      def serialize(call, indent = "")
        head = "#{indent}#{[call.name, arguments(call)].reject(&:empty?).join(" ")}"
        return head unless call.children

        ["#{head} do |t|",
         *call.children.map { |child| serialize(child, "#{indent}  ") },
         "#{indent}end"].join("\n")
      end

      def arguments(call)
        positional = call.args.map { |arg| literal(arg) }
        keyword    = call.opts.filter_map { |key, value| "#{key}: #{literal(value)}" unless value.nil? }
        (positional + keyword).join(", ")
      end

      def literal(value)
        value.is_a?(Raw) ? value.source : value.inspect
      end
    end
  end
end
