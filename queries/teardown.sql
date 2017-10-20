---
--- Remove server, tear down tables
---

SELECT fdw.drop_server();
SELECT fdw.drop_meta_schema();
DROP SCHEMA sierra_view CASCADE;
DROP SCHEMA sierra_view_fdw CASCADE;
