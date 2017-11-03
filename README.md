# Clone Sierra's DB: Foreign Data Wrapper (FDW) for the Sierra ILS database

Sets up a copy of the ```sierra_view``` views. Once set up all queries
working on Sierra's DB server should work on your local copy too.
No changes to the SQL are needed.

The queries here make a copy of data in some tables. This can help to increase
the speed of the queries if most of the used tables are stored locally.

Another benefit is that queries do not time out because Postgres and the FDW are taking care of that.

## How to

Change credentials in ```init.sql```, then execute ```functions.sql```
and ```init.sql```.

This will

* set up the FDW server
* create a schema ```fdw``` used for functions and helper tables and views
* create a schema ```sierra_view_fdw``` that stores the original FDW views
* create a schema ```sierra_view``` that holds the views / mirrored tables of the views in ```sierra_view_fdw```

## Get (and update) the data

Then the contents of the mirrored tables need to be pulled.
```update.sql``` will take care of that. The first run will take quite a
while because all data inside the tables needs to be moved. Once this is
done the updates are based on the information in the record_metadata
table. So just records that have been changed get updated.

The queries ignore deleted records for now.

## Add and remove tables

You replace a view with a copy by executing i.e.

```sql
SELECT fdw.add_table( 'bib_record', 'id', 'b' );
```

Removing the table and setting up a view by i.e.

```sql
SELECT fdw.add_view( 'bib_record' );
```

## Remove

```teardown.sql``` removes all tables, functions, views etc. that have
been created by the other queries.
