BEGIN;

/* LP#1479953: Adding indexes to foreign key references to
 * vandelay.queued_bib_record will speed up deletions of vqbr records (thereby
 * speeding up vandelay.bib_queue deletions).
 */

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE INDEX acq_lineitem_history_queued_record ON acq.acq_lineitem_history (queued_record);
CREATE INDEX li_queued_record ON acq.lineitem (queued_record);
CREATE INDEX bib_match_queued_record ON vandelay.bib_match (queued_record);
CREATE INDEX import_item_record ON vandelay.import_item (record);

COMMIT;
