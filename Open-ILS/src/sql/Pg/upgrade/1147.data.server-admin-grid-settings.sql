BEGIN;

SELECT evergreen.upgrade_deps_block_check('1147', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.server.config.rule_age_hold_protect', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.rule_age_hold_protect',
        'Grid Config: admin.server.config.rule_age_hold_protect',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.asset.stat_cat_sip_fields', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.asset.stat_cat_sip_fields',
        'Grid Config: admin.server.asset.stat_cat_sip_fields',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.actor.stat_cat_sip_fields', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.actor.stat_cat_sip_fields',
        'Grid Config: admin.server.actor.stat_cat_sip_fields',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.authority.browse_axis', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.authority.browse_axis',
        'Grid Config: admin.server.authority.browse_axis',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.authority.control_set', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.authority.control_set',
        'Grid Config: admin.server.authority.control_set',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.authority.heading_field', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.authority.heading_field',
        'Grid Config: admin.server.authority.heading_field',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.authority.thesaurus', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.authority.thesaurus',
        'Grid Config: admin.server.authority.thesaurus',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.best_hold_order', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.best_hold_order',
        'Grid Config: admin.server.config.best_hold_order',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.billing_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.billing_type',
        'Grid Config: admin.server.config.billing_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.asset.call_number_prefix', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.asset.call_number_prefix',
        'Grid Config: admin.server.asset.call_number_prefix',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.asset.call_number_suffix', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.asset.call_number_suffix',
        'Grid Config: admin.server.asset.call_number_suffix',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.rule_circ_duration', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.rule_circ_duration',
        'Grid Config: admin.server.config.rule_circ_duration',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.circ_limit_group', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.circ_limit_group',
        'Grid Config: admin.server.config.circ_limit_group',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.circ_matrix_weights', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.circ_matrix_weights',
        'Grid Config: admin.server.config.circ_matrix_weights',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.rule_max_fine', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.rule_max_fine',
        'Grid Config: admin.server.config.rule_max_fine',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.circ_modifier', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.circ_modifier',
        'Grid Config: admin.server.config.circ_modifier',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.copy_status', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.copy_status',
        'Grid Config: admin.server.config.copy_status',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.floating_group', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.floating_group',
        'Grid Config: admin.server.config.floating_group',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.global_flag', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.global_flag',
        'Grid Config: admin.server.config.global_flag',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.hard_due_date', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.hard_due_date',
        'Grid Config: admin.server.config.hard_due_date',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.hold_matrix_weights', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.hold_matrix_weights',
        'Grid Config: admin.server.config.hold_matrix_weights',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.vandelay.match_set', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.vandelay.match_set',
        'Grid Config: admin.server.vandelay.match_set',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.coded_value_map', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.coded_value_map',
        'Grid Config: admin.server.config.coded_value_map',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.vandelay.import_bib_trash_group', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.vandelay.import_bib_trash_group',
        'Grid Config: admin.server.vandelay.import_bib_trash_group',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.record_attr_definition', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.record_attr_definition',
        'Grid Config: admin.server.config.record_attr_definition',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_class', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_class',
        'Grid Config: admin.server.config.metabib_class',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_field_ts_map', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_field_ts_map',
        'Grid Config: admin.server.config.metabib_field_ts_map',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_field', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_field',
        'Grid Config: admin.server.config.metabib_field',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.permission.perm_list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.permission.perm_list',
        'Grid Config: admin.server.permission.perm_list',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.remote_account', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.remote_account',
        'Grid Config: admin.server.config.remote_account',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.sms_carrier', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.sms_carrier',
        'Grid Config: admin.server.config.sms_carrier',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.usr_activity_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.usr_activity_type',
        'Grid Config: admin.server.config.usr_activity_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.weight_assoc', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.weight_assoc',
        'Grid Config: admin.server.config.weight_assoc',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.z3950_index_field_map', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.z3950_index_field_map',
        'Grid Config: admin.server.config.z3950_index_field_map',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.z3950_source', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.z3950_source',
        'Grid Config: admin.server.config.z3950_source',
        'cwst', 'label'
    )
);

COMMIT;

