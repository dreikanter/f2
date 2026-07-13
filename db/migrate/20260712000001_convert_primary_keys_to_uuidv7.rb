class ConvertPrimaryKeysToUuidv7 < ActiveRecord::Migration[8.2]
  # Gem-owned Solid tables (Queue/Cache/Cable) stay bigint.
  SKIP_PREFIXES = %w[solid_queue_ solid_cache_ solid_cable_ ar_internal schema_].freeze

  # Tables already on uuid PKs (created with gen_random_uuid, i.e. v4). Their
  # keys stay; only the default moves to the time-ordered generator.
  ALREADY_UUID = %w[feed_previews invites].freeze

  # Polymorphic id columns can't be resolved from a foreign key, so their
  # target table is chosen per row from the sibling type column.
  POLYMORPHIC = { "events" => %w[subject], "event_references" => %w[reference] }.freeze

  # Columns that reference another table by convention but carry no database
  # foreign key, so foreign_keys introspection never surfaces them.
  UNCONSTRAINED_REFERENCES = {
    "feed_previews" => { "ai_credential_id" => "ai_credentials" },
    "event_references" => { "event_id" => "events" }
  }.freeze

  def up
    convert!(
      to: "uuid",
      map_type: "uuid",
      new_id_sql: "uuidv7()",
      pk_default: "uuidv7()"
    )

    ALREADY_UUID.each { |table| set_id_default(table, "uuidv7()") }
  end

  def down
    ALREADY_UUID.each { |table| set_id_default(table, "gen_random_uuid()") }

    # Regenerate sequential bigints in creation order (uuidv7 sorts by
    # creation time, so row_number reproduces the original ordering) and
    # restore an owned sequence so inserts auto-increment again.
    convert!(
      to: "bigint",
      map_type: "bigint",
      new_id_sql: "row_number() OVER (ORDER BY id)",
      pk_default: nil
    )
  end

  private

  # Reversible core: rewrites every convertible PK and referencing column from
  # one id type to the other while preserving rows, relationships, and indexes.
  def convert!(to:, map_type:, new_id_sql:, pk_default:)
    pk_tables = pk_convertible_tables
    # Every app table's foreign keys must be dropped before any referenced PK
    # changes type and re-added after — including the already-uuid tables,
    # whose fk columns still point at the tables being converted.
    fks = application_tables.flat_map { |table| foreign_keys(table).map { |fk| [table, fk] } }

    build_id_map(pk_tables, map_type, new_id_sql)

    fks.each { |(table, fk)| remove_foreign_key(table, name: fk.name) }

    pk_tables.each { |table| convert_primary_key(table, to, pk_default) }
    fks.each { |(table, fk)| convert_reference(table, fk.column, fk.to_table, to) }
    UNCONSTRAINED_REFERENCES.each do |table, columns|
      columns.each { |column, target| convert_reference(table, column, target, to) }
    end
    convert_polymorphic_columns(to)

    fks.each { |(table, fk)| add_foreign_key(table, fk.to_table, **foreign_key_options(fk)) }

    execute("DROP TABLE #{quote_table_name(map_table)}")
  end

  def application_tables
    connection.tables.reject { |table| SKIP_PREFIXES.any? { |prefix| table.start_with?(prefix) } }
  end

  # App tables whose PK is retyped: all except the already-uuid ones.
  def pk_convertible_tables
    application_tables - ALREADY_UUID
  end

  def build_id_map(tables, map_type, new_id_sql)
    execute(<<~SQL)
      CREATE TABLE #{quote_table_name(map_table)} (
        table_name text NOT NULL,
        model_name text NOT NULL,
        old_id #{old_id_type} NOT NULL,
        new_id #{map_type} NOT NULL,
        PRIMARY KEY (table_name, old_id)
      )
    SQL

    tables.each do |table|
      execute(<<~SQL)
        INSERT INTO #{quote_table_name(map_table)} (table_name, model_name, old_id, new_id)
        SELECT #{quote(table)}, #{quote(table.classify)}, id, #{new_id_sql}
        FROM #{quote_table_name(table)}
      SQL
    end
  end

  def convert_primary_key(table, to, pk_default)
    sequence = select_value("SELECT pg_get_serial_sequence(#{quote(table)}, 'id')")
    execute("ALTER TABLE #{quote_table_name(table)} ALTER COLUMN id DROP DEFAULT")
    rewrite_column(table, "id", to, "m.table_name = #{quote(table)} AND m.old_id = #{qualified(table, 'id')}")
    execute("DROP SEQUENCE IF EXISTS #{sequence}") if sequence

    if pk_default
      execute("ALTER TABLE #{quote_table_name(table)} ALTER COLUMN id SET DEFAULT #{pk_default}")
    else
      restore_sequence(table)
    end
  end

  def convert_reference(table, column, target_table, to)
    join = "m.table_name = #{quote(target_table)} AND m.old_id = #{qualified(table, column)}"
    rewrite_column(table, column, to, join)
  end

  def convert_polymorphic_columns(to)
    POLYMORPHIC.each do |table, names|
      names.each do |name|
        join = "m.model_name = #{qualified(table, "#{name}_type")} AND m.old_id = #{qualified(table, "#{name}_id")}"
        rewrite_column(table, "#{name}_id", to, join)
      end
    end
  end

  # Retype a column via a temporary sibling: fill it from the id map (a plain
  # UPDATE join, since ALTER ... USING forbids subqueries), then swap types.
  # A nullable column keeps the NULL for unmatched rows; a NOT NULL one can't,
  # so its dangling rows are pruned first (see prune_dangling_rows).
  def rewrite_column(table, column, to, join)
    quoted = quote_table_name(table)
    scratch = "uuidv7_migration_#{column}"

    execute("ALTER TABLE #{quoted} ADD COLUMN #{scratch} #{to}")
    execute("UPDATE #{quoted} SET #{scratch} = m.new_id FROM #{quote_table_name(map_table)} m WHERE #{join}")
    prune_dangling_rows(table, column, scratch)
    execute("ALTER TABLE #{quoted} ALTER COLUMN #{column} TYPE #{to} USING #{scratch}")
    execute("ALTER TABLE #{quoted} DROP COLUMN #{scratch}")
  end

  # Polymorphic and unconstrained references have no foreign key, so a row can
  # outlive its target (e.g. an event_reference to a since-deleted post). Such a
  # row has no id to remap to and can't take NULL in a NOT NULL column, so drop
  # it. PKs and enforced FKs always resolve, so nothing is pruned for them.
  def prune_dangling_rows(table, column, scratch)
    return if column_nullable?(table, column)

    execute("DELETE FROM #{quote_table_name(table)} WHERE #{scratch} IS NULL")
  end

  def column_nullable?(table, column)
    select_value(<<~SQL) == "YES"
      SELECT is_nullable FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND table_name = #{quote(table)}
        AND column_name = #{quote(column)}
    SQL
  end

  def restore_sequence(table)
    quoted = quote_table_name(table)
    sequence = "#{table}_id_seq"
    execute("CREATE SEQUENCE #{sequence} OWNED BY #{quoted}.id")
    execute("SELECT setval(#{quote(sequence)}, GREATEST(COALESCE((SELECT MAX(id) FROM #{quoted}), 0), 1))")
    execute("ALTER TABLE #{quoted} ALTER COLUMN id SET DEFAULT nextval(#{quote(sequence)}::regclass)")
  end

  def foreign_key_options(fk)
    options = { column: fk.column, primary_key: fk.primary_key, name: fk.name }
    options[:on_delete] = fk.on_delete if fk.on_delete
    options
  end

  def set_id_default(table, expression)
    execute("ALTER TABLE #{quote_table_name(table)} ALTER COLUMN id SET DEFAULT #{expression}")
  end

  def qualified(table, column)
    "#{quote_table_name(table)}.#{column}"
  end

  def old_id_type
    # Both directions map from the type we're leaving; the "from" PK is bigint
    # on up and uuid on down. Read it off an arbitrary convertible table.
    connection.columns(pk_convertible_tables.first).find { |c| c.name == "id" }.sql_type
  end

  def map_table
    "pk_id_map"
  end
end
