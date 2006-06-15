{

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
	package money::billable_transaction;
	
	money::billable_transaction->table( 'money.billable_xact' );
	money::billable_transaction->sequence( 'money.billable_xact_id_seq' );

	#---------------------------------------------------------------------
	package money::billing;
	
	money::billing->table( 'money.billing' );
	money::billing->sequence( 'money.billing_id_seq' );

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
	package money::work_payment;
	
	money::work_payment->table( 'money.work_payment' );
	money::work_payment->sequence( 'money.payment_id_seq' );

	#---------------------------------------------------------------------
	package money::forgive_payment;
	
	money::forgive_payment->table( 'money.forgive_payment' );
	money::forgive_payment->sequence( 'money.payment_id_seq' );

	#---------------------------------------------------------------------
	package money::open_billable_transaction_summary;
	
	money::open_billable_transaction_summary->table( 'money.open_billable_xact_summary' );

	#---------------------------------------------------------------------
	package money::billable_transaction_summary;
	
	money::billable_transaction_summary->table( 'money.billable_xact_with_void_summary' );

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
	package config::rules::recuring_fine;
	
	config::rules::recuring_fine->table( 'config.rule_recuring_fine' );
	config::rules::recuring_fine->sequence( 'config.rule_recuring_fine_id_seq' );
	
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
	package asset::copy_location;
	
	asset::copy_location->table( 'asset.copy_location' );
	asset::copy_location->sequence( 'asset.copy_location_id_seq' );

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
	package actor::profile;
	
	actor::profile->table( 'actor.profile' );
	actor::profile->sequence( 'actor.profile_id_seq' );
	
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
	package actor::stat_cat_entry_user_map;
	
	actor::stat_cat_entry_user_map->table( 'actor.stat_cat_entry_usr_map' );
	actor::stat_cat_entry_user_map->sequence( 'actor.stat_cat_entry_usr_map_id_seq' );
	
	#---------------------------------------------------------------------
	package actor::card;
	
	actor::card->table( 'actor.card' );
	actor::card->sequence( 'actor.card_id_seq' );

	#---------------------------------------------------------------------
	package actor::usr_note;
	
	actor::usr_note->table( 'actor.usr_note' );
	actor::usr_note->sequence( 'actor.usr_note_id_seq' );

	#---------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::metarecord;

	metabib::metarecord->table( 'metabib.metarecord' );
	metabib::metarecord->sequence( 'metabib.metarecord_id_seq' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.metarecord.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::metarecord',
	);


	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::title_field_entry;

	metabib::title_field_entry->table( 'metabib.title_field_entry' );
	metabib::title_field_entry->sequence( 'metabib.title_field_entry_id_seq' );
	metabib::title_field_entry->columns( 'FTS' => 'index_vector' );

#	metabib::title_field_entry->add_trigger(
#		before_create => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
#	);
#	metabib::title_field_entry->add_trigger(
#		before_update => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
#	);

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.title_field_entry.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::title_field_entry',
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::author_field_entry;

	metabib::author_field_entry->table( 'metabib.author_field_entry' );
	metabib::author_field_entry->sequence( 'metabib.author_field_entry_id_seq' );
	metabib::author_field_entry->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.author_field_entry.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::author_field_entry',
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::subject_field_entry;

	metabib::subject_field_entry->table( 'metabib.subject_field_entry' );
	metabib::subject_field_entry->sequence( 'metabib.subject_field_entry_id_seq' );
	metabib::subject_field_entry->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.subject_field_entry.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::subject_field_entry',
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::keyword_field_entry;

	metabib::keyword_field_entry->table( 'metabib.keyword_field_entry' );
	metabib::keyword_field_entry->sequence( 'metabib.keyword_field_entry_id_seq' );
	metabib::keyword_field_entry->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.keyword_field_entry.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::keyword_field_entry',
	);

	#-------------------------------------------------------------------------------
	package metabib::series_field_entry;

	metabib::series_field_entry->table( 'metabib.series_field_entry' );
	metabib::series_field_entry->sequence( 'metabib.series_field_entry_id_seq' );
	metabib::series_field_entry->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.series_field_entry.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::series_field_entry',
	);

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
	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.metarecord_source_map.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::metarecord_source_map',
	);


	#-------------------------------------------------------------------------------
	package authority::record_descriptor;

	authority::record_descriptor->table( 'authority.rec_descriptor' );
	authority::record_descriptor->sequence( 'authority.rec_descriptor_id_seq' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.authority.record_descriptor.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'authority::record_descriptor',
	);

	#-------------------------------------------------------------------------------
	package metabib::record_descriptor;

	metabib::record_descriptor->table( 'metabib.rec_descriptor' );
	metabib::record_descriptor->sequence( 'metabib.rec_descriptor_id_seq' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.record_descriptor.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::record_descriptor',
	);

	#-------------------------------------------------------------------------------


	#-------------------------------------------------------------------------------
	package authority::full_rec;

	authority::full_rec->table( 'authority.full_rec' );
	authority::full_rec->sequence( 'authority.full_rec_id_seq' );
	authority::full_rec->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.authority.full_rec.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'authority::full_rec',
	);


	#-------------------------------------------------------------------------------
	package metabib::full_rec;

	metabib::full_rec->table( 'metabib.full_rec' );
	metabib::full_rec->sequence( 'metabib.full_rec_id_seq' );
	metabib::full_rec->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.full_rec.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::full_rec',
	);


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

	package action::transit_copy;

	action::transit_copy->sequence( 'action.transit_copy_id_seq' );
	action::transit_copy->table('action.transit_copy');

	#-------------------------------------------------------------------------------

	package action::unfulfilled_hold_list;

	action::unfulfilled_hold_list->sequence( 'action.unfulfilled_hold_list_id_seq' );
	action::unfulfilled_hold_list->table('action.unfulfilled_hold_list');

	#-------------------------------------------------------------------------------

	package config::language_map;
	config::language_map->table('config.language_map');

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

1;
