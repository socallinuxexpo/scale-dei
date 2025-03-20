#!/usr/bin/env python

# written in python2-compat because it has to run on old py on reg
# also written in python in general to take advantage of 'settings.py'

from __future__ import print_function, division, absolute_import
import sys
import os
import csv
import logging
import mysql.connector

# Detect Python version
PY2 = sys.version_info[0] == 2

# Handle argument parsing differently for Python 2 and 3
try:
    import argparse

    parser = argparse.ArgumentParser(
        description="Export MySQL query results to CSV"
    )

    # Database connection options
    parser.add_argument(
        "--db-host", help="MySQL database host or Unix socket path"
    )
    parser.add_argument("--db-user", help="MySQL database user")
    parser.add_argument("--db-pass", help="MySQL database password")
    parser.add_argument("--db-database", help="MySQL database name")

    parser.add_argument(
        "--directory", default=".", help="Directory to store output files"
    )
    parser.add_argument(
        "--log-level", default="INFO", help="Set log level (default: INFO)"
    )

    options = parser.parse_args()
except ImportError:
    from optparse import OptionParser

    parser = OptionParser()

    parser.add_option(
        "--db-host",
        dest="db_host",
        help="MySQL database host or Unix socket path",
    )
    parser.add_option("--db-user", dest="db_user", help="MySQL database user")
    parser.add_option(
        "--db-pass", dest="db_pass", help="MySQL database password"
    )
    parser.add_option(
        "--db-database", dest="db_database", help="MySQL database name"
    )

    parser.add_option(
        "--directory",
        dest="directory",
        default=".",
        help="Directory to store output files",
    )
    parser.add_option(
        "--log-level",
        dest="log_level",
        default="INFO",
        help="Set log level (default: INFO)",
    )

    (options, args) = parser.parse_args()

log_level = getattr(
    logging, getattr(options, "log_level", "INFO").upper(), logging.INFO
)
logging.basicConfig(
    level=log_level, format="%(asctime)s - %(levelname)s - %(message)s"
)

# If we have any DB settings passed in, we're probably not in prod, ignore
# settings.py
use_settings = not (
    options.db_host or options.db_user or options.db_pass or options.db_database
)

if use_settings:
    try:
        sys.path.append("/var/www/django/scalereg")
        import settings

        db_info = settings.DATABASES["default"]
    except ImportError as e:
        logging.error("Could not import settings.py: %s", e)
        sys.exit(1)
else:
    # Determine if --db-host is a socket or a hostname
    is_socket = options.db_host and options.db_host.startswith("/")

    db_info = {
        "USER": options.db_user,
        "PASSWORD": options.db_pass,
        "NAME": options.db_database,
    }

    if is_socket:
        db_info["SOCKET"] = options.db_host
    else:
        db_info["HOST"] = options.db_host


# SQL Queries
query_demo_data = """
SELECT
    a.question_id,
    q.text AS question_text,
    a.id AS answer_id,
    a.text AS answer_text,
    COUNT(aa.attendee_id) AS num_attendees
FROM reg6_answer a
JOIN reg6_attendee_answers aa ON a.id = aa.answer_id
JOIN reg6_question q ON a.question_id = q.id
JOIN reg6_attendee att ON aa.attendee_id = att.id
WHERE a.question_id IN (4,5,20,21,22,23,24)
AND att.valid = 1
GROUP BY a.question_id, a.id
ORDER BY a.question_id, num_attendees DESC;
"""

query_totals = """
SELECT badge_type_id, count(*) as count
FROM reg6_attendee
WHERE valid = 1
GROUP BY badge_type_id;
"""


def get_connection():
    """Establish a MySQL connection using mysql.connector."""
    connection_params = {
        "user": db_info["USER"],
        "database": db_info["NAME"],
    }

    if db_info["PASSWORD"]:
        connection_params["password"] = db_info["PASSWORD"]

    if db_info["SOCKET"]:
        connection_params["unix_socket"] = db_info["SOCKET"]
    else:
        connection_params["host"] = db_info["HOST"]

    return mysql.connector.connect(**connection_params)


def execute_query_and_save(cursor, query, filename):
    """Executes a query and saves the results to a CSV file."""
    cursor.execute(query)
    rows = cursor.fetchall()
    column_names = [desc[0] for desc in cursor.description]

    output_path = os.path.join(options.directory, filename)

    # Handle Python 2 and 3 CSV writing differences
    mode = "wb" if PY2 else "w"
    newline_arg = {} if PY2 else {"newline": ""}

    with open(output_path, mode, **newline_arg) as file:
        writer = csv.writer(file)
        writer.writerow(column_names)
        for row in rows:
            writer.writerow(row)

    logging.info("Results saved to %s", output_path)


try:
    logging.debug("Connecting to MySQL database...")
    conn = get_connection()
    cursor = conn.cursor()

    execute_query_and_save(cursor, query_demo_data, "demo_data.csv")
    execute_query_and_save(cursor, query_totals, "totals.csv")

except mysql.connector.Error as err:
    logging.error("Database error: %s", err)
finally:
    if "cursor" in locals():
        cursor.close()
    if "conn" in locals():
        conn.close()
    logging.debug("Database connection closed.")
