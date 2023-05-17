BEGIN;

-- stop on error
\set ON_ERROR_STOP on

-- Ignore constraints until we're done
SET CONSTRAINTS ALL DEFERRED;

\echo loading actor.org_unit
\i actor.org_unit.sql

\echo loading actor.usr
\i actor.usr.sql

\echo loading acq.fund
\i acq.fund.sql

\echo loading acq.provider
\i acq.provider.sql

\echo loading asset.call_number
\i asset.call_number.sql

\echo loading asset.uri
\i asset.uri.sql

\echo loading asset.uri_call_number_map
\i asset.uri_call_number_map.sql

\echo loading biblio.record_entry
\i biblio.record_entry.sql

\echo loading biblio.monograph_part
\i biblio.monograph_part.sql

\echo loading acq.edi_account
\i acq.edi_account.sql

\echo loading acq.purchase_order
\i acq.purchase_order.sql

\echo loading acq.lineitem
\i acq.lineitem.sql

\echo loading acq.lineitem_detail
\i acq.lineitem_detail.sql

\echo loading acq.invoice
\i acq.invoice.sql

\echo loading acq.invoice_entry
\i acq.invoice_entry.sql

\echo loading asset.copy_location
\i asset.copy_location.sql

\echo loading asset.copy
\i asset.copy.sql

\echo loading biblio.peer_type
\i biblio.peer_type.sql

\echo loading authority.record_entry
\i authority.record_entry.sql

\echo loading money.grocery
\i money.grocery.sql

\echo loading money.billing
\i money.billing.sql

\echo loading acq.fund_allocation
\i acq.fund_allocation.sql

\echo loading acq.fund_debit
\i acq.fund_debit.sql

\echo loading acq.fund_transfer
\i acq.fund_transfer.sql

\echo loading acq.funding_source
\i acq.funding_source.sql

\echo loading acq.funding_source_credit
\i acq.funding_source_credit.sql

\echo loading acq.invoice_item
\i acq.invoice_item.sql

\echo loading acq.po_item
\i acq.po_item.sql

\echo loading acq.provider_holding_subfield_map
\i acq.provider_holding_subfield_map.sql

\echo loading action.circulation
\i action.circulation.sql

\echo loading action.hold_copy_map
\i action.hold_copy_map.sql

\echo loading action.hold_request
\i action.hold_request.sql

\echo loading action.hold_request_note
\i action.hold_request_note.sql

\echo loading action.survey
\i action.survey.sql

\echo loading action.survey_answer
\i action.survey_answer.sql

\echo loading action.survey_question
\i action.survey_question.sql

\echo loading action.survey_response
\i action.survey_response.sql

\echo loading action.unfulfilled_hold_list
\i action.unfulfilled_hold_list.sql

\echo loading actor.card
\i actor.card.sql

\echo loading actor.hours_of_operation
\i actor.hours_of_operation.sql

\echo loading actor.org_address
\i actor.org_address.sql

\echo loading actor.org_unit_closed
\i actor.org_unit_closed.sql

\echo loading actor.org_unit_setting
\i actor.org_unit_setting.sql

\echo loading actor.passwd
\i actor.passwd.sql

\echo loading actor.stat_cat
\i actor.stat_cat.sql

\echo loading actor.stat_cat_entry
\i actor.stat_cat_entry.sql

\echo loading actor.stat_cat_entry_default
\i actor.stat_cat_entry_default.sql

\echo loading actor.stat_cat_entry_usr_map
\i actor.stat_cat_entry_usr_map.sql

\echo loading actor.usr_activity
\i actor.usr_activity.sql

\echo loading actor.usr_address
\i actor.usr_address.sql

\echo loading actor.usr_setting
\i actor.usr_setting.sql

\echo loading actor.usr_standing_penalty
\i actor.usr_standing_penalty.sql

\echo loading actor.workstation
\i actor.workstation.sql

\echo loading asset.call_number_prefix
\i asset.call_number_prefix.sql

\echo loading asset.call_number_suffix
\i asset.call_number_suffix.sql

\echo loading asset.copy_location_group
\i asset.copy_location_group.sql

\echo loading asset.copy_location_group_map
\i asset.copy_location_group_map.sql

\echo loading asset.copy_note
\i asset.copy_note.sql

\echo loading asset.copy_part_map
\i asset.copy_part_map.sql

\echo loading asset.copy_template
\i asset.copy_template.sql

\echo loading asset.course_module_course
\i asset.course_module_course.sql

\echo loading asset.course_module_course_materials
\i asset.course_module_course_materials.sql

\echo loading asset.stat_cat
\i asset.stat_cat.sql

\echo loading asset.stat_cat_entry
\i asset.stat_cat_entry.sql

\echo loading authority.bib_linking
\i authority.bib_linking.sql

\echo loading biblio.peer_bib_copy_map
\i biblio.peer_bib_copy_map.sql

\echo loading booking.reservation
\i booking.reservation.sql

\echo loading booking.reservation_attr_value_map
\i booking.reservation_attr_value_map.sql

\echo loading booking.resource
\i booking.resource.sql

\echo loading booking.resource_attr
\i booking.resource_attr.sql

\echo loading booking.resource_attr_map
\i booking.resource_attr_map.sql

\echo loading booking.resource_attr_value
\i booking.resource_attr_value.sql

\echo loading booking.resource_type
\i booking.resource_type.sql

\echo loading config.billing_type
\i config.billing_type.sql

\echo loading config.circ_limit_set
\i config.circ_limit_set.sql

\echo loading config.circ_limit_set_circ_mod_map
\i config.circ_limit_set_circ_mod_map.sql

\echo loading config.circ_limit_set_copy_loc_map
\i config.circ_limit_set_copy_loc_map.sql

\echo loading config.circ_matrix_matchpoint
\i config.circ_matrix_matchpoint.sql

\echo loading config.circ_modifier
\i config.circ_modifier.sql

\echo loading config.copy_tag_type
\i config.copy_tag_type.sql

\echo loading config.floating_group
\i config.floating_group.sql

\echo loading config.floating_group_member
\i config.floating_group_member.sql

\echo loading config.hold_matrix_matchpoint
\i config.hold_matrix_matchpoint.sql

\echo loading config.org_unit_setting_type
\i config.org_unit_setting_type.sql

\echo loading config.remoteauth_profile
\i config.remoteauth_profile.sql

\echo loading config.rule_circ_duration
\i config.rule_circ_duration.sql

\echo loading config.rule_max_fine
\i config.rule_max_fine.sql

\echo loading config.rule_recurring_fine
\i config.rule_recurring_fine.sql

\echo loading config.usr_activity_type
\i config.usr_activity_type.sql

\echo loading container.biblio_record_entry_bucket
\i container.biblio_record_entry_bucket.sql

\echo loading container.biblio_record_entry_bucket_item
\i container.biblio_record_entry_bucket_item.sql

\echo loading container.carousel
\i container.carousel.sql

\echo loading container.carousel_org_unit
\i container.carousel_org_unit.sql

\echo loading container.user_bucket
\i container.user_bucket.sql

\echo loading container.user_bucket_item
\i container.user_bucket_item.sql

\echo loading money.account_adjustment
\i money.account_adjustment.sql

\echo loading money.cash_payment
\i money.cash_payment.sql

\echo loading money.check_payment
\i money.check_payment.sql

\echo loading money.credit_card_payment
\i money.credit_card_payment.sql

\echo loading money.debit_card_payment
\i money.debit_card_payment.sql

\echo loading money.forgive_payment
\i money.forgive_payment.sql

\echo loading money.goods_payment
\i money.goods_payment.sql

\echo loading money.work_payment
\i money.work_payment.sql

\echo loading permission.grp_penalty_threshold
\i permission.grp_penalty_threshold.sql

\echo loading permission.grp_tree
\i permission.grp_tree.sql

\echo loading permission.usr_work_ou_map
\i permission.usr_work_ou_map.sql

\echo loading serial.basic_summary
\i serial.basic_summary.sql

\echo loading serial.caption_and_pattern
\i serial.caption_and_pattern.sql

\echo loading serial.distribution
\i serial.distribution.sql

\echo loading serial.issuance
\i serial.issuance.sql

\echo loading serial.item
\i serial.item.sql

\echo loading serial.pattern_template
\i serial.pattern_template.sql

\echo loading serial.stream
\i serial.stream.sql

\echo loading serial.subscription
\i serial.subscription.sql

\echo loading serial.unit
\i serial.unit.sql

\echo loading vandelay.authority_queue
\i vandelay.authority_queue.sql

\echo loading vandelay.bib_match
\i vandelay.bib_match.sql

\echo loading vandelay.bib_queue
\i vandelay.bib_queue.sql

\echo loading vandelay.match_set
\i vandelay.match_set.sql

\echo loading vandelay.match_set_point
\i vandelay.match_set_point.sql

\echo loading vandelay.queued_authority_record
\i vandelay.queued_authority_record.sql

\echo loading vandelay.queued_authority_record_attr
\i vandelay.queued_authority_record_attr.sql

\echo loading vandelay.queued_bib_record
\i vandelay.queued_bib_record.sql

\echo loading vandelay.session_tracker
\i vandelay.session_tracker.sql

SELECT SETVAL('money.billable_xact_id_seq', (SELECT MAX(id) FROM money.billing));

SELECT SETVAL('config.remote_account_id_seq', (SELECT MAX(id) FROM config.remote_account));

SELECT SETVAL('money.payment_id_seq', (SELECT MAX(id) FROM money.payment));

SELECT SETVAL('asset.copy_id_seq', (SELECT MAX(id) FROM asset.copy));

SELECT SETVAL('vandelay.queue_id_seq', (SELECT MAX(id) FROM vandelay.queue));

SELECT SETVAL('vandelay.queued_record_id_seq', (SELECT MAX(id) FROM vandelay.queued_record));

SELECT SETVAL('acq.acq_lineitem_pkey_seq', (SELECT MAX(audit_id) FROM acq.acq_lineitem_history));

SELECT SETVAL('acq.acq_purchase_order_pkey_seq', (SELECT MAX(audit_id) FROM acq.acq_purchase_order_history));

SELECT SETVAL('actor.workstation_id_seq', (SELECT MAX(id) FROM actor.workstation_setting));

SELECT SETVAL('actor.org_unit_id_seq', (SELECT MAX(id) FROM actor.org_unit));

COMMIT;

CREATE OR REPLACE FUNCTION evergreen.concerto_date_carry_tbl_col(tbl TEXT, col TEXT, datecarry INTERVAL)
RETURNS void AS $func$

DECLARE
debug_output TEXT;
squery TEXT;
ucount BIGINT := 1;
current_offset BIGINT := 0;
chunk_size INT := 500;
max_rows BIGINT := 0;

BEGIN

squery := $$SELECT COUNT(*) FROM $$ || tbl;

EXECUTE squery INTO max_rows;

WHILE ucount > 0 LOOP

    squery := $$UPDATE $$ || tbl || $$ o SET $$ || col || $$ = $$ || col || $$ + '$$ || datecarry || $$'::INTERVAL
    FROM (SELECT id FROM $$ || tbl || $$ WHERE $$ || col || $$ IS NOT NULL ORDER BY id LIMIT $$ || chunk_size || $$ OFFSET $$ || current_offset || $$ ) AS j
    WHERE o.id=j.id$$;

    -- Display what we're about to work on
    -- SELECT INTO debug_output $$ $$ || squery || $$ $$
    --  FROM biblio.record_entry LIMIT 1;
    --  RAISE NOTICE '%', debug_output;

    -- work on it
    EXECUTE squery;

    current_offset = current_offset + chunk_size;

    squery := $$ SELECT COUNT(*) FROM (SELECT id FROM $$ || tbl || $$ ORDER BY id LIMIT $$ || chunk_size || $$ OFFSET $$ || current_offset || $$) a $$;

    -- Display squery
    -- SELECT INTO debug_output $$ $$ || squery || $$ $$
    --  FROM biblio.record_entry LIMIT 1;
    --  RAISE NOTICE '%', debug_output;

    EXECUTE squery INTO ucount;
    IF ucount > 0 THEN
        RAISE NOTICE 'date carry forward: %.% % / %', tbl, col, current_offset, max_rows;
    END IF;

END LOOP;

END;
$func$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION evergreen.concerto_date_carry_all( skip_date_carry BOOLEAN DEFAULT FALSE )
RETURNS void AS $$
DECLARE
    datediff INTERVAL;

BEGIN

IF NOT skip_date_carry THEN

    SELECT INTO datediff (SELECT now() - lowdate FROM (SELECT MIN(create_date) lowdate FROM asset.call_number) as a);

    -- acq.claim_event
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.claim_event', 'event_date', datediff);

    -- acq.fund_allocation
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.fund_allocation', 'create_time', datediff);

    -- acq.fund_debit
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.fund_debit', 'create_time', datediff);

    -- acq.fund_transfer
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.fund_transfer', 'transfer_time', datediff);

    -- acq.funding_source_credit
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.funding_source_credit', 'deadline_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.funding_source_credit', 'effective_date', datediff);

    -- acq.invoice
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.invoice', 'recv_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.invoice', 'close_date', datediff);

    -- acq.lineitem
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.lineitem', 'expected_recv_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.lineitem', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.lineitem', 'edit_time', datediff);

    -- acq.lineitem_detail
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.lineitem_detail', 'recv_time', datediff);

    -- acq.purchase_order
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.purchase_order', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.purchase_order', 'edit_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.purchase_order', 'order_date', datediff);

    -- action.circulation
    -- relying on action.push_circ_due_time() to take care of the 1 second before midnight logic
    -- Omitting xact_start and xact_finish because those are going to get updated when the parent table is updated
    PERFORM evergreen.concerto_date_carry_tbl_col('action.circulation', 'due_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.circulation', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.circulation', 'stop_fines_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.circulation', 'checkin_time', datediff);

    -- action.hold_request
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'request_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'capture_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'fulfillment_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'checkin_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'return_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'prev_check_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'expire_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'cancel_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'thaw_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'shelf_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'shelf_expire_time', datediff);

    -- action.survey
    PERFORM evergreen.concerto_date_carry_tbl_col('action.survey', 'start_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.survey', 'end_date', datediff);

    -- action.survey_response
    PERFORM evergreen.concerto_date_carry_tbl_col('action.survey_response', 'answer_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.survey_response', 'effective_date', datediff);

    -- action.unfulfilled_hold_list
    PERFORM evergreen.concerto_date_carry_tbl_col('action.unfulfilled_hold_list', 'fail_time', datediff);

    -- actor.org_unit_closed
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.org_unit_closed', 'close_start', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.org_unit_closed', 'close_end', datediff);

    -- actor.passwd
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.passwd', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.passwd', 'edit_date', datediff);

    -- actor.usr
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr', 'expire_date', datediff);

    -- actor.usr_activity
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr_activity', 'event_time', datediff);

    -- actor.usr_standing_penalty
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr_standing_penalty', 'set_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr_standing_penalty', 'stop_date', datediff);

    -- asset.call_number
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.call_number', 'create_date', datediff);

    -- asset.copy
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy', 'edit_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy', 'status_changed_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy', 'active_date', datediff);

    -- asset.copy_note
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy_note', 'create_date', datediff);

    -- authority.record_entry
    PERFORM evergreen.concerto_date_carry_tbl_col('authority.record_entry', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('authority.record_entry', 'edit_date', datediff);

    -- biblio.record_entry
    PERFORM evergreen.concerto_date_carry_tbl_col('biblio.record_entry', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('biblio.record_entry', 'edit_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('biblio.record_entry', 'merge_date', datediff);

    -- booking.reservation
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'request_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'start_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'end_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'capture_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'cancel_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'pickup_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'return_time', datediff);

    -- container.biblio_record_entry_bucket
    PERFORM evergreen.concerto_date_carry_tbl_col('container.biblio_record_entry_bucket', 'create_time', datediff);

    -- container.carousel
    PERFORM evergreen.concerto_date_carry_tbl_col('container.carousel', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('container.carousel', 'edit_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('container.carousel', 'last_refresh_time', datediff);

    -- container.user_bucket
    PERFORM evergreen.concerto_date_carry_tbl_col('container.user_bucket', 'create_time', datediff);

    -- container.user_bucket_item
    PERFORM evergreen.concerto_date_carry_tbl_col('container.user_bucket', 'create_time', datediff);

    -- money.billable_xact
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billable_xact', 'xact_start', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billable_xact', 'xact_finish', datediff);

    -- money.billing
    ALTER TABLE money.billing DISABLE TRIGGER maintain_billing_ts_tgr;
    ALTER TABLE money.billing DISABLE TRIGGER mat_summary_upd_tgr;
    ALTER TABLE money.billing DROP CONSTRAINT billing_btype_fkey;

    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'billing_ts', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'void_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'period_start', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'period_end', datediff);

    ALTER TABLE money.billing ENABLE TRIGGER maintain_billing_ts_tgr;
    ALTER TABLE money.billing ENABLE TRIGGER mat_summary_upd_tgr;
    ALTER TABLE money.billing ADD CONSTRAINT billing_btype_fkey FOREIGN KEY (btype)
      REFERENCES config.billing_type (id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

    -- money.payment
    PERFORM evergreen.concerto_date_carry_tbl_col('money.payment', 'payment_ts', datediff);

    -- serial.caption_and_pattern
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.caption_and_pattern', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.caption_and_pattern', 'start_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.caption_and_pattern', 'end_date', datediff);

    -- serial.issuance
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.issuance', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.issuance', 'edit_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.issuance', 'date_published', datediff);

    -- serial.item
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.item', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.item', 'edit_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.item', 'date_expected', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.item', 'date_received', datediff);

    -- serial.subscription
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.subscription', 'start_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.subscription', 'end_date', datediff);

    -- vandelay.queued_record
    PERFORM evergreen.concerto_date_carry_tbl_col('vandelay.queued_record', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('vandelay.queued_record', 'import_time', datediff);

    -- vandelay.session_tracker
    PERFORM evergreen.concerto_date_carry_tbl_col('vandelay.session_tracker', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('vandelay.session_tracker', 'update_time', datediff);

END IF;
END;
$$ LANGUAGE plpgsql;

\set ON_ERROR_STOP off

CREATE TABLE IF NOT EXISTS evergreen.tvar_carry_date(tvar BOOLEAN);
INSERT INTO evergreen.tvar_carry_date(tvar)
VALUES(:skip_date_carry::boolean);

BEGIN;

DO $$
DECLARE skip BOOLEAN;
BEGIN

    SELECT INTO skip tvar FROM evergreen.tvar_carry_date LIMIT 1;
    IF NOT FOUND THEN skip = FALSE;
    END IF;

    PERFORM evergreen.concerto_date_carry_all(skip);

END;

$$;

COMMIT;

DROP FUNCTION evergreen.concerto_date_carry_all(BOOLEAN);
DROP FUNCTION evergreen.concerto_date_carry_tbl_col(TEXT, TEXT, INTERVAL);

DROP TABLE IF EXISTS evergreen.tvar_carry_date;


