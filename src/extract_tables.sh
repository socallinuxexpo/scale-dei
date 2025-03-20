#!/bin/bash

# In the event we need to get data from previous years, this will extract
# the relevant tables from the backup file for easy importing into a local
# mysql instance.
#
# Then do `cat * | mysql <params> <db>`

input=$1
base=$(basename $input .sql)

for table in reg6_answer reg6_attendee_answers reg6_question reg6_attendee; do
    sed -n \
        '/Table structure for table `'$table'`/,/Table structure for table `/p' \
        $input > "${base}_${table}.sql"
done
