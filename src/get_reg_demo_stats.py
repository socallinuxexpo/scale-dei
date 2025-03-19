#!/bin/env python

# written in python2 because it has to run on old py on reg
# also written in python in general to take advantage of 'settings.py'

import sys
import os
import csv
import logging
import mysql.connector
from optparse import OptionParser

sys.path.append("/var/www/django/scalereg")
import settings

# Set up argument parsing
parser = OptionParser()
parser.add_option(
    "--directory",
    dest="directory",
    default=".",
    help="Directory to store output files (default: .)",
)
parser.add_option(
    "--log-level",
    dest="log_level",
    default="INFO",
    help="Set log level (default: INFO)",
)
(options, args) = parser.parse_args()

# Configure logging
log_level = getattr(logging, options.log_level.upper(), logging.INFO)
logging.basicConfig(
    level=log_level, format="%(asctime)s - %(levelname)s - %(message)s"
)

# Get database credentials
db_info = settings.DATABASES["default"]

# Queries
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


def execute_query_and_save(cursor, query, filename):
    """Executes a query and saves the results to a CSV file."""
    cursor.execute(query)
    rows = cursor.fetchall()
    column_names = [desc[0] for desc in cursor.description]
    output_path = os.path.join(options.directory, filename)

    with open(output_path, mode="w") as file:
        writer = csv.writer(file)
        writer.writerow(column_names)
        writer.writerows(rows)

    logging.info("Results saved to %s", output_path)


try:
    logging.debug("Connecting to MySQL database...")
    conn = mysql.connector.connect(
        host=db_info["HOST"],
        user=db_info["USER"],
        password=db_info["PASSWORD"],
        database=db_info["NAME"],
    )
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
