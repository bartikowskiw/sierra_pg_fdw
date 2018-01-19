---
--- INIT FDW SERVER
---

SELECT fdw.init( :'username', :'password', :'server' );

---
--- CREATE UPDATE META TABLES
---

CREATE TABLE IF NOT EXISTS fdw.updated_tables (
  id serial PRIMARY KEY,
  table_name character varying(128),
  id_field character varying(128) DEFAULT 'id',
  record_type_code char DEFAULT NULL,
  by_index bool DEFAULT FALSE,
  active bool DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS fdw.updates ( id bigint UNIQUE );

---
--- CREATE VIEWS FOR DUPLICATION
---

CREATE SCHEMA sierra_view;
GRANT ALL ON SCHEMA sierra_view TO CURRENT_USER;

SELECT fdw.mirror_schema();

---
--- DEFINE WHICH TABLES TO COPY
---

/*

SELECT fdw.add_table( 'bib_record', 'id', 'b' );
SELECT fdw.add_table( 'bib_record_location', 'bib_record_id', 'b' );
SELECT fdw.add_table( 'bib_record_property', 'bib_record_id', 'b' );
SELECT fdw.add_table( 'bib_record_holding_record_link', 'bib_record_id', 'b' );
SELECT fdw.add_table( 'bib_record_item_record_link', 'bib_record_id', 'b' );
SELECT fdw.add_table( 'bib_record_order_record_link', 'bib_record_id', 'b' );
SELECT fdw.add_table( 'bib_record_volume_record_link', 'bib_record_id', 'b' );

SELECT fdw.add_table( 'item_record', 'id', 'i' );
SELECT fdw.add_table( 'item_record_property', 'item_record_id', 'i' );

SELECT fdw.add_table( 'varfield', 'record_id' );
SELECT fdw.add_table( 'record_metadata', 'id' );

SELECT fdw.add_table( 'circ_trans', 'id', NULL, TRUE );

*/

