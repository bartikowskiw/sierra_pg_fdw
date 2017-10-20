---
--- PERFORM UPDATE
---

--- Look for new / updated records according to the record_metadata table
INSERT INTO fdw.updates 
	SELECT 
		fdw.get_updates( 'sierra_view_fdw.record_metadata', 'sierra_view.record_metadata', u.record_type_code )	
	FROM fdw.updated_tables AS u 
		WHERE u.active 
		AND u.record_type_code IS NOT NULL 
	GROUP BY record_type_code;

--- Update the rows
SELECT fdw.update_table(
	fdw.ftn( table_name, 'sierra_view_fdw' ),
	fdw.ftn( table_name, 'sierra_view' ),
	'fdw.updates',
	id_field
)  FROM fdw.updated_tables AS u WHERE u.active;

--- Remove the ids from the updates table
DELETE FROM fdw.updates;

