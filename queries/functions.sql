---
--- Init meta schema
---

CREATE SCHEMA IF NOT EXISTS fdw;
GRANT ALL ON SCHEMA fdw TO CURRENT_USER;

---
--- Drop meta schema
---

CREATE OR REPLACE FUNCTION fdw.drop_meta_schema()
RETURNS void AS $$
BEGIN

    DROP SCHEMA fdw CASCADE;

END; $$ LANGUAGE plpgsql;

---
--- Escape table name
---

CREATE OR REPLACE FUNCTION fdw.ftn(
    table_name text,
    schema_name text DEFAULT 'public'
)
RETURNS text AS $$
BEGIN
    RETURN quote_ident( schema_name ) || '.' || quote_ident( table_name );
END; $$ LANGUAGE plpgsql;

---
--- Set up FDW
---

CREATE OR REPLACE FUNCTION fdw.init(
    username text,
    password text,
    host text,
    db_name text DEFAULT 'iii',
    port int DEFAULT 1032,
    server_name text DEFAULT 'sierra_server',
    local_schema_name text DEFAULT 'sierra_view_fdw',
    remote_schema_name text DEFAULT 'sierra_view'
)
RETURNS void AS $$
BEGIN

    CREATE EXTENSION IF NOT EXISTS postgres_fdw;

    RAISE NOTICE 'Setting up "%" Foreign Data Wrapper for %@%:%/%. Local schema name: "%".',
    server_name, username, host, port, db_name, local_schema_name;

    EXECUTE 'CREATE SERVER ' || quote_ident( server_name ) || '
      FOREIGN DATA WRAPPER postgres_fdw
      OPTIONS (
    host ' || quote_literal( host ) || ',
    dbname ' || quote_literal( db_name ) || ',
    port ' || quote_literal( port ) || ')';

    EXECUTE 'CREATE USER MAPPING FOR CURRENT_USER
      SERVER sierra_server
      OPTIONS (
    user ' || quote_literal( username) || ',
    password ' || quote_literal( password ) || '
    )';

    EXECUTE 'CREATE SCHEMA ' || quote_ident( local_schema_name );

    EXECUTE 'GRANT ALL ON SCHEMA ' || quote_ident( local_schema_name ) || ' TO CURRENT_USER';

    EXECUTE 'IMPORT FOREIGN SCHEMA ' || quote_ident( remote_schema_name ) || '
      FROM SERVER ' || quote_ident( server_name ) || '
      INTO ' || quote_ident( local_schema_name );

    EXECUTE 'GRANT ALL ON SCHEMA ' || quote_ident( local_schema_name ) || ' TO CURRENT_USER';

    EXECUTE 'CREATE OR REPLACE VIEW fdw.tables AS
      SELECT
        s.srvname AS server_name,
        split_part( t.ftoptions[1], ''='', 2 ) AS schema_name,
        split_part( t.ftoptions[2], ''='', 2 ) AS table_name

        FROM pg_foreign_server AS s
        JOIN pg_foreign_table AS t ON ( t.ftserver = s.oid )
      WHERE s.srvname = ' || quote_literal( server_name );

END; $$ LANGUAGE plpgsql;

---
--- Tear down FDW (server)
---

CREATE OR REPLACE FUNCTION fdw.drop_server(
    server_name text DEFAULT 'sierra_server'
)
RETURNS void AS $$
BEGIN

    RAISE NOTICE 'Dropping Foreign Data Server "%" and all depended objects.', server_name;

    EXECUTE 'DROP SERVER IF EXISTS ' || quote_ident( server_name ) || ' CASCADE;';

END; $$ LANGUAGE plpgsql;

---
--- Duplicate table structure
---

CREATE OR REPLACE FUNCTION fdw.duplicate_table_structure(
    table_original text,
    table_copy text,
    id_field text DEFAULT 'id'
)
RETURNS void AS $$
BEGIN

    RAISE NOTICE 'Duplicating table structure of "%" to "%".', table_original, table_copy;

    EXECUTE 'DROP VIEW IF EXISTS ' || table_copy;

    EXECUTE 'CREATE TABLE ' || table_copy || ' AS SELECT * FROM ' || table_original || ' LIMIT 0';

    EXECUTE 'ALTER TABLE ' || table_copy || ' ADD PRIMARY KEY( id )';
    EXECUTE 'CREATE INDEX ON ' || table_copy || '( ' || quote_ident( id_field ) || ' )';

END; $$ LANGUAGE plpgsql;

---
--- Create views for all tables / views of a schema
---

CREATE OR REPLACE FUNCTION fdw.create_mirror_view(
    table_from text,
    table_to text
)
RETURNS void AS $$
BEGIN

    RAISE NOTICE 'Create copy of "%" to "%".', table_from, table_to;

    EXECUTE 'CREATE OR REPLACE VIEW ' || table_to || ' AS SELECT * FROM ' || table_from;

END; $$ LANGUAGE plpgsql;

---
--- Create view for all tables in the fdw.tables view
---

CREATE OR REPLACE FUNCTION fdw.mirror_schema(
    schema_from text DEFAULT 'sierra_view_fdw',
    schema_to text DEFAULT 'sierra_view',
    server_name text DEFAULT 'sierra_server',
    schema_original_name text DEFAULT 'sierra_view'
)
RETURNS void AS $$
BEGIN

    RAISE NOTICE 'Create copy of "%" to "%".', schema_from, schema_to;

    EXECUTE 'SELECT
        fdw.create_mirror_view(
            fdw.ftn( table_name,' || quote_literal( schema_from ) || ' ),
            fdw.ftn( table_name, ' || quote_literal( schema_to ) || ' )
        ) FROM fdw.tables
        WHERE
            server_name = ' || quote_literal( server_name ) || '
            AND schema_name = ' || quote_literal( schema_original_name )
    ;

END; $$ LANGUAGE plpgsql;

---
--- Replace a view with a table
---

CREATE OR REPLACE FUNCTION fdw.add_table(
    table_name text, 
    id_field text,
    record_type_code text DEFAULT NULL,
    schema_original text DEFAULT 'sierra_view_fdw',
    schema_copy text DEFAULT 'sierra_view'
)
RETURNS void AS $$
BEGIN

    EXECUTE 'DELETE FROM fdw.updated_tables WHERE table_name = ' || quote_literal( table_name );

    IF record_type_code IS NULL THEN
    EXECUTE 'INSERT INTO fdw.updated_tables ( table_name, id_field ) 
        VALUES ( ' || quote_literal( table_name ) || ', ' || quote_literal( id_field ) || ' )';
    ELSE
        EXECUTE 'INSERT INTO fdw.updated_tables ( table_name, id_field, record_type_code ) 
        VALUES ( ' || quote_literal( table_name ) || ', ' || quote_literal( id_field ) || ', ' || quote_literal( record_type_code ) || ' )';
    END IF;

    

    EXECUTE 'SELECT fdw.duplicate_table_structure(
    ' || quote_literal( fdw.ftn( table_name, schema_original ) ) || ',
    ' || quote_literal( fdw.ftn( table_name, schema_copy ) ) || ',
    ' || quote_literal( id_field ) || '
    )';

END; $$ LANGUAGE plpgsql;

---
--- Replace table with a view
---

CREATE OR REPLACE FUNCTION fdw.add_view(
    table_name text, 
    schema_from text DEFAULT 'sierra_view_fdw',
    schema_to text DEFAULT 'sierra_view'
)
RETURNS void AS $$
BEGIN

    EXECUTE 'DROP TABLE IF EXISTS ' || fdw.ftn( table_name, schema_to );
    
    PERFORM fdw.create_mirror_view(
    fdw.ftn( table_name, schema_from ),
        fdw.ftn( table_name, schema_to )
    );

END; $$ LANGUAGE plpgsql;

---
--- Get ids of records to update.
---
--- @returns a table of ids
---

CREATE OR REPLACE FUNCTION fdw.get_updates(
    table_original text DEFAULT 'sierra_view_fdw.record_metadata',
    table_copy text DEFAULT 'sierra_view.record_metadata',
    record_type_code char DEFAULT NULL,
    record_limit int DEFAULT NULL
)
RETURNS TABLE( id bigint ) AS $$
DECLARE
    sql text;
    max_date date DEFAULT NULL;
BEGIN

    RAISE NOTICE 'Getting record ids for records to update from % to %.', table_original, table_copy;

    EXECUTE 'SELECT MAX( record_last_updated_gmt ) FROM ' || table_copy INTO max_date;
    IF max_date IS NULL THEN max_date := DATE '1969-07-21'; END IF;
    RAISE NOTICE '  Max date: %', max_date;

    sql := 'SELECT md.id FROM ' || table_original || ' AS md
        WHERE ( md.creation_date_gmt > ' || quote_literal( max_date ) || '
        OR md.record_last_updated_gmt > ' || quote_literal( max_date ) || ' )';

    IF record_type_code IS NOT NULL THEN
        sql := sql || ' AND record_type_code = ' || quote_literal( record_type_code );
        RAISE NOTICE '  Record type restricted to %.', record_type_code;
    END IF;

    IF record_limit IS NOT NULL THEN
        sql := sql || ' LIMIT ' || record_limit;
        RAISE NOTICE '  Limited to % records.', record_limit;
    END IF;

    RETURN QUERY EXECUTE sql;

END; $$ LANGUAGE plpgsql;

---
--- Update the table records
---

CREATE OR REPLACE FUNCTION fdw.update_table(
    table_original text,
    table_copy text,
    table_updates text DEFAULT 'fdw.updates',
    id_field text DEFAULT 'id'
)
RETURNS void AS $$
BEGIN

    RAISE NOTICE 'Coping updated records from "%" to "%".', table_original, table_copy;

    EXECUTE
      'DELETE
        FROM ' || table_copy || ' AS r
        WHERE r.' || quote_ident( id_field ) || ' = ANY ( ARRAY( SELECT id FROM ' || table_updates || ' ) )';

    EXECUTE
      'INSERT INTO ' || table_copy || '
        SELECT * FROM ' || table_original || ' AS r
        WHERE r.' || quote_ident( id_field ) || ' = ANY ( ARRAY( SELECT id FROM ' || table_updates || ' ) )';

END; $$ LANGUAGE plpgsql;

---
--- Update table by id
---
--- Uses just the (auto increment) id as criterion for updates
--- Does not delete removed rows
---

CREATE OR REPLACE FUNCTION fdw.update_tables_by_index(
    table_original text,
    table_copy text,
    id_field text DEFAULT 'id',
    record_limit int DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    sql text;
    max_id integer DEFAULT 0;
    affected integer DEFAULT 0;
BEGIN

    RAISE NOTICE 'Updating % with data from %.', table_original, table_copy;

    EXECUTE 'SELECT MAX( ' || quote_ident( id_field ) || ' ) FROM ' || table_copy INTO max_id;
    IF max_id IS NULL THEN max_id := 0; END IF;
    RAISE NOTICE '  Max id: %', max_id;

    sql := '
    INSERT INTO ' || table_copy || '
        SELECT * FROM ' || table_original || ' AS t
        WHERE ( t.' || quote_ident( id_field ) ||  ' > ' || quote_literal( max_id ) || ')';

    IF record_limit IS NOT NULL THEN
        sql := sql || ' LIMIT ' || record_limit;
        RAISE NOTICE '  Limited to % records.', record_limit;
    END IF;

    EXECUTE sql;
    
    GET DIAGNOSTICS affected = ROW_COUNT;
    RAISE NOTICE '  Added % row(s).', affected;

END; $$ LANGUAGE plpgsql;
