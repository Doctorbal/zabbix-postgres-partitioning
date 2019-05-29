# [Zabbix PostgreSQL version 11 Native Partitioning](#zabbix-postgresql-native-partitioning)

Table of Contents
=================

   * [<a href="#zabbix-postgresql-native-partitioning">Zabbix PostgreSQL version 11 Native Partitioning</a>](#zabbix-postgresql-version-11-native-partitioning)
   * [Table of Contents](#table-of-contents)
      * [<a href="#requirements">Requirements</a>](#requirements)
      * [<a href="#zabbix-history-and-trends-tables">Zabbix History* and Trends* Tables</a>](#zabbix-history-and-trends-tables)
         * [<a href="#history--trends">history &amp; trends</a>](#history--trends)
      * [<a href="#zabbix-partitioning-considerations">Zabbix Partitioning Considerations</a>](#zabbix-partitioning-considerations)
      * [<a href="#time-series-partitioning">Time Series Partitioning</a>](#time-series-partitioning)
         * [<a href="#postgresql-default-partition">PostgreSQL Default Partition</a>](#postgresql-default-partition)
         * [<a href="#optional--brin-versus-btree-indexes">Optional - BRIN versus Btree INDEXES</a>](#optional---brin-versus-btree-indexes)
      * [<a href="#prepare-postgresql-database">Prepare PostgreSQL Database</a>](#prepare-postgresql-database)
         * [<a href="#install-postgresql">Install PostgreSQL v11</a>](#install-postgresql-v11)
         * [<a href="#prepare-zabbix-database">Prepare Zabbix Database</a>](#prepare-zabbix-database)
         * [<a href="#create-table">Create Empty history* and trends* Tables</a>](#create-empty-history-and-trends-tables)
      * [<a href="#postgresql-partition-manager-extension-pgpartman">PostgreSQL Partition Manager Extension (pg_partman)</a>](#postgresql-partition-manager-extension-pg_partman)
         * [<a href="#installing-pgpartman">Installing pg_partman</a>](#installing-pg_partman)
         * [<a href="#postgresqlconf">postgresql.conf</a>](#postgresqlconf)
         * [<a href="#create-partitioned-tables">Create Partitioned Tables</a>](#create-partitioned-tables)
         * [<a href="#deleting-designated-partitions">Deleting Designated Partitions</a>](#deleting-designated-partitions)
         * [<a href="#partition-maintenance-creating-future-partitions">Partition Maintenance: Creating Future Partitions</a>](#partition-maintenance-creating-future-partitions)
         * [<a href="#partition-maintenance-droppingexpiring-old-partitions">Partition Maintenance: Dropping/expiring old partitions</a>](#partition-maintenance-droppingexpiring-old-partitions)
      * [<a href="#change-zabbix-history-tables-from-monthly-to-daily-with-pgpartman">Change Zabbix history tables from monthly to daily with pg_partman</a>](#change-zabbix-history-tables-from-monthly-to-daily-with-pgpartman)
      * [<a href="#zabbix-remote-data-dump">Zabbix Remote Data Dump</a>](#zabbix-remote-data-dump)
         * [<a href="#pgdumppgrestore-manual-mechanism">pgdump/pgrestore Manual Mechanism</a>](#pgdumppgrestore-manual-mechanism)
      * [<a href="#upgrade-zabbix-v34-to-v42-while-moving-from-postgresql-v96-to-postgresql-v11">Upgrade Zabbix v3.4 to v4.2 while moving from PostgreSQL v9.6 to PostgreSQL v11</a>](#upgrade-zabbix-v34-to-v42-while-moving-from-postgresql-v96-to-postgresql-v11)
         * [<a href="#migrate-the-configuration-data">Migrate the Configuration Data</a>](#migrate-the-configuration-data)
         * [<a href="#migrate-the-old-history-and-trends-data">Migrate the old history* and trends* data</a>](#migrate-the-old-history-and-trends-data)
      * [<a href="#benchmarking">Performance Testing</a>](#performance-testing)
         * [<a href="#pgbench">pgbench</a>](#pgbench)
         * [<a href="#explain-analyze">EXPLAIN ANALYZE</a>](#explain-analyze)
         * [<a href="#zabbix-database-performance-results">Zabbix Databases Performance Results</a>](#zabbix-databases-performance-results)
      * [<a href="#partitioning-advantages-mistakes-and-problems">Partitioning Advantages, Mistakes and Problems</a>](#partitioning-advantages-mistakes-and-problems)
         * [<a href="#partitioning-advantages">Partitioning Advantages</a>](#partitioning-advantages)
         * [<a href="#common-partitioning-mistakes">Common Partitioning Mistakes</a>](#common-partitioning-mistakes)
      * [<a href="#ansible-role">Ansible Role</a>](#ansible-role)
      * [<a href="#references">References</a>](#references)

---

## [Requirements](#requirements)

* Debian 8 Jessie or Debian 9 Stretch OS Distro
* PostgreSQL version 11
* Zabbix version 3.4 or 4.0 (tested successfully on both)

---

## [Zabbix History* and Trends* Tables](#zabbix-history-and-trends-tables)

* history - `history`, `history_uint`, `history_str`, `history_text`, `history_log`
* trends - `trends`, `trends_uint`

### [history &amp; trends](#history--trends)

* `history` - table that stores all numeric (float) values
* `history_uint` - table that stores all integer values
* `history_log` - table that stores all log values
* `history_text` - table that store all text values
* `history_str` - table that stores all string values
* `trends` - table that stores all numeric (float) values
* `trends_uint` - table that stores all numeric (unsigned integers)

History and trends are the two ways of storing collected data in Zabbix.

Whereas history keeps each collected value, trends keep averaged information on hourly basis and therefore are less resource-hungry.

The general strong advice is to keep history for the smallest possible number of days and that way not to overload the database with lots of historical values.

Instead of keeping a long history, you can keep longer data of trends. For example, you could keep history for 14 days and trends for 5 years.

While keeping shorter history, you will still be able to review older data in graphs, as graphs will use trend values for displaying older data.

Trends is a built-in historical data reduction mechanism which stores minimum, maximum, average and the total number of values per every hour for numeric data types.

Trends usually can be kept for much longer than history. Any older data will be removed by the housekeeper.

When server flushes trend cache and there are already trends in the database for this hour (for example, server has been restarted mid-hour), server needs to use update statements instead of simple inserts. Therefore on a bigger installation if restart is needed it is desirable to stop server in the end of one hour and start in the beginning of the next hour to avoid trend data overlap.

Zabbix updates trends immediately after receipt of new value. Therefore, all information stored in trends is always valid and up-to-date (updated in realtime).

Zabbix generates all graphs from detailed history if period is less than 24 hours, and the trends are used for graphs having period longer than 24 hours.

---

## [Zabbix Partitioning Considerations](#zabbix-partitioning-considerations)

Before performing partitioning in Zabbix, several aspects must be considered:

1. Time partitioning will be used for table partitioning.
2. Housekeeper will not be needed for some data types anymore. This Zabbix functionality for clearing old history and trend data from the database can be controlled in **Administration | General Housekeeper**.
3. The values of History storage period (in days) and Trend storage period (in days) fields in item configuration will not be used anymore as old data will be cleared by the range i.e. the whole partition. They can (and should be) overridden in **Administration | General Housekeeper** - the period should match the period for which we are expecting to keep the
partitions which is **monthly**
4. Even with the housekeeping for items disabled, Zabbix server and web interface will keep
writing housekeeping information for future use into the housekeeper table. To avoid this,
you can add trigger for this table **after you add the data there**:

```
CREATE TRIGGER housekeeper_blackhole
    BEFORE INSERT ON housekeeper
    FOR EACH ROW
    EXECUTE PROCEDURE housekeeper_blackhole();
```

With the following procedure:

```
CREATE OR REPLACE FUNCTION housekeeper_blackhole()
    RETURNS trigger AS
$func$
BEGIN
    RETURN NULL;
END
$func$ LANGUAGE plpgsql;
```

---

## [Time Series Partitioning](#time-series-partitioning)

Partitioning syntax was introduced in PostgreSQL 10. It is very effective for INSERTs and large/slow `SELECT` queries, which makes it suitable for time series logging.

### [PostgreSQL Default Partition](#postgresql-default-partition)

With PostgreSQL version 11 it is possible to create a "default" partition. This stores rows that do not fall into any existing partition's range. This is ideal since the partitioned range might not include specific data which the default will then pick up. This is automatically done with `pg_partman`. From there one can delete all data from the table via the following example:

```
DELETE FROM public.history_p2018_11
```

### [Optional - BRIN versus Btree INDEXES](#optional--brin-versus-btree-indexes)

With PostgreSQL 9.5 a new type of index, [BRIN (Block Range INdex)](https://www.postgresql.org/docs/9.5/brin-intro.html) was introduced. These indexes work best when the data on disk is sorted. Brin only stores min/max values for a range of blocks on disk, which allows them to be small, but which raises the cost for any lookup against the index. Each lookup that hits the index must read a range of pages from disk, so each hit becomes more expensive.

Huge tables benefit from the BRIN index. Adding a BRIN index is fast and very easy and works well for the use case of time series data logging, though less well under intensive update. An INSERTs into BRIN indexes are specifically designed to **not** slow down as the table get bigger, so they perform much better than btree indexes.

In PostgreSQL v11, partitioning offers automatic index creation. You simply create an index on the parent table, and Postgres will automatically create indexes on all child tables. This thus makes partition maintenance much easier!

---

## [Prepare PostgreSQL Database](#prepare-postgresql-database)

1. Download and install the [PostgreSQL Core Distribution](https://www.postgresql.org/download/) that supports Native Partitioning. As of this writing it is PostgreSQL v11.1.
2. Tune `postgresql.conf` to ensure `enable_partition_pruning = on`. The default should be `on`. This enables or disables the query planner's ability to eliminate a partitioned table's partitions from query plans, thus improving performance.
3. Copy the `pg_hba.conf` from the old database to the new database and tune the database appropriately. You can use the following tools:
* [pgtune](https://pgtune.leopard.in.ua/#/)
* [postgresqltuner](https://github.com/jfcoz/postgresqltuner).
4. Turn of Zabbix Housekeeper in the Frontend as mentioned in the [Zabbix Partitioning Considerations](#zabbix-partitioning-considerations).
5. Shut down (or stop) the Zabbix Server and Zabbix Frontend from writing to the database.
6. Back up the original database!!!

### [Install PostgreSQL v11](#install-postgresql)

```
wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | sudo apt-key add -
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" >> /etc/apt/sources.list.d/pgdg.list'
sudo apt update
sudo apt install postgresql-11
sudo passwd postgres
sudo su - postgres
ssh-keygen # passwordless
```

### [Prepare Zabbix Database](#prepare-zabbix-database)

```
sudo -i -u postgres
postgres@zbxdatabase:~$ createuser -P -s -e zabbix
postgres@zbxdatabase:~$ psql
postgres=# create database zabbix;
postgres=# GRANT ALL PRIVILEGES ON DATABASE zabbix to zabbix;
postgres=# \q
```

### [Create Empty history* and trends* Tables](#create-table)

On an empty database (you can create multiple database on the same server if you'd like or want to upgrade from version 9.x to 10/11) create the following tables for `history*` and `trends*`.

```
sudo -su postgres psql -d zabbix
```

Then run the following commands

```
-- history
CREATE TABLE public.history
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    value numeric(16,4) NOT NULL DEFAULT 0.0000,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_1 ON public.history USING btree (itemid, clock);

-- history_log
CREATE TABLE public.history_log
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    "timestamp" integer NOT NULL DEFAULT 0,
    source character varying(64) COLLATE pg_catalog."default" NOT NULL DEFAULT ''::character varying,
    severity integer NOT NULL DEFAULT 0,
    value text COLLATE pg_catalog."default" NOT NULL DEFAULT ''::text,
    logeventid integer NOT NULL DEFAULT 0,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_log_1 ON public.history_log USING btree (itemid, clock);

-- history_str
CREATE TABLE public.history_str
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    value character varying(255) COLLATE pg_catalog."default" NOT NULL DEFAULT ''::character varying,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_str_1 ON public.history_str USING btree (itemid, clock);

-- history_text
CREATE TABLE public.history_text
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    value text COLLATE pg_catalog."default" NOT NULL DEFAULT ''::text,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_text_1 ON public.history_text USING btree (itemid, clock);

-- history_uint
CREATE TABLE public.history_uint
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    value numeric(20,0) NOT NULL DEFAULT (0)::numeric,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_uint_1 ON public.history_uint USING btree (itemid, clock);

-- trends
CREATE TABLE public.trends
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    num integer NOT NULL DEFAULT 0,
    value_min numeric(16,4) NOT NULL DEFAULT 0.0000,
    value_avg numeric(16,4) NOT NULL DEFAULT 0.0000,
    value_max numeric(16,4) NOT NULL DEFAULT 0.0000,
    CONSTRAINT trends_pkey PRIMARY KEY (itemid, clock)
) PARTITION BY RANGE (clock);

-- trends_uint
CREATE TABLE public.trends_uint
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    num integer NOT NULL DEFAULT 0,
    value_min numeric(20,0) NOT NULL DEFAULT (0)::numeric,
    value_avg numeric(20,0) NOT NULL DEFAULT (0)::numeric,
    value_max numeric(20,0) NOT NULL DEFAULT (0)::numeric,
    CONSTRAINT trends_uint_pkey PRIMARY KEY (itemid, clock)
) PARTITION BY RANGE (clock);
```

---

Optionally depending on the role you used run

```
ALTER TABLE public.history OWNER TO zabbix;
ALTER TABLE public.history_log OWNER TO zabbix;
ALTER TABLE public.history_str OWNER TO zabbix;
ALTER TABLE public.history_text OWNER TO zabbix;
ALTER TABLE public.history_uint OWNER TO zabbix;
ALTER TABLE public.trends OWNER TO zabbix;
ALTER TABLE public.trends_uint OWNER TO zabbix;
```

## [PostgreSQL Partition Manager Extension (pg_partman)](#postgresql-partition-manager-extension-pgpartman)

pg_partman is an extensions to create and manage both time-based and serial-based table partition sets. Native partitioning in PostgreSQL 10 is supported as of pg_partman v3.0.1 and PostgreSQL 11 as of pg_partman v4.0.0.

pg_partman works as an extension and it can be installed directly on top of PostgreSQL.

### [Installing pg_partman](#installing-pgpartman)

Debian apt:

```
sudo apt install postgresql-11-partman
```

### [postgresql.conf](#postgresqlconf)

`/etc/postgresql/11/main/conf.d/pgpartman.conf`

```
### General
shared_preload_libraries = 'pg_stat_statements, pg_partman_bgw' # (change requires restart)

### Partitioning & pg_partman settings
enable_partition_pruning = on
pg_partman_bgw.interval = 3600
pg_partman_bgw.role = 'zabbix'
pg_partman_bgw.dbname = 'zabbix'
pg_partman_bgw.analyze = off
pg_partman_bgw.jobmon = on
```

Restart postgresql (`sudo systemctl restart postgresql.service`) and in the logs you should see `pg_partman master background worker master process initialized with role zabbix`.

Connect as postgres user to Zabbix database and create the extensions as part of the `public` schema on the Zabbix database.

```
sudo -su postgres psql -d zabbix
```
Then create the SCHEMA and EXTENSION:
```
CREATE SCHEMA partman;
CREATE EXTENSION pg_partman schema partman;
```

Optionally depending on the user you used for this operation you need to set the right access right to your zabbix role, eg.
```
GRANT USAGE ON SCHEMA partman TO zabbix;
GRANT SELECT ON ALL TABLES IN SCHEMA partman TO zabbix;
GRANT DELETE ON ALL TABLES IN SCHEMA partman TO zabbix;
```

### [Create Partitioned Tables](#create-partitioned-tables)

Perform the SQL queries **on the Zabbix database** (otherwise it won't find the functions in another database where the extension was added) which will target the pg_partman functions uploaded

```
select partman.create_parent('public.history', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
select partman.create_parent('public.history_uint', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
select partman.create_parent('public.history_str', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
select partman.create_parent('public.history_text', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
select partman.create_parent('public.history_log', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
select partman.create_parent('public.trends', 'clock', 'native', 'monthly', null, 12, 'on', null, true, 'seconds');
select partman.create_parent('public.trends_uint', 'clock', 'native', 'monthly', null, 12, 'on', null, true, 'seconds');
```

This can be changed by using the UPDATE command on the `partman.part_config` table; for e.g.:

```
UPDATE partman.part_config SET premake = 7 WHERE parent_table = 'public.history_log';
```

### [Deleting Designated Partitions](#deleting-designated-partitions)

It is impossible to manually remove partitions, thus use `partman.part_config` table config:

```
UPDATE partman.part_config set retention = '30 day', retention_keep_table = false, retention_keep_index = false WHERE parent_table = 'public.history';
```

Then execute maintenance procedure:

```
SELECT partman.run_maintenance('public.history');
```

### [Partition Maintenance: Creating Future Partitions](#partition-maintenance-creating-future-partitions)

pg_partman has a function `run_maintenance` that allows one to automate the table maintenance.

```
SELECT run_maintenance(p_analyze := false);

 -- note: disabling analyze is recommended for native partitioning due to aggressive locks
```

**Native partitioning can result in heavy locking and therefore it is recommended to set p_analyze to FALSE which will effectively disable analyze.**

### [Partition Maintenance: Dropping/expiring old partitions](#partition-maintenance-droppingexpiring-old-partitions)

To configure pg_partman to drop old partitions, update the `partman.part_config` tables:

```
UPDATE partman.part_config SET retention_keep_table = false, retention = '7 day'
WHERE parent_table = 'public.history';
UPDATE partman.part_config SET retention_keep_table = false, retention = '7 day'
WHERE parent_table = 'public.history_uint';
UPDATE partman.part_config SET retention_keep_table = false, retention = '7 day'
WHERE parent_table = 'public.history_str';
UPDATE partman.part_config SET retention_keep_table = false, retention = '7 day'
WHERE parent_table = 'public.history_text';
UPDATE partman.part_config SET retention_keep_table = false, retention = '7 day'
WHERE parent_table = 'public.history_log';
UPDATE partman.part_config SET retention_keep_table = false, retention = '12 month'
WHERE parent_table = 'public.trends';
UPDATE partman.part_config SET retention_keep_table = false, retention = '12 month'
WHERE parent_table = 'public.trends_uint';
```

Following this change run the maintenance actively via SQL:

```
SELECT partman.run_maintenance('public.history');
SELECT partman.run_maintenance('public.history_uint');
SELECT partman.run_maintenance('public.history_str');
SELECT partman.run_maintenance('public.history_text');
SELECT partman.run_maintenance('public.history_log');
SELECT partman.run_maintenance('public.trends');
SELECT partman.run_maintenance('public.trends_uint');
```

---

## [Change Zabbix history tables from monthly to daily with pg_partman](#change-zabbix-history-tables-from-monthly-to-daily-with-pgpartman)


* Originally we agreed to perform monthly partitions on the history* tables. But there is so much data being sent to Zabbix it increases the Zabbix database quickly. This will make scaling a problem in the future.
* Although we can keep attaching disks the simple, scalable and permanent solution is to implement "Daily" partitions on all history* tables.
* Currently (20190212) the partitioned tables for history* are based on monthly partitions.
* The Zabbix Consultants recommend using daily partitions no longer than 7 days previously. Additionally the Zabbix Official Documentation clarifies this in detail - https://www.zabbix.com/documentation/current/manual/config/items/history_and_trends
* The Zabbix Housekeeper, based on the rule set in Administration | General | Housekeeping to 7 days and 365 days respectively for history* and trends* data. Thus there is NO POINT IN RETAINING LONGER THAN 7 DAYS OF HISTORY IF ALREADY SPECIFIED IN THE FRONTEND.
* https://github.com/pgpartman/pg_partman/issues/248


**PRIOR**
1. Set 5 hour maintenance window. Take a snapshot of the database. pg_dump remotely the database and have backups upon backups...
2. Stop NGINX GUI, then Zabbix Server.
3. Kill all connections to the database.
```
-- view connections
SELECT sum(numbackends) FROM pg_stat_database;

-- kill all connections
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = 'zabbix'
  AND pid <> pg_backend_pid();
```

**PROCEDURE**

_Objective_: changing the following example table (plus 4 other tables ~10GGB each) from monthly to daily partitions while minimizing downtime and data loss.

```
zabbix=# \d+ history
                                     Table "public.history"
 Column |     Type      | Collation | Nullable | Default | Storage | Stats target | Description
--------+---------------+-----------+----------+---------+---------+--------------+-------------
 itemid | bigint        |           | not null |         | plain   |              |
 clock  | integer       |           | not null | 0       | plain   |              |
 value  | numeric(16,4) |           | not null | 0.0000  | main    |              |
 ns     | integer       |           | not null | 0       | plain   |              |
Partition key: RANGE (clock)
Indexes:
    "history_1" btree (itemid, clock)
Partitions: history_p2019_01 FOR VALUES FROM (1546300800) TO (1548979200),
            history_p2019_02 FOR VALUES FROM (1548979200) TO (1551398400),
            history_p2019_03 FOR VALUES FROM (1551398400) TO (1554076800),
            history_p2019_04 FOR VALUES FROM (1554076800) TO (1556668800),
            history_p2019_05 FOR VALUES FROM (1556668800) TO (1559347200),
            history_p2019_06 FOR VALUES FROM (1559347200) TO (1561939200),
            history_p2019_07 FOR VALUES FROM (1561939200) TO (1564617600),
            history_default DEFAULT
```

Procedure:
00. Delete data older than 7 days. This will simplify and speed up the moving process.

```
/* The following is just an example of an epoch timestamp 7 days out from initiall creating this procedure - https://www.epochconverter.com/ ...
delete FROM history where age(to_timestamp(history.clock)) > interval '7 days';
delete FROM history_uint where age(to_timestamp(history_uint.clock)) > interval '7 days' ;
delete FROM history_str where age(to_timestamp(history_str.clock)) > interval '7 days' ;
delete FROM history_log where age(to_timestamp(history_log.clock)) > interval '7 days' ;
delete FROM history_text where age(to_timestamp(history_text.clock)) > interval '7 days' ;
```

0. Stop pg_partman from running the dynamic background worker to perform table maintenance on the `history*` tables in the `partman.part_config` column used by the maintenance


```
UPDATE partman.part_config SET automatic_maintenance = 'off' WHERE parent_table = 'public.history';
UPDATE partman.part_config SET automatic_maintenance = 'off' WHERE parent_table = 'public.history_uint';
UPDATE partman.part_config SET automatic_maintenance = 'off' WHERE parent_table = 'public.history_str';
UPDATE partman.part_config SET automatic_maintenance = 'off' WHERE parent_table = 'public.history_log';
UPDATE partman.part_config SET automatic_maintenance = 'off' WHERE parent_table = 'public.history_text';
```

1. Create a table similar to the one being unpartitioned. For e.g.:


```
-- history_moved
CREATE TABLE public.history_moved
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    value numeric(16,4) NOT NULL DEFAULT 0.0000,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_moved_1 ON public.history_moved USING BRIN (itemid, clock);

-- history_uint_moved
CREATE TABLE public.history_uint_moved
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    value numeric(20,0) NOT NULL DEFAULT (0)::numeric,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_uint_moved_1 ON public.history_uint_moved USING BRIN (itemid, clock);

-- history_str_moved
CREATE TABLE public.history_str_moved
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    value character varying(255) COLLATE pg_catalog."default" NOT NULL DEFAULT ''::character varying,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_str_moved_1 ON public.history_str_moved USING BRIN (itemid, clock);

-- history_log_moved
CREATE TABLE public.history_log_moved
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    "timestamp" integer NOT NULL DEFAULT 0,
    source character varying(64) COLLATE pg_catalog."default" NOT NULL DEFAULT ''::character varying,
    severity integer NOT NULL DEFAULT 0,
    value text COLLATE pg_catalog."default" NOT NULL DEFAULT ''::text,
    logeventid integer NOT NULL DEFAULT 0,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_log_moved_1 ON public.history_log_moved USING BRIN (itemid, clock);

-- history_text_moved
CREATE TABLE public.history_text_moved
(
    itemid bigint NOT NULL,
    clock integer NOT NULL DEFAULT 0,
    value text COLLATE pg_catalog."default" NOT NULL DEFAULT ''::text,
    ns integer NOT NULL DEFAULT 0
) PARTITION BY RANGE (clock);

CREATE INDEX history_text_moved_1 ON public.history_text_moved USING BRIN (itemid, clock);
```

Then run

```
select partman.create_parent('public.history_moved', 'clock', 'native', 'monthly', null, 1, 'on', null, true, 'seconds');
select partman.create_parent('public.history_uint_moved', 'clock', 'native', 'monthly', null, 1, 'on', null, true, 'seconds');
select partman.create_parent('public.history_str_moved', 'clock', 'native', 'monthly', null, 1, 'on', null, true, 'seconds');
select partman.create_parent('public.history_log_moved', 'clock', 'native', 'monthly', null, 1, 'on', null, true, 'seconds');
select partman.create_parent('public.history_text_moved', 'clock', 'native', 'monthly', null, 1, 'on', null, true, 'seconds');
```

2. Call the `partman.undo_partition_proc()` function on the table wanting to be unpartitioned. This seems to lock the table and you can't view any information in the frontend:

```
CALL partman.undo_partition_proc('public.history', '1 day', null, 1, 'public.history_moved', false, 0, 10, false);
CALL partman.undo_partition_proc('public.history_uint', '1 day', null, 3, 'public.history_uint_moved', false, 0, 10, false);
CALL partman.undo_partition_proc('public.history_str', '1 day', null, 3, 'public.history_str_moved', false, 0, 10, false);
CALL partman.undo_partition_proc('public.history_log', '1 day', null, 3, 'public.history_log_moved', false, 0, 10, false);
CALL partman.undo_partition_proc('public.history_text', '1 day', null, 3, 'public.history_text_moved', false, 0, 10, false);
```

```
VACUUM ANALYZE history;
VACUUM ANALYZE history_uint;
VACUUM ANALYZE history_str;
VACUUM ANALYZE history_log;
VACUUM ANALYZE history_text;
```

3. Create the partitioned tables on the original `history*` tables wanting daily partitions:

```
select partman.create_parent('public.history', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
select partman.create_parent('public.history_uint', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
select partman.create_parent('public.history_str', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
select partman.create_parent('public.history_log', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
select partman.create_parent('public.history_text', 'clock', 'native', 'daily', null, 7, 'on', null, true, 'seconds');
```

4. INSERT the data back into the newly partitioned tables. Use https://www.epochconverter.com/ to find epoch timestamp <= '7 days'. Below is just an example:


```
INSERT INTO public.history SELECT * FROM public.history_moved WHERE clock > 1549168074;
INSERT INTO public.history_uint SELECT * FROM public.history_uint_moved WHERE clock > 1549168074;
INSERT INTO public.history_str SELECT * FROM public.history_str_moved WHERE clock > 1549168074;
INSERT INTO public.history_log SELECT * FROM public.history_log_moved WHERE clock > 1549168074;
INSERT INTO public.history_text SELECT * FROM public.history_text_moved WHERE clock > 1549168074;
```

5. Drop the old table and remove the `partman.part_config` column


```
DROP TABLE history_moved;
DELETE FROM partman.part_config WHERE parent_table = 'public.history_moved';
DROP TABLE history_uint_moved;
DELETE FROM partman.part_config WHERE parent_table = 'public.history_uint_moved';
DROP TABLE history_str_moved;
DELETE FROM partman.part_config WHERE parent_table = 'public.history_str_moved';
DROP TABLE history_log_moved;
DELETE FROM partman.part_config WHERE parent_table = 'public.history_log_moved';
DROP TABLE history_text_moved;
DELETE FROM partman.part_config WHERE parent_table = 'public.history_text_moved';
```

6. UPDATE the `partman.part_config` for `public.history`:


```
UPDATE partman.part_config SET automatic_maintenance = 'on', retention_keep_table = false, retention = '8 day' WHERE parent_table = 'public.history';
UPDATE partman.part_config SET automatic_maintenance = 'on', retention_keep_table = false, retention = '8 day' WHERE parent_table = 'public.history_uint';
UPDATE partman.part_config SET automatic_maintenance = 'on', retention_keep_table = false, retention = '8 day' WHERE parent_table = 'public.history_str';
UPDATE partman.part_config SET automatic_maintenance = 'on', retention_keep_table = false, retention = '8 day' WHERE parent_table = 'public.history_log';
UPDATE partman.part_config SET automatic_maintenance = 'on', retention_keep_table = false, retention = '8 day' WHERE parent_table = 'public.history_text';
```

7. Run the maintenance:


```
SELECT partman.run_maintenance('public.history');
SELECT partman.run_maintenance('public.history_uint');
SELECT partman.run_maintenance('public.history_str');
SELECT partman.run_maintenance('public.history_log');
SELECT partman.run_maintenance('public.history_text');
```

8. Verify `partman.part_config`:

```
SELECT * FROM partman.part_config;
```

9. Run VACUUM ANALYZE:

```
VACUUM ANALYZE history;
VACUUM ANALYZE history_uint;
VACUUM ANALYZE history_str;
VACUUM ANALYZE history_log;
VACUUM ANALYZE history_text;
```

Ensure `pg_partman_bgw` is set in `postgresql.conf` file.

---

## [Zabbix Remote Data Dump](#zabbix-remote-data-dump)

### [pgdump/pgrestore Manual Mechanism](#pgdumppgrestore-manual-mechanism)

On the old database, ensure `pg_hba.conf` file is set to allow connections from the new database.

```
# Note that the following commands are run on the new DB instance...
root# mkdir -p /var/backups/postgresql
root# chown -R postgres:postgres /var/backups/postgresql
postgres$ time pg_dump -Fc --file=/var/backups/postgresql/zabbix.dump -d zabbix -h <OLD_ZABBIX_DATABASE>
postgres# time pg_restore -Fc -j 8 -d zabbix /var/backups/postgresql/zabbix.dump
```

---

## [Upgrade Zabbix v3.4 to v4.2 while moving from PostgreSQL v9.6 to PostgreSQL v11](#upgrade-zabbix-v34-to-v42-while-moving-from-postgresql-v96-to-postgresql-v11)

The following scenario addresses how to migrate from Zabbix version 3.4 to version 4.2 while also moving from PostgreSQL version 9.6 to version 11.

**Requirements**
* Debian 8 Jessie or Debian 9 Stretch OS Distro
* Old PostgreSQL instance running version 9.6.
* New PostgreSQL instance running version 11.

Prepare the new PostgreSQL instance for the Zabbix 4.2 database as described in the [previous section](#prepare-postgresql-database), as well as [follow the steps for installing the pg_partman extension](#installing-pgpartman).

### [Migrate the Configuration Data](#migrate-the-configuration-data)

On the old database, ensure `pg_hba.conf` file is set to allow connections from the new database.

```
# Note that the following commands are run on the new DB instance...
root# mkdir -p /var/backups/postgresql
root# chown -R postgres:postgres /var/backups/postgresql
postgres$ time pg_dump -Fd -j 4 -d zabbix -h <OLD_ZABBIX_DATABASE> -U zabbix --inserts -Z 4 --file=/var/backups/postgresql/zabbix-configuration-<DATE>  --exclude-table=history* --exclude-table=trends*
postgres# time pg_restore -Fd -j 4 -d zabbix -h 127.0.0.1 -U zabbix /var/backups/postgresql/zabbix-configuration-<DATE>
```

* In order to prevent the disk from trashing you can use the compression `pg_dump` option `-j 4`.
* Additionally using the custom directory format option `-Fd` helps restore data in parallel which is also faster.

At this point you will have all tables except `history*` and `trends*` on the new Zabbix instance.

You can then prepare the missing `history*` and `trends*` tables by following the ["create partitioned tables" section](#create-partitioned-tables) outlined above.

Once you finish the procedure of importing the configuration data from the old instance to the new instance **AND** you created the partitioned tables you can point the Zabbix server to the new DB instance.

Thus this minimizes downtime of the Zabbix environment as we can import the older `history*` and `trends*` data later while Zabbix is actively running.

Once you start the Zabbix Server you should see the following lines in the `zabbix_server.log` file verifying that the upgrade has completed successfully.

```
  6330:20190512:020451.749 using configuration file: /etc/zabbix/zabbix_server.conf
  6330:20190512:020451.862 current database version (mandatory/optional): 03040000/03040007
  6330:20190512:020451.862 required mandatory version: 04020000
  6330:20190512:020451.862 starting automatic database upgrade
  6330:20190512:020451.880 completed 0% of database upgrade
  6330:20190512:020451.897 completed 1% of database upgrade
  6330:20190512:020451.932 completed 2% of database upgrade
  ...
  6364:20190512:021416.145 completed 99% of event name update
  6364:20190512:021416.322 completed 100% of event name update
  6364:20190512:021416.555 event name update completed
  6364:20190512:021416.567 server #0 started [main process]
  ...
```

### [Migrate the old history* and trends* data](#migrate-the-old-history-and-trends-data)

In order to migrate the old data from `history*` and `trends*` data with as minimal time as possible perform the following `pg_dump/restore` command **on the new DB instance**:

```
# Note that the following commands are run on the new DB instance...
postgres$ time pg_dump -Fd -j 4 -d zabbix -h <OLD_ZABBIX_DATABASE> -U zabbix --inserts -Z 4 --file=/var/backups/postgresql/zabbix-history-<DATE> --table=history*
postgres# time pg_restore -Fd -j 4 -d zabbix -h 127.0.0.1 -U zabbix /var/backups/postgresql/zabbix-history-<DATE>
```

You can use the default `COPY` procedure (not using the `--inserts` option...), as there are no constraints on the tables. Thus it is allowed to insert all the data, even the duplicate ones, to the `history*` tables. Those will eventually be dropped via partitioning.

For the `trends*` tables it is a bit more complex. Since there are unique constraints on those tables, it is not possible to use the `COPY` approach because it will most likely fail and no data will be inserted (`COPY` is just one big transaction). Therefore we can use the `--inserts` option for `pg_dump`, which creates dump files, where each table row is an extra INSERT. You can use the following approach:

```
# Note that the following commands are run on the new DB instance...
postgres$ time pg_dump -Fd -j 4 -d zabbix -h <OLD_ZABBIX_DATABASE> -U zabbix --inserts -Z 4 --file=/var/backups/postgresql/zabbix-trends-<DATE> --table=trends*
postgres# time pg_restore -Fd -j 4 -d zabbix -h 127.0.0.1 -U zabbix /var/backups/postgresql/zabbix-trends-<DATE>
```

For **large Zabbix databases** the amount of data to restore could be exponential (Terabytes worth of trends* data) and take a very long time (hours). A use case mentioned by someone else was to change the parameter in the `postgresql.conf` file `fsync = off` (:scream:) (this just requires a reload of postgresql and not a restart of the cluster). **This is very, very risky** as turning this off can cause unrecoverable data corruption. As an end result turning off _fsync_ helped 49 million records to restore within 3 hours.

:exclamation: As always please test this properly before implementing this procedure in a production instance.

---

## [Performance Testing](#benchmarking)

### [pgbench](#pgbench)

[`pgbench`](https://www.postgresql.org/docs/current/pgbench.html) help understand **Transaction Processing Performance Council (TPC)** on a database to see performance.

* Ensure you generate enough load.
* Options
    * `-i` = initialize
    * `-s` = scaling
    * `-j` = threads
    * `-c` = clients
    * `-t` = transactions; based on clients; if 10 clients then 100,000 transactions

Example:

```
$ pgbench -i -s 50 zabbix
$ pgbench -c 10 -j 2 -t 10000 zabbix
```

### [EXPLAIN ANALYZE](#explain-analyze)

To help understand what is being done under the hood with partitioning we can use the `EXPLAIN` command. The `EXPLAIN` command shows the execution plan of a statement and how the tables i scanned.

```
$ psql -d zabbix -c "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT count(*) FROM public.history;"
```

```
$ psql -d zabbix -c "EXPLAIN ANALYZE SELECT * FROM public.history;"
```

### [Zabbix Databases Performance Results](#zabbix-database-performance-results)


**PSQL 11 Non-Partitioned Database VM**

* 8vCPU
* 16GB RAM
* SSD

```
$ pgbench -i -s 50 zabbix
$ pgbench -c 10 -j 2 -t 10000 zabbix
```

Result:
```
$ pgbench -c 10 -j 2 -t 10000 zabbix
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 50
query mode: simple
number of clients: 10
number of threads: 2
number of transactions per client: 10000
number of transactions actually processed: 100000/100000
latency average = 6.900 ms
tps = 1449.297191 (including connections establishing)
tps = 1449.363391 (excluding connections establishing)
```


**PSQL 11 Non-Partitioned Database Baremetal**

* 24 CPUs
* 126GB RAM
* HDD

```
$ pgbench -c 10 -j 2 -t 10000 zabbix
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 50
query mode: simple
number of clients: 10
number of threads: 2
number of transactions per client: 10000
number of transactions actually processed: 100000/100000
latency average = 8.235 ms
tps = 1214.341276 (including connections establishing)
tps = 1214.421294 (excluding connections establishing)
```


**PSQL 11 Partitioned Database VM**

* 8vCPU
* 16GB RAM
* SSD

```
$ pgbench -i -s 50 zabbix
$ pgbench -c 10 -j 2 -t 10000 zabbix
```

```
$ pgbench -c 10 -j 2 -t 10000 zabbix
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 50
query mode: simple
number of clients: 10
number of threads: 2
number of transactions per client: 10000
number of transactions actually processed: 100000/100000
latency average = 5.605 ms
tps = 1783.971153 (including connections establishing)
tps = 1784.074779 (excluding connections establishing)
```

---

## [Partitioning Advantages, Mistakes and Problems](#partitioning-advantages-mistakes-and-problems)

### [Partitioning Advantages](#partitioning-advantages)

* Average number of index blocks to navigate in order to find a row goes down.
* Having smaller blocks of data will improve performance.
* You can `DROP` an individual partition to erase all of the data from that range.
* The `REINDEX` operations will happen in a fraction of a time it would take for a single giant index to build.

### [Common Partitioning Mistakes](#common-partitioning-mistakes)

* Not turning on `enable_partition_pruning = on`.
* Failing to add all the same indexes or constraints to each partition that existed in the parent.
* Forgetting to assign the same permissions to each child table as the parent.
* Writing queries that don't filter on the partitioned key field. The `WHERE` clause needs to filter on constants. In general, keep the `WHERE` clauses as simple as possible, to improve the odds the optimizer will construct the exclusion proof you're looking for.
* Query overhead for partitioning is proportional to the number of partitions. Keep the number of partitions to the two digit range for best performance.
* When you manually `VACUUM/ANALYZE`, these will not cascade from the parent. You need to specifically target each partition with those operations.
* Fail to account for out of range dates in the `INSERT` trigger. Expect the bad data will show up one day with a timestamp either far in the past or in the future, relative to what you have partitioned right now. Instead of throwing an error, some prefer to redirect inserted rows from outside of the partitioned range into a holding pen partition dedicated to suspicious data.
* Regarding **logical replication** note that the [logical replication restrictions from postgres documentation](https://www.postgresql.org/docs/current/logical-replication-restrictions.html) *Replication is only possible from base tables to base tables. That is, the tables on the publication and on the subscription side must be normal tables, not views, materialized views, partition root tables, or foreign tables. In the case of partitions, you can therefore replicate a partition hierarchy one-to-one, but you cannot currently replicate to a differently partitioned setup. Attempts to replicate tables other than base tables will result in an error.*

*Reference - PostgreSQL 10 High Performance; 2018; pg 426-427*

---

## [Ansible Role](#ansible-role)

I have written an ansible role that I used to configure pg_partman. I used the role in conjunction with the excellent [ANXS postgresql](https://github.com/ANXS/postgresql) role.

For details please view [ansible|zabbix.pgpartman](ansible/zabbix.pgpartman/).

---

## [References](#references)

* Ciolli, G., & Riggs, S. (2018). *PostgreSQL 10 Administration Cookbook.* Burmingham, UK: Packt Publishing Ltd.
* Ahmed, I., Pirozzi, E., Smith, G. (2018). *PostgreSQL High Performance.* Burmingham, UK: Packt Publishing Ltd.
* Juba, S., Volkov, A. (2017). *Learning PostgreSQL 10.* Burmingham, UK: Packt Publishing Ltd.
* [PostgreSQL Official Documentation | Table Partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html)
* [PostgreSQL Official Documentation | CREATE TABLE](https://www.postgresql.org/docs/current/sql-createtable.html)
* [PostgreSQL Official Documentation | Logical Replication | Restrictions](https://www.postgresql.org/docs/current/logical-replication-restrictions.html)
* [PostgreSQL Official Documentation | pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html)
* [PostgreSQL Official Documentation | Write Ahead Log](https://www.postgresql.org/docs/current/runtime-config-wal.html)
* [pgBarman](https://www.pgbarman.org/)
* [pgbench](https://www.postgresql.org/docs/current/pgbench.html)
* [pgBouncer](https://pgbouncer.github.io/)
* [PgCookbook - a PostgreSQL documentation project](https://github.com/grayhemp/pgcookbook/blob/master/switching_to_another_server_with_pgbouncer.md)
* [pglogical](https://www.2ndquadrant.com/en/resources/pglogical/)
* [pg_partman](https://github.com/pgpartman/pg_partman)
* [Upgrading to postgreSQL 11 with Logical Replication](https://blog.2ndquadrant.com/upgrading-to-postgresql-11-with-logical-replication/)
* [Zabbix Documentation | History and Trends](https://www.zabbix.com/documentation/current/manual/config/items/history_and_trends)
* [Tuning PostgreSQL with pgbench](https://blog.codeship.com/tuning-postgresql-with-pgbench/)
* [PostgreSQL Logical Replication Gotchas](https://pgdash.io/blog/postgres-replication-gotchas.html)
* [Change already implemented PSQL 11 Native Partitioning from Monthly to Daily](https://github.com/pgpartman/pg_partman/issues/248)
* [PostgreSQL Partition Manager Extension (`pg_partman`)](https://github.com/pgpartman/pg_partman/blob/master/doc/pg_partman.md)