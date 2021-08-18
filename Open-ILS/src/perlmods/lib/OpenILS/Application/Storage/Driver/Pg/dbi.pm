{

    #-------------------------------------------------------------------------------
    package asset::copy_part_map;

    asset::copy_part_map->table( 'asset.copy_part_map' );
    asset::copy_part_map->sequence( 'asset.copy_part_map_id_seq' );

    #-------------------------------------------------------------------------------
    package biblio::monograph_part;

    biblio::monograph_part->table( 'biblio.monograph_part' );
    biblio::monograph_part->sequence( 'biblio.monograph_part_id_seq' );

    #-------------------------------------------------------------------------------
    package biblio::peer_bib_copy_map;

    biblio::peer_bib_copy_map->table( 'biblio.peer_bib_copy_map' );
    biblio::peer_bib_copy_map->sequence( 'biblio.peer_bib_copy_map_id_seq' );

    #-------------------------------------------------------------------------------
    package biblio::peer_type;

    biblio::peer_type->table( 'biblio.peer_type' );
    biblio::peer_type->sequence( 'biblio.peer_type_id_seq' );

    #-------------------------------------------------------------------------------
    package container::user_bucket;

    container::user_bucket->table( 'container.user_bucket' );
    container::user_bucket->sequence( 'container.user_bucket_id_seq' );

    #-------------------------------------------------------------------------------
    package container::user_bucket_item;

    container::user_bucket_item->table( 'container.user_bucket_item' );
    container::user_bucket_item->sequence( 'container.user_bucket_item_id_seq' );

    #-------------------------------------------------------------------------------
    package container::copy_bucket;

    container::copy_bucket->table( 'container.copy_bucket' );
    container::copy_bucket->sequence( 'container.copy_bucket_id_seq' );

    #-------------------------------------------------------------------------------
    package container::copy_bucket_item;

    container::copy_bucket_item->table( 'container.copy_bucket_item' );
    container::copy_bucket_item->sequence( 'container.copy_bucket_item_id_seq' );

    #-------------------------------------------------------------------------------
    package container::call_number_bucket;

    container::call_number_bucket->table( 'container.call_number_bucket' );
    container::call_number_bucket->sequence( 'container.call_number_bucket_id_seq' );

    #-------------------------------------------------------------------------------
    package container::call_number_bucket_item;

    container::call_number_bucket_item->table( 'container.call_number_bucket_item' );
    container::call_number_bucket_item->sequence( 'container.call_number_bucket_item_id_seq' );

    #-------------------------------------------------------------------------------
    package container::biblio_record_entry_bucket;

    container::biblio_record_entry_bucket->table( 'container.biblio_record_entry_bucket' );
    container::biblio_record_entry_bucket->sequence( 'container.biblio_record_entry_bucket_id_seq' );

    #-------------------------------------------------------------------------------
    package container::biblio_record_entry_bucket_item;

    container::biblio_record_entry_bucket_item->table( 'container.biblio_record_entry_bucket_item' );
    container::biblio_record_entry_bucket_item->sequence( 'container.biblio_record_entry_bucket_item_id_seq' );

    #---------------------------------------------------------------------
    package money::grocery;
    
    money::grocery->table( 'money.grocery' );
    money::grocery->sequence( 'money.billable_xact_id_seq' );

    #---------------------------------------------------------------------
    package money::collections_tracker;
    
    money::collections_tracker->table( 'money.collections_tracker' );
    money::collections_tracker->sequence( 'money.collections_tracker_id_seq' );

    #---------------------------------------------------------------------
    package money::billable_transaction;
    
    money::billable_transaction->table( 'money.billable_xact' );
    money::billable_transaction->sequence( 'money.billable_xact_id_seq' );

    #---------------------------------------------------------------------
    package money::billing;
    
    money::billing->table( 'money.billing' );
    money::billing->sequence( 'money.billing_id_seq' );

    #---------------------------------------------------------------------
    package money::desk_payment;
    
    money::desk_payment->table( 'money.desk_payment_view' );

    #---------------------------------------------------------------------
    package money::payment;
    
    money::payment->table( 'money.payment_view' );

    #---------------------------------------------------------------------
    package money::cash_payment;
    
    money::cash_payment->table( 'money.cash_payment' );
    money::cash_payment->sequence( 'money.payment_id_seq' );

    #---------------------------------------------------------------------
    package money::check_payment;
    
    money::check_payment->table( 'money.check_payment' );
    money::check_payment->sequence( 'money.payment_id_seq' );

    #---------------------------------------------------------------------
    package money::credit_payment;
    
    money::credit_payment->table( 'money.credit_payment' );
    money::credit_payment->sequence( 'money.payment_id_seq' );

    #---------------------------------------------------------------------
    package money::credit_card_payment;
    
    money::credit_card_payment->table( 'money.credit_card_payment' );
    money::credit_card_payment->sequence( 'money.payment_id_seq' );

    #---------------------------------------------------------------------
    package money::debit_card_payment;
    
    money::debit_card_payment->table( 'money.debit_card_payment' );
    money::debit_card_payment->sequence( 'money.payment_id_seq' );

    #---------------------------------------------------------------------
    package money::work_payment;
    
    money::work_payment->table( 'money.work_payment' );
    money::work_payment->sequence( 'money.payment_id_seq' );

    #---------------------------------------------------------------------
    package money::goods_payment;
    
    money::goods_payment->table( 'money.goods_payment' );
    money::goods_payment->sequence( 'money.payment_id_seq' );

    #---------------------------------------------------------------------
    package money::forgive_payment;
    
    money::forgive_payment->table( 'money.forgive_payment' );
    money::forgive_payment->sequence( 'money.payment_id_seq' );

    #---------------------------------------------------------------------
    package money::open_billable_transaction_summary;
    
    money::open_billable_transaction_summary->table( 'money.open_billable_xact_summary' );

    #---------------------------------------------------------------------
    package money::billable_transaction_summary;
    
    money::billable_transaction_summary->table( 'money.billable_xact_summary' );

    #---------------------------------------------------------------------
    package money::open_user_summary;
    
    money::open_user_summary->table( 'money.open_usr_summary' );

    #---------------------------------------------------------------------
    package money::user_summary;
    
    money::user_summary->table( 'money.usr_summary' );

    #---------------------------------------------------------------------
    package money::open_user_circulation_summary;
    
    money::open_user_circulation_summary->table( 'money.open_usr_circulation_summary' );

    #---------------------------------------------------------------------
    package money::user_circulation_summary;
    
    money::user_circulation_summary->table( 'money.usr_circulation_summary' );

    #---------------------------------------------------------------------
    package action::circulation;
    
    action::circulation->table( 'action.circulation' );
    action::circulation->sequence( 'money.billable_xact_id_seq' );

    #---------------------------------------------------------------------
    package booking::resource_type;
    
    booking::resource_type->table( 'booking.resource_type' );
    booking::resource_type->sequence( 'booking.resource_type_id_seq' );

    #---------------------------------------------------------------------
    package booking::resource;
    
    booking::resource->table( 'booking.resource' );
    booking::resource->sequence( 'booking.resource_id_seq' );

    #---------------------------------------------------------------------
    package booking::reservation;
    
    booking::reservation->table( 'booking.reservation' );
    booking::reservation->sequence( 'money.billable_xact_id_seq' );

    #---------------------------------------------------------------------
    package booking::reservation_attr_value_map;
    
    booking::reservation_attr_value_map->table( 'booking.reservation_attr_value_map' );
    booking::reservation_attr_value_map->sequence( 'booking.reservation_attr_value_map_id_seq' );

    #---------------------------------------------------------------------
    package booking::resource_attr_map;
    
    booking::resource_attr_map->table( 'booking.resource_attr_map' );
    booking::resource_attr_map->sequence( 'booking.resource_attr_map_id_seq' );

    #---------------------------------------------------------------------
    package action::non_cat_in_house_use;
    
    action::non_cat_in_house_use->table( 'action.non_cat_in_house_use' );
    action::non_cat_in_house_use->sequence( 'action.non_cat_in_house_use_id_seq' );

    #---------------------------------------------------------------------
    package action::in_house_use;
    
    action::in_house_use->table( 'action.in_house_use' );
    action::in_house_use->sequence( 'action.in_house_use_id_seq' );

    #---------------------------------------------------------------------
    package action::non_cataloged_circulation;
    
    action::non_cataloged_circulation->table( 'action.non_cataloged_circulation' );
    action::non_cataloged_circulation->sequence( 'action.non_cataloged_circulation_id_seq' );

    #---------------------------------------------------------------------
    package action::open_circulation;
    
    action::open_circulation->table( 'action.open_circulation' );

    #---------------------------------------------------------------------
    package action::survey;
    
    action::survey->table( 'action.survey' );
    action::survey->sequence( 'action.survey_id_seq' );
    
    #---------------------------------------------------------------------
    package action::survey_question;
    
    action::survey_question->table( 'action.survey_question' );
    action::survey_question->sequence( 'action.survey_question_id_seq' );
    
    #---------------------------------------------------------------------
    package action::survey_answer;
    
    action::survey_answer->table( 'action.survey_answer' );
    action::survey_answer->sequence( 'action.survey_answer_id_seq' );
    
    #---------------------------------------------------------------------
    package action::survey_response;
    
    action::survey_response->table( 'action.survey_response' );
    action::survey_response->sequence( 'action.survey_response_id_seq' );
    
    #---------------------------------------------------------------------
    package config::non_cataloged_type;
    
    config::non_cataloged_type->table( 'config.non_cataloged_type' );
    config::non_cataloged_type->sequence( 'config.non_cataloged_type_id_seq' );

    #---------------------------------------------------------------------
    package config::copy_status;
    
    config::copy_status->table( 'config.copy_status' );
    config::copy_status->sequence( 'config.copy_status_id_seq' );

    #---------------------------------------------------------------------
    package config::rules::circ_duration;
    
    config::rules::circ_duration->table( 'config.rule_circ_duration' );
    config::rules::circ_duration->sequence( 'config.rule_circ_duration_id_seq' );
    
    #---------------------------------------------------------------------
    package config::rules::age_hold_protect;
    
    config::rules::age_hold_protect->table( 'config.rule_age_hold_protect' );
    config::rules::age_hold_protect->sequence( 'config.rule_age_hold_protect_id_seq' );
    
    #---------------------------------------------------------------------
    package config::rules::max_fine;
    
    config::rules::max_fine->table( 'config.rule_max_fine' );
    config::rules::max_fine->sequence( 'config.rule_max_fine_id_seq' );
    
    #---------------------------------------------------------------------
    package config::rules::recurring_fine;
    
    config::rules::recurring_fine->table( 'config.rule_recurring_fine' );
    config::rules::recurring_fine->sequence( 'config.rule_recurring_fine_id_seq' );
    
    #---------------------------------------------------------------------
    package config::net_access_level;
    
    config::net_access_level->table( 'config.net_access_level' );
    config::net_access_level->sequence( 'config.net_access_level_id_seq' );
    
    #---------------------------------------------------------------------
    package config::standing;
    
    config::standing->table( 'config.standing' );
    config::standing->sequence( 'config.standing_id_seq' );
    
    #---------------------------------------------------------------------
    package config::metabib_field;
    
    config::metabib_field->table( 'config.metabib_field' );
    config::metabib_field->sequence( 'config.metabib_field_id_seq' );
    
    #---------------------------------------------------------------------
    package config::bib_source;
    
    config::bib_source->table( 'config.bib_source' );
    config::bib_source->sequence( 'config.bib_source_id_seq' );
    
    #---------------------------------------------------------------------
    package config::identification_type;
    
    config::identification_type->table( 'config.identification_type' );
    config::identification_type->sequence( 'config.identification_type_id_seq' );
    
    #---------------------------------------------------------------------
    package asset::call_number_note;
    
    asset::call_number_note->table( 'asset.call_number_note' );
    asset::call_number_note->sequence( 'asset.call_number_note_id_seq' );
    
    #---------------------------------------------------------------------
    package asset::copy_note;
    
    asset::copy_note->table( 'asset.copy_note' );
    asset::copy_note->sequence( 'asset.copy_note_id_seq' );

    #---------------------------------------------------------------------
    package asset::call_number;
    
    asset::call_number->table( 'asset.call_number' );
    asset::call_number->sequence( 'asset.call_number_id_seq' );
    
    #---------------------------------------------------------------------
    package asset::call_number_suffix;
    
    asset::call_number_suffix->table( 'asset.call_number_suffix' );
    asset::call_number_suffix->sequence( 'asset.call_number_suffix_id_seq' );

    #---------------------------------------------------------------------
    package asset::call_number_prefix;
    
    asset::call_number_prefix->table( 'asset.call_number_prefix' );
    asset::call_number_prefix->sequence( 'asset.call_number_prefix_id_seq' );

    #---------------------------------------------------------------------
    package asset::call_number_class;
    
    asset::call_number_class->table( 'asset.call_number_class' );
    asset::call_number_class->sequence( 'asset.call_number_class_id_seq' );
    
    #---------------------------------------------------------------------
    package asset::copy_location_order;
    
    asset::copy_location_order->table( 'asset.copy_location_order' );
    asset::copy_location_order->sequence( 'asset.copy_location_order_id_seq' );

    #---------------------------------------------------------------------
    package asset::copy_location;
    
    asset::copy_location->table( 'asset.copy_location' );
    asset::copy_location->sequence( 'asset.copy_location_id_seq' );

    #---------------------------------------------------------------------
    package asset::copy_location_group;
    
    asset::copy_location_group->table( 'asset.copy_location_group' );
    asset::copy_location_group->sequence( 'asset.copy_location_group_id_seq' );

    #---------------------------------------------------------------------
    package asset::copy;
    
    asset::copy->table( 'asset.copy' );
    asset::copy->sequence( 'asset.copy_id_seq' );

    #---------------------------------------------------------------------
    package asset::stat_cat;
    
    asset::stat_cat->table( 'asset.stat_cat' );
    asset::stat_cat->sequence( 'asset.stat_cat_id_seq' );
    
    #---------------------------------------------------------------------
    package asset::stat_cat_entry;
    
    asset::stat_cat_entry->table( 'asset.stat_cat_entry' );
    asset::stat_cat_entry->sequence( 'asset.stat_cat_entry_id_seq' );
    
    #---------------------------------------------------------------------
    package asset::stat_cat_entry_copy_map;
    
    asset::stat_cat_entry_copy_map->table( 'asset.stat_cat_entry_copy_map' );
    asset::stat_cat_entry_copy_map->sequence( 'asset.stat_cat_entry_copy_map_id_seq' );
    
    #---------------------------------------------------------------------
    package authority::record_entry;
    
    authority::record_entry->table( 'authority.record_entry' );
    authority::record_entry->sequence( 'authority.record_entry_id_seq' );

    #---------------------------------------------------------------------
    package biblio::record_entry;
    
    biblio::record_entry->table( 'biblio.record_entry' );
    biblio::record_entry->sequence( 'biblio.record_entry_id_seq' );

    #---------------------------------------------------------------------
    #package biblio::record_marc;
    #
    #biblio::record_marc->table( 'biblio.record_marc' );
    #biblio::record_marc->sequence( 'biblio.record_marc_id_seq' );
    #
    #---------------------------------------------------------------------
    package authority::record_note;
    
    authority::record_note->table( 'authority.record_note' );
    authority::record_note->sequence( 'authority.record_note_id_seq' );

    #---------------------------------------------------------------------
    package biblio::record_note;
    
    biblio::record_note->table( 'biblio.record_note' );
    biblio::record_note->sequence( 'biblio.record_note_id_seq' );
    
    #---------------------------------------------------------------------
    package actor::workstation;
    
    actor::workstation->table( 'actor.workstation' );
    actor::workstation->sequence( 'actor.workstation_id_seq' );

    #---------------------------------------------------------------------
    package actor::user;
    
    actor::user->table( 'actor.usr' );
    actor::user->sequence( 'actor.usr_id_seq' );

    #---------------------------------------------------------------------
    package actor::org_unit::closed_date;
    
    actor::org_unit::closed_date->table( 'actor.org_unit_closed' );
    actor::org_unit::closed_date->sequence( 'actor.org_unit_closed_id_seq' );

    #---------------------------------------------------------------------
    package actor::org_unit_setting;
    
    actor::org_unit_setting->table( 'actor.org_unit_setting' );
    actor::org_unit_setting->sequence( 'actor.org_unit_setting_id_seq' );

    #---------------------------------------------------------------------
    package actor::user_standing_penalty;
    
    actor::user_standing_penalty->table( 'actor.usr_standing_penalty' );
    actor::user_standing_penalty->sequence( 'actor.usr_standing_penalty_id_seq' );

    #---------------------------------------------------------------------
    package actor::user_setting;
    
    actor::user_setting->table( 'actor.usr_setting' );
    actor::user_setting->sequence( 'actor.usr_setting_id_seq' );

    #---------------------------------------------------------------------
    package actor::user_address;
    
    actor::user_address->table( 'actor.usr_address' );
    actor::user_address->sequence( 'actor.usr_address_id_seq' );

    #---------------------------------------------------------------------
    package actor::org_address;
    
    actor::org_address->table( 'actor.org_address' );
    actor::org_address->sequence( 'actor.org_address_id_seq' );
    
    #---------------------------------------------------------------------
    package actor::usr_org_unit_opt_in;
    
    actor::usr_org_unit_opt_in->table( 'actor.usr_org_unit_opt_in' );
    actor::usr_org_unit_opt_in->sequence( 'actor.usr_org_unit_opt_in_id_seq' );

    #---------------------------------------------------------------------
    package actor::org_unit_proximity;
    
    actor::org_unit_proximity->table( 'actor.org_unit_proximity' );
    actor::org_unit_proximity->sequence( 'actor.org_unit_proximity_id_seq' );

    #---------------------------------------------------------------------
    package actor::org_unit_type;
    
    actor::org_unit_type->table( 'actor.org_unit_type' );
    actor::org_unit_type->sequence( 'actor.org_unit_type_id_seq' );

    #---------------------------------------------------------------------
    package actor::org_unit::hours_of_operation;
    
    actor::org_unit::hours_of_operation->table( 'actor.hours_of_operation' );

    #---------------------------------------------------------------------
    package actor::org_unit;
    
    actor::org_unit->table( 'actor.org_unit' );
    actor::org_unit->sequence( 'actor.org_unit_id_seq' );

    #---------------------------------------------------------------------
    package actor::stat_cat;
    
    actor::stat_cat->table( 'actor.stat_cat' );
    actor::stat_cat->sequence( 'actor.stat_cat_id_seq' );
    
    #---------------------------------------------------------------------
    package actor::stat_cat_entry;
    
    actor::stat_cat_entry->table( 'actor.stat_cat_entry' );
    actor::stat_cat_entry->sequence( 'actor.stat_cat_entry_id_seq' );
    
    #---------------------------------------------------------------------
    package actor::stat_cat_entry_default;
    
    actor::stat_cat_entry_default->table( 'actor.stat_cat_entry_default' );
    actor::stat_cat_entry_default->sequence( 'actor.stat_cat_entry_default_id_seq' );

    #---------------------------------------------------------------------
    package actor::stat_cat_entry_user_map;
    
    actor::stat_cat_entry_user_map->table( 'actor.stat_cat_entry_usr_map' );
    actor::stat_cat_entry_user_map->sequence( 'actor.stat_cat_entry_usr_map_id_seq' );
    
    #---------------------------------------------------------------------
    package actor::card;
    
    actor::card->table( 'actor.card' );
    actor::card->sequence( 'actor.card_id_seq' );

    #---------------------------------------------------------------------
    package actor::usr_message;
    
    actor::usr_message->table( 'actor.usr_message' );
    actor::usr_message->sequence( 'actor.usr_message_id_seq' );

    #---------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    package metabib::metarecord;

    metabib::metarecord->table( 'metabib.metarecord' );
    metabib::metarecord->sequence( 'metabib.metarecord_id_seq' );


    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    package metabib::identifier_field_entry;

    metabib::identifier_field_entry->table( 'metabib.identifier_field_entry' );
    metabib::identifier_field_entry->sequence( 'metabib.identifier_field_entry_id_seq' );
    metabib::identifier_field_entry->columns( 'FTS' => 'index_vector' );

    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    package metabib::title_field_entry;

    metabib::title_field_entry->table( 'metabib.title_field_entry' );
    metabib::title_field_entry->sequence( 'metabib.title_field_entry_id_seq' );
    metabib::title_field_entry->columns( 'FTS' => 'index_vector' );

#   metabib::title_field_entry->add_trigger(
#       before_create => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
#   );
#   metabib::title_field_entry->add_trigger(
#       before_update => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
#   );

    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    package metabib::author_field_entry;

    metabib::author_field_entry->table( 'metabib.author_field_entry' );
    metabib::author_field_entry->sequence( 'metabib.author_field_entry_id_seq' );
    metabib::author_field_entry->columns( 'FTS' => 'index_vector' );

    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    package metabib::subject_field_entry;

    metabib::subject_field_entry->table( 'metabib.subject_field_entry' );
    metabib::subject_field_entry->sequence( 'metabib.subject_field_entry_id_seq' );
    metabib::subject_field_entry->columns( 'FTS' => 'index_vector' );

    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    package metabib::keyword_field_entry;

    metabib::keyword_field_entry->table( 'metabib.keyword_field_entry' );
    metabib::keyword_field_entry->sequence( 'metabib.keyword_field_entry_id_seq' );
    metabib::keyword_field_entry->columns( 'FTS' => 'index_vector' );

    #-------------------------------------------------------------------------------
    package metabib::series_field_entry;

    metabib::series_field_entry->table( 'metabib.series_field_entry' );
    metabib::series_field_entry->sequence( 'metabib.series_field_entry_id_seq' );
    metabib::series_field_entry->columns( 'FTS' => 'index_vector' );

    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    #package metabib::title_field_entry_source_map;

    #metabib::title_field_entry_source_map->table( 'metabib.title_field_entry_source_map' );

    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    #package metabib::author_field_entry_source_map;

    #metabib::author_field_entry_source_map->table( 'metabib.author_field_entry_source_map' );

    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    #package metabib::subject_field_entry_source_map;

    #metabib::subject_field_entry_source_map->table( 'metabib.subject_field_entry_source_map' );

    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    #package metabib::keyword_field_entry_source_map;

    #metabib::keyword_field_entry_source_map->table( 'metabib.keyword_field_entry_source_map' );

    #-------------------------------------------------------------------------------

    #-------------------------------------------------------------------------------
    package metabib::metarecord_source_map;

    metabib::metarecord_source_map->table( 'metabib.metarecord_source_map' );
    metabib::metarecord_source_map->sequence( 'metabib.metarecord_source_map_id_seq' );

    #-------------------------------------------------------------------------------
    package authority::record_descriptor;

    authority::record_descriptor->table( 'authority.rec_descriptor' );
    authority::record_descriptor->sequence( 'authority.rec_descriptor_id_seq' );

    #-------------------------------------------------------------------------------
    package metabib::record_descriptor;

    metabib::record_descriptor->table( 'metabib.rec_descriptor' );
    metabib::record_descriptor->sequence( 'metabib.rec_descriptor_id_seq' );

    #-------------------------------------------------------------------------------


    #-------------------------------------------------------------------------------
    package authority::full_rec;

    authority::full_rec->table( 'authority.full_rec' );
    authority::full_rec->sequence( 'authority.full_rec_id_seq' );
    authority::full_rec->columns( 'FTS' => 'index_vector' );

    #-------------------------------------------------------------------------------
    package metabib::full_rec;

    metabib::full_rec->table( 'metabib.full_rec' );
    metabib::full_rec->sequence( 'metabib.full_rec_id_seq' );
    metabib::full_rec->columns( 'FTS' => 'index_vector' );

    #-------------------------------------------------------------------------------

    package permission::perm_list;

    permission::perm_list->sequence( 'permission.perm_list_id_seq' );
    permission::perm_list->table('permission.perm_list');

    #-------------------------------------------------------------------------------

    package permission::grp_tree;

    permission::grp_tree->sequence( 'permission.grp_tree_id_seq' );
    permission::grp_tree->table('permission.grp_tree');

    #-------------------------------------------------------------------------------

    package permission::usr_grp_map;

    permission::usr_grp_map->sequence( 'permission.usr_grp_map_id_seq' );
    permission::usr_grp_map->table('permission.usr_grp_map');

    #-------------------------------------------------------------------------------

    package permission::usr_work_ou_map;
    permission::usr_work_ou_map->sequence('permission.usr_work_ou_map_id_seq');
    permission::usr_work_ou_map->table('permission.usr_work_ou_map');

    #-------------------------------------------------------------------------------

    package permission::usr_perm_map;

    permission::usr_perm_map->sequence( 'permission.usr_perm_map_id_seq' );
    permission::usr_perm_map->table('permission.usr_perm_map');

    #-------------------------------------------------------------------------------

    package permission::grp_perm_map;

    permission::grp_perm_map->sequence( 'permission.grp_perm_map_id_seq' );
    permission::grp_perm_map->table('permission.grp_perm_map');

    #-------------------------------------------------------------------------------

    package action::hold_request;

    action::hold_request->sequence( 'action.hold_request_id_seq' );
    action::hold_request->table('action.hold_request');

    #-------------------------------------------------------------------------------

    package action::hold_request_reset_reason_entry;

    action::hold_request_reset_reason_entry->sequence( 'action.hold_request_reset_reason_entry_id_seq' );
    action::hold_request_reset_reason_entry->table('action.hold_request_reset_reason_entry');

    #-------------------------------------------------------------------------------

    package action::hold_request_reset_reason;

    action::hold_request_reset_reason->sequence( 'action.hold_request_reset_reason_id_seq' );
    action::hold_request_reset_reason->table('action.hold_request_reset_reason');

    #-------------------------------------------------------------------------------

    package action::hold_notification;

    action::hold_notification->sequence( 'action.hold_notification_id_seq' );
    action::hold_notification->table('action.hold_notification');

    #-------------------------------------------------------------------------------

    package action::hold_copy_map;

    action::hold_copy_map->sequence( 'action.hold_copy_map_id_seq' );
    action::hold_copy_map->table('action.hold_copy_map');

    #-------------------------------------------------------------------------------

    package action::hold_transit_copy;

    action::hold_transit_copy->sequence( 'action.transit_copy_id_seq' );
    action::hold_transit_copy->table('action.hold_transit_copy');

    #-------------------------------------------------------------------------------

    package action::reservation_transit_copy;

    action::reservation_transit_copy->sequence( 'action.transit_copy_id_seq' );
    action::reservation_transit_copy->table('action.reservation_transit_copy');

    #-------------------------------------------------------------------------------

    package action::transit_copy;

    action::transit_copy->sequence( 'action.transit_copy_id_seq' );
    action::transit_copy->table('action.transit_copy');

    #-------------------------------------------------------------------------------

    package action::unfulfilled_hold_list;

    action::unfulfilled_hold_list->sequence( 'action.unfulfilled_hold_list_id_seq' );
    action::unfulfilled_hold_list->table('action.unfulfilled_hold_list');

    #-------------------------------------------------------------------------------

    package serial::subscription;

    serial::subscription->sequence( 'serial.subscription_id_seq' );
    serial::subscription->table('serial.subscription');

    #-------------------------------------------------------------------------------

    package serial::issuance;

    serial::issuance->sequence( 'serial.issuance_id_seq' );
    serial::issuance->table('serial.issuance');

    #-------------------------------------------------------------------------------

    package serial::item;

    serial::item->sequence( 'serial.item_id_seq' );
    serial::item->table('serial.item');

    #-------------------------------------------------------------------------------

    package serial::unit;

    serial::unit->sequence( 'asset.copy_id_seq' );
    serial::unit->table('serial.unit');

    #-------------------------------------------------------------------------------

    package config::language_map;
    config::language_map->table('config.language_map');

    #-------------------------------------------------------------------------------

    package config::i18n_locale;
    config::i18n_locale->table('config.i18n_locale');

    #-------------------------------------------------------------------------------

    package config::i18n_core;
    config::i18n_core->sequence( 'config.i18n_core_id_seq' );
    config::i18n_core->table('config.i18n_core');

    #-------------------------------------------------------------------------------

    package config::item_form_map;
    config::item_form_map->table('config.item_form_map');

    #-------------------------------------------------------------------------------

    package config::lit_form_map;
    config::lit_form_map->table('config.lit_form_map');

    #-------------------------------------------------------------------------------

    package config::item_type_map;
    config::item_type_map->table('config.item_type_map');

    #-------------------------------------------------------------------------------
    package config::audience_map;
    config::audience_map->table('config.audience_map');

    #-------------------------------------------------------------------------------


}

for my $class ( qw/
            biblio::record_entry
            metabib::metarecord
            metabib::title_field_entry
            metabib::author_field_entry
            metabib::subject_field_entry
            metabib::keyword_field_entry
            metabib::series_field_entry
            metabib::metarecord_source_map
            metabib::record_descriptor
            metabib::full_rec
            authority::record_descriptor
            authority::full_rec
        / ) {

    (my $method_class = $class) =~ s/::/./go;

    for my $type ( qw/create create_start create_push create_finish/ ) {
        my ($name,$part) = split('_', $type);

        my $apiname = "open-ils.storage.direct.$method_class.batch.$name";
        $apiname .= ".$part" if ($part);

        OpenILS::Application::Storage->register_method(
            api_name    => $apiname,
            method      => "copy_$type",
            api_level   => 1,
            'package'   => 'OpenILS::Application::Storage',
            cdbi        => $class,
        );
    }
}


1;
