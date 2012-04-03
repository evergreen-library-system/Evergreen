-- Updates config.org_unit_setting_type to remove the old tag prefixes for once 
-- groups have been added.
--
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0622', :eg_version);

INSERT INTO config.settings_group (name, label) VALUES
('sys', oils_i18n_gettext('config.settings_group.system', 'System', 'coust', 'label')),
('gui', oils_i18n_gettext('config.settings_group.gui', 'GUI', 'coust', 'label')),
('lib', oils_i18n_gettext('config.settings_group.lib', 'Library', 'coust', 'label')),
('sec', oils_i18n_gettext('config.settings_group.sec', 'Security', 'coust', 'label')),
('cat', oils_i18n_gettext('config.settings_group.cat', 'Cataloging', 'coust', 'label')),
('holds', oils_i18n_gettext('config.settings_group.holds', 'Holds', 'coust', 'label')),
('circ', oils_i18n_gettext('config.settings_group.circulation', 'Circulation', 'coust', 'label')),
('self', oils_i18n_gettext('config.settings_group.self', 'Self Check', 'coust', 'label')),
('opac', oils_i18n_gettext('config.settings_group.opac', 'OPAC', 'coust', 'label')),
('prog', oils_i18n_gettext('config.settings_group.program', 'Program', 'coust', 'label')),
('glob', oils_i18n_gettext('config.settings_group.global', 'Global', 'coust', 'label')),
('finance', oils_i18n_gettext('config.settings_group.finances', 'Finances', 'coust', 'label')),
('credit', oils_i18n_gettext('config.settings_group.ccp', 'Credit Card Processing', 'coust', 'label')),
('serial', oils_i18n_gettext('config.settings_group.serial', 'Serials', 'coust', 'label')),
('recall', oils_i18n_gettext('config.settings_group.recall', 'Recalls', 'coust', 'label')),
('booking', oils_i18n_gettext('config.settings_group.booking', 'Booking', 'coust', 'label')),
('offline', oils_i18n_gettext('config.settings_group.offline', 'Offline', 'coust', 'label')),
('receipt_template', oils_i18n_gettext('config.settings_group.receipt_template', 'Receipt Template', 'coust', 'label'));

UPDATE config.org_unit_setting_type SET grp = 'lib', label='Set copy creator as receiver' WHERE name = 'acq.copy_creator_uses_receiver';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.default_circ_modifier';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.default_copy_location';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'acq.fund.balance_limit.block';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'acq.fund.balance_limit.warn';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.holds.allow_holds_from_purchase_request';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.tmp_barcode_prefix';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.tmp_callnumber_prefix';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'auth.opac_timeout';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'auth.persistent_login_interval';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'auth.staff_timeout';
UPDATE config.org_unit_setting_type SET grp = 'booking' WHERE name = 'booking.allow_email_notify';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'cat.bib.alert_on_empty';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Delete bib if all copies are deleted via Acquisitions lineitem cancellation.' WHERE name = 'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel';
UPDATE config.org_unit_setting_type SET grp = 'prog' WHERE name = 'cat.bib.keep_on_empty';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Default Classification Scheme' WHERE name = 'cat.default_classification_scheme';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Default copy status (fast add)' WHERE name = 'cat.default_copy_status_fast';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Default copy status (normal)' WHERE name = 'cat.default_copy_status_normal';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'cat.default_item_price';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine and pocket label font family' WHERE name = 'cat.label.font.family';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine and pocket label font size' WHERE name = 'cat.label.font.size';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine and pocket label font weight' WHERE name = 'cat.label.font.weight';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Defines the control number identifier used in 003 and 035 fields.' WHERE name = 'cat.marc_control_number_identifier';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine label maximum lines' WHERE name = 'cat.spine.line.height';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine label left margin' WHERE name = 'cat.spine.line.margin';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine label line width' WHERE name = 'cat.spine.line.width';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Delete volume with last copy' WHERE name = 'cat.volume.delete_on_empty';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Toggle off the patron summary sidebar after first view.' WHERE name = 'circ.auto_hide_patron_summary';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Block Renewal of Items Needed for Holds' WHERE name = 'circ.block_renews_for_holds';
UPDATE config.org_unit_setting_type SET grp = 'booking', label='Elbow room' WHERE name = 'circ.booking_reservation.default_elbow_room';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.charge_lost_on_zero';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.charge_on_damaged';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.checkout_auto_renew_age';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.checkout_fills_related_hold';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.checkout_fills_related_hold_exact_match_only';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.claim_never_checked_out.mark_missing';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.claim_return.copy_status';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.damaged.void_ovedue';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.damaged_item_processing_fee';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Do not include outstanding Claims Returned circulations in lump sum tallies in Patron Display.' WHERE name = 'circ.do_not_tally_claims_returned';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Hard boundary' WHERE name = 'circ.hold_boundary.hard';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Soft boundary' WHERE name = 'circ.hold_boundary.soft';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Expire Alert Interval' WHERE name = 'circ.hold_expire_alert_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Expire Interval' WHERE name = 'circ.hold_expire_interval';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.hold_shelf_status_delay';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Soft stalling interval' WHERE name = 'circ.hold_stalling.soft';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Hard stalling interval' WHERE name = 'circ.hold_stalling_hard';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Use Active Date for Age Protection' WHERE name = 'circ.holds.age_protect.active_date';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Behind Desk Pickup Supported' WHERE name = 'circ.holds.behind_desk_pickup_supported';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Canceled holds display age' WHERE name = 'circ.holds.canceled.display_age';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Canceled holds display count' WHERE name = 'circ.holds.canceled.display_count';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Clear shelf copy status' WHERE name = 'circ.holds.clear_shelf.copy_status';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Bypass hold capture during clear shelf process' WHERE name = 'circ.holds.clear_shelf.no_capture_holds';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Default Estimated Wait' WHERE name = 'circ.holds.default_estimated_wait_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.default_shelf_expire_interval';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Block hold request if hold recipient privileges have expired' WHERE name = 'circ.holds.expired_patron_block';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Has Local Copy Alert' WHERE name = 'circ.holds.hold_has_copy_at.alert';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Has Local Copy Block' WHERE name = 'circ.holds.hold_has_copy_at.block';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Maximum library target attempts' WHERE name = 'circ.holds.max_org_unit_target_loops';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Minimum Estimated Wait' WHERE name = 'circ.holds.min_estimated_wait_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Org Unit Target Weight' WHERE name = 'circ.holds.org_unit_target_weight';
UPDATE config.org_unit_setting_type SET grp = 'recall', label='An array of fine amount, fine interval, and maximum fine.' WHERE name = 'circ.holds.recall_fine_rules';
UPDATE config.org_unit_setting_type SET grp = 'recall', label='Truncated loan period.' WHERE name = 'circ.holds.recall_return_interval';
UPDATE config.org_unit_setting_type SET grp = 'recall', label='Circulation duration that triggers a recall.' WHERE name = 'circ.holds.recall_threshold';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Use weight-based hold targeting' WHERE name = 'circ.holds.target_holds_by_org_unit_weight';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.target_skip_me';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Reset request time on un-cancel' WHERE name = 'circ.holds.uncancel.reset_request_time';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='FIFO' WHERE name = 'circ.holds_fifo';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'circ.item_checkout_history.max';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Lost Checkin Generates New Overdues' WHERE name = 'circ.lost.generate_overdue_on_checkin';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Lost items usable on checkin' WHERE name = 'circ.lost_immediately_available';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.lost_materials_processing_fee';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Void lost max interval' WHERE name = 'circ.max_accept_return_of_lost';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Cap Max Fine at Item Price' WHERE name = 'circ.max_fine.cap_at_price';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.max_patron_claim_return_count';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Item Status for Missing Pieces' WHERE name = 'circ.missing_pieces.copy_status';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'circ.obscure_dob';
UPDATE config.org_unit_setting_type SET grp = 'offline', label='Skip offline checkin if newer item Status Changed Time.' WHERE name = 'circ.offline.skip_checkin_if_newer_status_changed_time';
UPDATE config.org_unit_setting_type SET grp = 'offline', label='Skip offline checkout if newer item Status Changed Time.' WHERE name = 'circ.offline.skip_checkout_if_newer_status_changed_time';
UPDATE config.org_unit_setting_type SET grp = 'offline', label='Skip offline renewal if newer item Status Changed Time.' WHERE name = 'circ.offline.skip_renew_if_newer_status_changed_time';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Offline: Patron Usernames Allowed' WHERE name = 'circ.offline.username_allowed';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Maximum concurrently active self-serve password reset requests per user' WHERE name = 'circ.password_reset_request_per_user_limit';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Require matching email address for password reset requests' WHERE name = 'circ.password_reset_request_requires_matching_email';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Maximum concurrently active self-serve password reset requests' WHERE name = 'circ.password_reset_request_throttle';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Self-serve password reset request time-to-live' WHERE name = 'circ.password_reset_request_time_to_live';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Patron Registration: Cloned patrons get address copy' WHERE name = 'circ.patron_edit.clone.copy_address';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.patron_invalid_address_apply_penalty';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.pre_cat_copy_circ_lib';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.reshelving_complete.interval';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Restore overdues on lost item return' WHERE name = 'circ.restore_overdue_on_lost_return';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Pop-up alert for errors' WHERE name = 'circ.selfcheck.alert.popup';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Audio Alerts' WHERE name = 'circ.selfcheck.alert.sound';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.auto_override_checkout_events';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Block copy checkout status' WHERE name = 'circ.selfcheck.block_checkout_on_copy_status';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Patron Login Timeout (in seconds)' WHERE name = 'circ.selfcheck.patron_login_timeout';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Require Patron Password' WHERE name = 'circ.selfcheck.patron_password_required';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Require patron password' WHERE name = 'circ.selfcheck.require_patron_password';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Workstation Required' WHERE name = 'circ.selfcheck.workstation_required';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.staff_client.actor_on_checkout';
UPDATE config.org_unit_setting_type SET grp = 'prog' WHERE name = 'circ.staff_client.do_not_auto_attempt_print';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of alert_text include' WHERE name = 'circ.staff_client.receipt.alert_text';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of event_text include' WHERE name = 'circ.staff_client.receipt.event_text';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of footer_text include' WHERE name = 'circ.staff_client.receipt.footer_text';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of header_text include' WHERE name = 'circ.staff_client.receipt.header_text';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of notice_text include' WHERE name = 'circ.staff_client.receipt.notice_text';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Minimum Transit Checkin Interval' WHERE name = 'circ.transit.min_checkin_interval';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Patron Merge Deactivate Card' WHERE name = 'circ.user_merge.deactivate_cards';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Patron Merge Address Delete' WHERE name = 'circ.user_merge.delete_addresses';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Patron Merge Barcode Delete' WHERE name = 'circ.user_merge.delete_cards';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Void lost item billing when returned' WHERE name = 'circ.void_lost_on_checkin';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Void processing fee on lost item return' WHERE name = 'circ.void_lost_proc_fee_on_checkin';
UPDATE config.org_unit_setting_type SET grp = 'finance', label='Void overdue fines when items are marked lost' WHERE name = 'circ.void_overdue_on_lost';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'credit.payments.allow';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='Enable AuthorizeNet payments' WHERE name = 'credit.processor.authorizenet.enabled';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='AuthorizeNet login' WHERE name = 'credit.processor.authorizenet.login';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='AuthorizeNet password' WHERE name = 'credit.processor.authorizenet.password';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='AuthorizeNet server' WHERE name = 'credit.processor.authorizenet.server';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='AuthorizeNet test mode' WHERE name = 'credit.processor.authorizenet.testmode';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='Name default credit processor' WHERE name = 'credit.processor.default';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='Enable PayflowPro payments' WHERE name = 'credit.processor.payflowpro.enabled';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro login/merchant ID' WHERE name = 'credit.processor.payflowpro.login';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro partner' WHERE name = 'credit.processor.payflowpro.partner';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro password' WHERE name = 'credit.processor.payflowpro.password';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro test mode' WHERE name = 'credit.processor.payflowpro.testmode';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro vendor' WHERE name = 'credit.processor.payflowpro.vendor';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='Enable PayPal payments' WHERE name = 'credit.processor.paypal.enabled';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayPal login' WHERE name = 'credit.processor.paypal.login';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayPal password' WHERE name = 'credit.processor.paypal.password';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayPal signature' WHERE name = 'credit.processor.paypal.signature';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayPal test mode' WHERE name = 'credit.processor.paypal.testmode';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Format Dates with this pattern.' WHERE name = 'format.date';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Format Times with this pattern.' WHERE name = 'format.time';
UPDATE config.org_unit_setting_type SET grp = 'glob' WHERE name = 'global.default_locale';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'global.juvenile_age_threshold';
UPDATE config.org_unit_setting_type SET grp = 'glob' WHERE name = 'global.password_regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Disable the ability to save list column configurations locally.' WHERE name = 'gui.disable_local_save_columns';
UPDATE config.org_unit_setting_type SET grp = 'lib', label='Courier Code' WHERE name = 'lib.courier_code';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'notice.telephony.callfile_lines';
UPDATE config.org_unit_setting_type SET grp = 'opac', label='Allow pending addresses' WHERE name = 'opac.allow_pending_address';
UPDATE config.org_unit_setting_type SET grp = 'glob' WHERE name = 'opac.barcode_regex';
UPDATE config.org_unit_setting_type SET grp = 'opac', label='Use fully compressed serial holdings' WHERE name = 'opac.fully_compressed_serial_holdings';
UPDATE config.org_unit_setting_type SET grp = 'opac', label='Org Unit Hiding Depth' WHERE name = 'opac.org_unit_hiding.depth';
UPDATE config.org_unit_setting_type SET grp = 'opac', label='Payment History Age Limit' WHERE name = 'opac.payment_history_age_limit';
UPDATE config.org_unit_setting_type SET grp = 'prog' WHERE name = 'org.bounced_emails';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Patron Opt-In Boundary' WHERE name = 'org.patron_opt_boundary';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Patron Opt-In Default' WHERE name = 'org.patron_opt_default';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'patron.password.use_phone';
UPDATE config.org_unit_setting_type SET grp = 'serial', label='Previous Issuance Copy Location' WHERE name = 'serial.prev_issuance_copy_location';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Work Log: Maximum Patrons Logged' WHERE name = 'ui.admin.patron_log.max_entries';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Work Log: Maximum Actions Logged' WHERE name = 'ui.admin.work_log.max_entries';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Horizontal layout for Volume/Copy Creator/Editor.' WHERE name = 'ui.cat.volume_copy_editor.horizontal';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Uncheck bills by default in the patron billing interface' WHERE name = 'ui.circ.billing.uncheck_bills_and_unfocus_payment_box';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Record In-House Use: Maximum # of uses allowed per entry.' WHERE name = 'ui.circ.in_house_use.entry_cap';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Record In-House Use: # of uses threshold for Are You Sure? dialog.' WHERE name = 'ui.circ.in_house_use.entry_warn';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.circ.patron_summary.horizontal';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.circ.show_billing_tab_on_bills';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Suppress popup-dialogs during check-in.' WHERE name = 'ui.circ.suppress_checkin_popups';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Button bar' WHERE name = 'ui.general.button_bar';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Default Hotkeyset' WHERE name = 'ui.general.hotkeyset';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Idle timeout' WHERE name = 'ui.general.idle_timeout';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Default Country for New Addresses in Patron Editor' WHERE name = 'ui.patron.default_country';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Default Ident Type for Patron Registration' WHERE name = 'ui.patron.default_ident_type';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Default level of patrons'' internet access' WHERE name = 'ui.patron.default_inet_access_level';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show active field on patron registration' WHERE name = 'ui.patron.edit.au.active.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest active field on patron registration' WHERE name = 'ui.patron.edit.au.active.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show alert_message field on patron registration' WHERE name = 'ui.patron.edit.au.alert_message.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest alert_message field on patron registration' WHERE name = 'ui.patron.edit.au.alert_message.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show alias field on patron registration' WHERE name = 'ui.patron.edit.au.alias.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest alias field on patron registration' WHERE name = 'ui.patron.edit.au.alias.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show barred field on patron registration' WHERE name = 'ui.patron.edit.au.barred.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest barred field on patron registration' WHERE name = 'ui.patron.edit.au.barred.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show claims_never_checked_out_count field on patron registration' WHERE name = 'ui.patron.edit.au.claims_never_checked_out_count.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest claims_never_checked_out_count field on patron registration' WHERE name = 'ui.patron.edit.au.claims_never_checked_out_count.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show claims_returned_count field on patron registration' WHERE name = 'ui.patron.edit.au.claims_returned_count.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest claims_returned_count field on patron registration' WHERE name = 'ui.patron.edit.au.claims_returned_count.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show calendar widget for dob field on patron registration' WHERE name = 'ui.patron.edit.au.dob.calendar';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require dob field on patron registration' WHERE name = 'ui.patron.edit.au.dob.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show dob field on patron registration' WHERE name = 'ui.patron.edit.au.dob.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest dob field on patron registration' WHERE name = 'ui.patron.edit.au.dob.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for email field on patron registration' WHERE name = 'ui.patron.edit.au.email.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for email field on patron registration' WHERE name = 'ui.patron.edit.au.email.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require email field on patron registration' WHERE name = 'ui.patron.edit.au.email.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show email field on patron registration' WHERE name = 'ui.patron.edit.au.email.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest email field on patron registration' WHERE name = 'ui.patron.edit.au.email.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show ident_value field on patron registration' WHERE name = 'ui.patron.edit.au.ident_value.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest ident_value field on patron registration' WHERE name = 'ui.patron.edit.au.ident_value.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show ident_value2 field on patron registration' WHERE name = 'ui.patron.edit.au.ident_value2.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest ident_value2 field on patron registration' WHERE name = 'ui.patron.edit.au.ident_value2.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show juvenile field on patron registration' WHERE name = 'ui.patron.edit.au.juvenile.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest juvenile field on patron registration' WHERE name = 'ui.patron.edit.au.juvenile.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show master_account field on patron registration' WHERE name = 'ui.patron.edit.au.master_account.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest master_account field on patron registration' WHERE name = 'ui.patron.edit.au.master_account.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show second_given_name field on patron registration' WHERE name = 'ui.patron.edit.au.second_given_name.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest second_given_name field on patron registration' WHERE name = 'ui.patron.edit.au.second_given_name.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show suffix field on patron registration' WHERE name = 'ui.patron.edit.au.suffix.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest suffix field on patron registration' WHERE name = 'ui.patron.edit.au.suffix.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require county field on patron registration' WHERE name = 'ui.patron.edit.aua.county.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for post_code field on patron registration' WHERE name = 'ui.patron.edit.aua.post_code.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for post_code field on patron registration' WHERE name = 'ui.patron.edit.aua.post_code.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Default showing suggested patron registration fields' WHERE name = 'ui.patron.edit.default_suggested';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for phone fields on patron registration' WHERE name = 'ui.patron.edit.phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for phone fields on patron registration' WHERE name = 'ui.patron.edit.phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require at least one address for Patron Registration' WHERE name = 'ui.patron.registration.require_address';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Cap results in Patron Search at this number.' WHERE name = 'ui.patron_search.result_cap';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require staff initials for entry/edit of item/patron/penalty notes/messages.' WHERE name = 'ui.staff.require_initials';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Unified Volume/Item Creator/Editor' WHERE name = 'ui.unified_volume_copy_editor';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='URL for remote directory containing list column settings.' WHERE name = 'url.remote_column_settings';



COMMIT;
