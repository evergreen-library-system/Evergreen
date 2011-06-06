BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0549'); --dbs

-- config settings group
INSERT INTO config.settings_group (name, label) VALUES
('sys', 'System'),
('finance','Finances'),
('holds','Holds'),
('circ','Circulation'),
('self','Self Check'),
('opac','OPAC'),
('gui','GUI'),
('lib','Library'),
('sec','Security'),
('prog','Program'),
('glob','Global'),
('credit','Credit Card Processing'),
('cat','Cataloging'),
('serial','Serials'),
('recall','Recalls');

-- Set up all of the config.org_unit_setting_type[s] with a proper group.
UPDATE config.org_unit_setting_type SET grp = 'cat' WHERE name = 'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel';
UPDATE config.org_unit_setting_type SET grp = 'cat' WHERE name = 'cat.default_classification_scheme';
UPDATE config.org_unit_setting_type SET grp = 'cat' WHERE name = 'cat.label.font.family';
UPDATE config.org_unit_setting_type SET grp = 'cat' WHERE name = 'cat.label.font.size';
UPDATE config.org_unit_setting_type SET grp = 'cat' WHERE name = 'cat.label.font.weight';
UPDATE config.org_unit_setting_type SET grp = 'cat' WHERE name = 'cat.marc_control_number_identifier';
UPDATE config.org_unit_setting_type SET grp = 'cat' WHERE name = 'cat.spine.line.height';
UPDATE config.org_unit_setting_type SET grp = 'cat' WHERE name = 'cat.spine.line.margin';
UPDATE config.org_unit_setting_type SET grp = 'cat' WHERE name = 'cat.spine.line.width';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.checkout_auto_renew_age';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.checkout_fills_related_hold';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.do_not_tally_claims_returned';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.holds.expired_patron_block';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.hold_shelf_status_delay';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.lost_immediately_available';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.max_accept_return_of_lost';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.max_fine.cap_at_price';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.max_patron_claim_return_count';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.missing_pieces.copy_status';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.password_reset_request_requires_matching_email';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.patron_edit.clone.copy_address';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.patron_invalid_address_apply_penalty';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.restore_overdue_on_lost_return';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.void_lost_on_checkin';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.void_lost_proc_fee_on_checkin';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'ui.circ.suppress_checkin_popups';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.authorizenet.enabled';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.authorizenet.login';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.authorizenet.password';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.authorizenet.server';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.authorizenet.testmode';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.default';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.payflowpro.enabled';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.payflowpro.login';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.payflowpro.partner';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.payflowpro.password';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.payflowpro.testmode';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.payflowpro.vendor';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.paypal.enabled';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.paypal.login';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.paypal.password';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.paypal.signature';
UPDATE config.org_unit_setting_type SET grp = 'credit' WHERE name = 'credit.processor.paypal.testmode';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'acq.fund.balance_limit.block';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'acq.fund.balance_limit.warn';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'cat.default_item_price';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.charge_lost_on_zero';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.charge_on_damaged';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.damaged_item_processing_fee';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.lost_materials_processing_fee';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.void_overdue_on_lost';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'credit.payments.allow';
UPDATE config.org_unit_setting_type SET grp = 'glob' WHERE name = 'global.default_locale';
UPDATE config.org_unit_setting_type SET grp = 'glob' WHERE name = 'global.password_regex';
UPDATE config.org_unit_setting_type SET grp = 'glob' WHERE name = 'opac.barcode_regex';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'cat.bib.alert_on_empty';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'circ.auto_hide_patron_summary';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'circ.item_checkout_history.max';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'format.date';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'format.time';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'gui.disable_local_save_columns';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.admin.patron_log.max_entries';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.admin.work_log.max_entries';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.circ.in_house_use.entry_cap';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.circ.in_house_use.entry_warn';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.circ.patron_summary.horizontal';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.circ.show_billing_tab_on_bills';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.general.button_bar';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.general.idle_timeout';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.default_country';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.default_ident_type';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.aua.county.require';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.active.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.active.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.alert_message.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.alert_message.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.alias.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.alias.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.aua.post_code.example';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.aua.post_code.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.barred.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.barred.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.claims_never_checked_out_count.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.claims_never_checked_out_count.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.claims_returned_count.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.claims_returned_count.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.day_phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.day_phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.day_phone.require';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.day_phone.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.day_phone.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.dob.calendar';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.dob.require';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.dob.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.dob.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.email.example';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.email.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.email.require';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.email.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.email.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.evening_phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.evening_phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.evening_phone.require';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.evening_phone.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.evening_phone.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.ident_value2.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.ident_value2.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.ident_value.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.ident_value.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.juvenile.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.juvenile.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.master_account.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.master_account.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.other_phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.other_phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.other_phone.require';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.other_phone.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.other_phone.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.second_given_name.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.second_given_name.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.suffix.show';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.au.suffix.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.default_suggested';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.edit.phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.patron.registration.require_address';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.staff.require_initials';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'url.remote_column_settings';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.block_renews_for_holds';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.hold_boundary.hard';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.hold_boundary.soft';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.hold_expire_alert_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.hold_expire_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.behind_desk_pickup_supported';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.canceled.display_age';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.canceled.display_count';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.clear_shelf.copy_status';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.clear_shelf.no_capture_holds';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.default_estimated_wait_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.default_shelf_expire_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds_fifo';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.hold_has_copy_at.alert';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.hold_has_copy_at.block';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.max_org_unit_target_loops';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.min_estimated_wait_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.org_unit_target_weight';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.hold_stalling_hard';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.hold_stalling.soft';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.target_holds_by_org_unit_weight';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.target_skip_me';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.uncancel.reset_request_time';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.default_circ_modifier';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.default_copy_location';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.holds.allow_holds_from_purchase_request';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.tmp_barcode_prefix';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.tmp_callnumber_prefix';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.booking_reservation.default_elbow_room';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.claim_never_checked_out.mark_missing';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.claim_return.copy_status';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.damaged.void_ovedue';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.pre_cat_copy_circ_lib';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.reshelving_complete.interval';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'global.juvenile_age_threshold';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'lib.courier_code';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'notice.telephony.callfile_lines';
UPDATE config.org_unit_setting_type SET grp = 'opac' WHERE name = 'opac.allow_pending_address';
UPDATE config.org_unit_setting_type SET grp = 'opac' WHERE name = 'opac.fully_compressed_serial_holdings';
UPDATE config.org_unit_setting_type SET grp = 'opac' WHERE name = 'opac.org_unit_hiding.depth';
UPDATE config.org_unit_setting_type SET grp = 'prog' WHERE name = 'cat.bib.keep_on_empty';
UPDATE config.org_unit_setting_type SET grp = 'prog' WHERE name = 'circ.staff_client.do_not_auto_attempt_print';
UPDATE config.org_unit_setting_type SET grp = 'prog' WHERE name = 'org.bounced_emails';
UPDATE config.org_unit_setting_type SET grp = 'recall' WHERE name = 'circ.holds.recall_fine_rules';
UPDATE config.org_unit_setting_type SET grp = 'recall' WHERE name = 'circ.holds.recall_return_interval';
UPDATE config.org_unit_setting_type SET grp = 'recall' WHERE name = 'circ.holds.recall_threshold';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'auth.opac_timeout';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'auth.persistent_login_interval';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'auth.staff_timeout';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'circ.obscure_dob';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'circ.offline.username_allowed';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'circ.password_reset_request_per_user_limit';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'circ.password_reset_request_throttle';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'circ.password_reset_request_time_to_live';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'patron.password.use_phone';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'ui.patron.default_inet_access_level';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.alert.popup';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.alert.sound';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.auto_override_checkout_events';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.block_checkout_on_copy_status';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.patron_login_timeout';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.patron_password_required';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.require_patron_password';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.workstation_required';
UPDATE config.org_unit_setting_type SET grp = 'serial' WHERE name = 'serial.prev_issuance_copy_location';

COMMIT;
