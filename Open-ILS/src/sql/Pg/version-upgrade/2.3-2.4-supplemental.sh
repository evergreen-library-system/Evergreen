#!/bin/bash

echo "Starting update of field_entry values.  This will take a while..."
date

psql -c "UPDATE metabib.identifier_field_entry set value = value;" &
psql -c "UPDATE metabib.title_field_entry set value = value;" &
psql -c "UPDATE metabib.author_field_entry set value = value;" &
psql -c "UPDATE metabib.subject_field_entry set value = value;" &
psql -c "UPDATE metabib.keyword_field_entry set value = value;" &
psql -c "UPDATE metabib.series_field_entry set value = value;" &

wait

echo "Completed update of field_entry values."
date

echo "Starting update of combined field_entry values.  This will also take a while..."
psql -c "SELECT count(metabib.update_combined_index_vectors(id)) FROM biblio.record_entry WHERE NOT deleted;" &

echo "Starting creation of indexes from 0782..."
echo "There may be deadlock errors; if they happen, this script will"
echo "rebuild the affected invalid indexes at the end."
psql -c "CREATE INDEX CONCURRENTLY usr_activity_usr_idx on actor.usr_activity (usr);" &
psql -c "CREATE INDEX CONCURRENTLY hold_request_open_idx on action.hold_request (id) where cancel_time IS NULL AND fulfillment_time IS NULL;" &
psql -c "CREATE INDEX CONCURRENTLY cp_available_by_circ_lib_idx on asset.copy (circ_lib) where status IN (0,7);" &
psql -c "CREATE INDEX CONCURRENTLY edi_message_account_status_idx on acq.edi_message (account,status);" &
psql -c "CREATE INDEX CONCURRENTLY atev_def_state on action_trigger.event (event_def,state);" &
psql -c "CREATE INDEX CONCURRENTLY hold_transit_copy_hold_idx on action.hold_transit_copy (hold);" &

wait

echo "Starting creation of more indexes from 0782..."
psql -c "CREATE INDEX CONCURRENTLY hold_request_current_copy_before_cap_idx on action.hold_request (current_copy) where capture_time IS NULL AND cancel_time IS NULL;" &
psql -c "CREATE INDEX CONCURRENTLY edi_message_po_idx on acq.edi_message (purchase_order);" &

wait

echo "Parallel updates complete."
echo "Creating any indexes that may not have been built due to a deadlock"
echo "bug in PostgreSQL"
date

rebuildscript=`mktemp`
psql -A -t -c "SELECT 'DROP INDEX ' || n.nspname || '.' || i.relname || ';' \
FROM pg_index x \
JOIN pg_class c ON c.oid = x.indrelid \
JOIN pg_class i ON i.oid = x.indexrelid \
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace \
WHERE c.relkind = 'r'::\"char\" AND i.relkind = 'i'::\"char\" \
AND n.nspname IN ('action', 'action_trigger', 'actor', 'acq', 'asset') \
AND NOT x.indisvalid;" >  $rebuildscript

psql -A -t -c "SELECT pg_get_indexdef(i.oid) || ';' \
FROM pg_index x \
JOIN pg_class c ON c.oid = x.indrelid \
JOIN pg_class i ON i.oid = x.indexrelid \
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace \
WHERE c.relkind = 'r'::\"char\" AND i.relkind = 'i'::\"char\" \
AND n.nspname IN ('action', 'action_trigger', 'actor', 'acq', 'asset') \
AND NOT x.indisvalid;" >> $rebuildscript

psql -a -f $rebuildscript

echo "Combined field_entry values and index creation complete"
date
