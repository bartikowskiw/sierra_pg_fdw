---
--- PERFORM UPDATE BY record_metadata
---

--- Look for new / updated records according to the record_metadata table
INSERT INTO fdw.updates 
    SELECT 
        fdw.get_updates( 'sierra_view_fdw.record_metadata', 'sierra_view.record_metadata', u.record_type_code ) 
    FROM fdw.updated_tables AS u 
        WHERE u.active 
        AND u.record_type_code IS NOT NULL 
        AND NOT u.by_index 
    GROUP BY record_type_code;

--- Update the rows, using the record_metadata information
SELECT fdw.update_table(
    fdw.ftn( u.table_name, 'sierra_view_fdw' ),
    fdw.ftn( u.table_name, 'sierra_view' ),
    'fdw.updates',
    u.id_field
)  FROM fdw.updated_tables AS u WHERE u.active AND NOT u.by_index;

--- Remove the ids from the updates table
DELETE FROM fdw.updates;

---
--- PERFORM UPDATE BY index
---

--- Update the rows, using the index information
SELECT fdw.update_table_by_index(
    fdw.ftn( u.table_name, 'sierra_view_fdw' ),
    fdw.ftn( u.table_name, 'sierra_view' ),
    u.id_field
)  FROM fdw.updated_tables AS u WHERE u.active AND u.by_index;
