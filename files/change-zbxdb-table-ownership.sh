#!/bin/bash
# Description: Changes the database to the specified database user.
#              Run as postgres user; i.e. superuser of postgres DB.
# Usage: ./change-zbxdb-table-ownership.sh zabbix zabbix

DATABASE=$1
NEW_OWNER=$2

# test that there are two arguments
if test $# -lt 2; then
  echo "usage: $0 <DATABASE> <NEW_OWNER>"
  exit 0
fi

tables=`psql -qAt -c "select tablename from pg_tables where schemaname = 'public';" $DATABASE`

for tbl in $tables ; do
  psql -c "alter table $tbl owner to $NEW_OWNER" $DATABASE ;
done