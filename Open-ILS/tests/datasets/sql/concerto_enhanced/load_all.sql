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

\echo loading acq.acq_lineitem_history
\i acq.acq_lineitem_history.sql

\echo loading acq.acq_purchase_order_history
\i acq.acq_purchase_order_history.sql

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

\echo loading permission.perm_list
\i permission.perm_list.sql

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

COMMIT;
