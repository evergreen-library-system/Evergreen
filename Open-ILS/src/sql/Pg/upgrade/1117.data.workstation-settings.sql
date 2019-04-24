BEGIN;

SELECT evergreen.upgrade_deps_block_check('1117', :eg_version);

INSERT INTO permission.perm_list (id, code, description) VALUES
 (608, 'APPLY_WORKSTATION_SETTING',
   oils_i18n_gettext(608, 'APPLY_WORKSTATION_SETTING', 'ppl', 'description'));

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.circ.checkin.no_precat_alert', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.no_precat_alert',
        'Checkin: Ignore Precataloged Items',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.noop', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.noop',
        'Checkin: Suppress Holds and Transits',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.void_overdues', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.void_overdues',
        'Checkin: Amnesty Mode',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.auto_print_holds_transits', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.auto_print_holds_transits',
        'Checkin: Auto-Print Holds and Transits',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.clear_expired', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.clear_expired',
        'Checkin: Clear Holds Shelf',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.retarget_holds', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.retarget_holds',
        'Checkin: Retarget Local Holds',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.retarget_holds_all', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.retarget_holds_all',
        'Checkin: Retarget All Statuses',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.hold_as_transit', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.hold_as_transit',
        'Checkin: Capture Local Holds as Transits',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.manual_float', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.manual_float',
        'Checkin: Manual Floating Active',
        'cwst', 'label'
    )
), (
    'eg.circ.patron.summary.collapse', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.patron.summary.collapse',
        'Collaps Patron Summary Display',
        'cwst', 'label'
    )
), (
    'circ.bills.receiptonpay', 'circ', 'bool',
    oils_i18n_gettext(
        'circ.bills.receiptonpay',
        'Print Receipt On Payment',
        'cwst', 'label'
    )
), (
    'circ.renew.strict_barcode', 'circ', 'bool',
    oils_i18n_gettext(
        'circ.renew.strict_barcode',
        'Renew: Strict Barcode',
        'cwst', 'label'
    )
), (
    'circ.checkin.strict_barcode', 'circ', 'bool',
    oils_i18n_gettext(
        'circ.checkin.strict_barcode',
        'Checkin: Strict Barcode',
        'cwst', 'label'
    )
), (
    'circ.checkout.strict_barcode', 'circ', 'bool',
    oils_i18n_gettext(
        'circ.checkout.strict_barcode',
        'Checkout: Strict Barcode',
        'cwst', 'label'
    )
), (
    'cat.holdings_show_copies', 'cat', 'bool',
    oils_i18n_gettext(
        'cat.holdings_show_copies',
        'Holdings View Show Copies',
        'cwst', 'label'
    )
), (
    'cat.holdings_show_empty', 'cat', 'bool',
    oils_i18n_gettext(
        'cat.holdings_show_empty',
        'Holdings View Show Empty Volumes',
        'cwst', 'label'
    )
), (
    'cat.holdings_show_empty_org', 'cat', 'bool',
    oils_i18n_gettext(
        'cat.holdings_show_empty_org',
        'Holdings View Show Empty Orgs',
        'cwst', 'label'
    )
), (
    'cat.holdings_show_vols', 'cat', 'bool',
    oils_i18n_gettext(
        'cat.holdings_show_vols',
        'Holdings View Show Volumes',
        'cwst', 'label'
    )
), (
    'cat.copy.defaults', 'cat', 'object',
    oils_i18n_gettext(
        'cat.copy.defaults',
        'Copy Edit Default Values',
        'cwst', 'label'
    )
), (
    'cat.printlabels.default_template', 'cat', 'string',
    oils_i18n_gettext(
        'cat.printlabels.default_template',
        'Print Label Default Template',
        'cwst', 'label'
    )
), (
    'cat.printlabels.templates', 'cat', 'object',
    oils_i18n_gettext(
        'cat.printlabels.templates',
        'Print Label Templates',
        'cwst', 'label'
    )
), (
    'eg.circ.patron.search.include_inactive', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.patron.search.include_inactive',
        'Patron Search Include Inactive',
        'cwst', 'label'
    )
), (
    'eg.circ.patron.search.show_extras', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.patron.search.show_extras',
        'Patron Search Show Extra Search Options',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.checkin.checkin', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.checkin.checkin',
        'Grid Config: circ.checkin.checkin',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.checkin.capture', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.checkin.capture',
        'Grid Config: circ.checkin.capture',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.copy_tag_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.copy_tag_type',
        'Grid Config: admin.server.config.copy_tag_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_field_virtual_map.grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_field_virtual_map.grid',
        'Grid Config: admin.server.config.metabib_field_virtual_map.grid',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_field.grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_field.grid',
        'Grid Config: admin.server.config.metabib_field.grid',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.marc_field', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.marc_field',
        'Grid Config: admin.server.config.marc_field',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.asset.copy_tag', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.asset.copy_tag',
        'Grid Config: admin.server.asset.copy_tag',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.circ.neg_balance_users', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.circ.neg_balance_users',
        'Grid Config: admin.local.circ.neg_balance_users',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.rating.badge', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.rating.badge',
        'Grid Config: admin.local.rating.badge',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.workstation.work_log', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.workstation.work_log',
        'Grid Config: admin.workstation.work_log',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.workstation.patron_log', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.workstation.patron_log',
        'Grid Config: admin.workstation.patron_log',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.serials.pattern_template', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.serials.pattern_template',
        'Grid Config: admin.serials.pattern_template',
        'cwst', 'label'
    )
), (
    'eg.grid.serials.copy_templates', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.serials.copy_templates',
        'Grid Config: serials.copy_templates',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.record_overlay.holdings', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.record_overlay.holdings',
        'Grid Config: cat.record_overlay.holdings',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.record.search', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.record.search',
        'Grid Config: cat.bucket.record.search',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.record.view', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.record.view',
        'Grid Config: cat.bucket.record.view',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.record.pending', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.record.pending',
        'Grid Config: cat.bucket.record.pending',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.copy.view', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.copy.view',
        'Grid Config: cat.bucket.copy.view',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.copy.pending', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.copy.pending',
        'Grid Config: cat.bucket.copy.pending',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.items', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.items',
        'Grid Config: cat.items',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.volcopy.copies', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.volcopy.copies',
        'Grid Config: cat.volcopy.copies',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.volcopy.copies.complete', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.volcopy.copies.complete',
        'Grid Config: cat.volcopy.copies.complete',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.peer_bibs', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.peer_bibs',
        'Grid Config: cat.peer_bibs',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.catalog.holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.catalog.holds',
        'Grid Config: cat.catalog.holds',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.holdings', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.holdings',
        'Grid Config: cat.holdings',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.z3950_results', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.z3950_results',
        'Grid Config: cat.z3950_results',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.holds.shelf', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.holds.shelf',
        'Grid Config: circ.holds.shelf',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.holds.pull', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.holds.pull',
        'Grid Config: circ.holds.pull',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.in_house_use', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.in_house_use',
        'Grid Config: circ.in_house_use',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.renew', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.renew',
        'Grid Config: circ.renew',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.transits.list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.transits.list',
        'Grid Config: circ.transits.list',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.holds',
        'Grid Config: circ.patron.holds',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.pending_patrons.list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.pending_patrons.list',
        'Grid Config: circ.pending_patrons.list',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.items_out.noncat', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.items_out.noncat',
        'Grid Config: circ.patron.items_out.noncat',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.items_out', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.items_out',
        'Grid Config: circ.patron.items_out',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.billhistory_payments', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.billhistory_payments',
        'Grid Config: circ.patron.billhistory_payments',
        'cwst', 'label'
    )
), (
    'eg.grid.user.bucket.view', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.user.bucket.view',
        'Grid Config: user.bucket.view',
        'cwst', 'label'
    )
), (
    'eg.grid.user.bucket.pending', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.user.bucket.pending',
        'Grid Config: user.bucket.pending',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.staff_messages', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.staff_messages',
        'Grid Config: circ.patron.staff_messages',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.archived_messages', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.archived_messages',
        'Grid Config: circ.patron.archived_messages',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.bills', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.bills',
        'Grid Config: circ.patron.bills',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.checkout', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.checkout',
        'Grid Config: circ.patron.checkout',
        'cwst', 'label'
    )
), (
    'eg.grid.serials.mfhd_grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.serials.mfhd_grid',
        'Grid Config: serials.mfhd_grid',
        'cwst', 'label'
    )
), (
    'eg.grid.serials.view_item_grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.serials.view_item_grid',
        'Grid Config: serials.view_item_grid',
        'cwst', 'label'
    )
), (
    'eg.grid.serials.dist_stream_grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.serials.dist_stream_grid',
        'Grid Config: serials.dist_stream_grid',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.search', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.search',
        'Grid Config: circ.patron.search',
        'cwst', 'label'
    )
), (
    'eg.cat.record.summary.collapse', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.cat.record.summary.collapse',
        'Collapse Bib Record Summary',
        'cwst', 'label'
    )
), (
    'cat.marcedit.flateditor', 'gui', 'bool',
    oils_i18n_gettext(
        'cat.marcedit.flateditor',
        'Use Flat MARC Editor',
        'cwst', 'label'
    )
), (
    'cat.marcedit.stack_subfields', 'gui', 'bool',
    oils_i18n_gettext(
        'cat.marcedit.stack_subfields',
        'MARC Editor Stack Subfields',
        'cwst', 'label'
    )
), (
    'eg.offline.print_receipt', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.offline.print_receipt',
        'Offline Print Receipt',
        'cwst', 'label'
    )
), (
    'eg.offline.strict_barcode', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.offline.strict_barcode',
        'Offline Use Strict Barcode',
        'cwst', 'label'
    )
), (
    'cat.default_bib_marc_template', 'gui', 'string',
    oils_i18n_gettext(
        'cat.default_bib_marc_template',
        'Default MARC Template',
        'cwst', 'label'
    )
), (
    'eg.audio.disable', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.audio.disable',
        'Disable Staff Client Notification Audio',
        'cwst', 'label'
    )
), (
    'eg.search.adv_pane', 'gui', 'string',
    oils_i18n_gettext(
        'eg.search.adv_pane',
        'Catalog Advanced Search Default Pane',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.bills_current', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.bills_current',
        'Print Template Context: bills_current',
        'cwst', 'label'
    )
), (
    'eg.print.template.bills_current', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.bills_current',
        'Print Template: bills_current',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.bills_historical', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.bills_historical',
        'Print Template Context: bills_historical',
        'cwst', 'label'
    )
), (
    'eg.print.template.bills_historical', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.bills_historical',
        'Print Template: bills_historical',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.bill_payment', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.bill_payment',
        'Print Template Context: bill_payment',
        'cwst', 'label'
    )
), (
    'eg.print.template.bill_payment', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.bill_payment',
        'Print Template: bill_payment',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.checkin', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.checkin',
        'Print Template Context: checkin',
        'cwst', 'label'
    )
), (
    'eg.print.template.checkin', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.checkin',
        'Print Template: checkin',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.checkout', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.checkout',
        'Print Template Context: checkout',
        'cwst', 'label'
    )
), (
    'eg.print.template.checkout', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.checkout',
        'Print Template: checkout',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.hold_transit_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.hold_transit_slip',
        'Print Template Context: hold_transit_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template.hold_transit_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.hold_transit_slip',
        'Print Template: hold_transit_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.hold_shelf_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.hold_shelf_slip',
        'Print Template Context: hold_shelf_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template.hold_shelf_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.hold_shelf_slip',
        'Print Template: hold_shelf_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.holds_for_bib', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.holds_for_bib',
        'Print Template Context: holds_for_bib',
        'cwst', 'label'
    )
), (
    'eg.print.template.holds_for_bib', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.holds_for_bib',
        'Print Template: holds_for_bib',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.holds_for_patron', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.holds_for_patron',
        'Print Template Context: holds_for_patron',
        'cwst', 'label'
    )
), (
    'eg.print.template.holds_for_patron', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.holds_for_patron',
        'Print Template: holds_for_patron',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.hold_pull_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.hold_pull_list',
        'Print Template Context: hold_pull_list',
        'cwst', 'label'
    )
), (
    'eg.print.template.hold_pull_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.hold_pull_list',
        'Print Template: hold_pull_list',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.hold_shelf_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.hold_shelf_list',
        'Print Template Context: hold_shelf_list',
        'cwst', 'label'
    )
), (
    'eg.print.template.hold_shelf_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.hold_shelf_list',
        'Print Template: hold_shelf_list',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.in_house_use_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.in_house_use_list',
        'Print Template Context: in_house_use_list',
        'cwst', 'label'
    )
), (
    'eg.print.template.in_house_use_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.in_house_use_list',
        'Print Template: in_house_use_list',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.item_status', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.item_status',
        'Print Template Context: item_status',
        'cwst', 'label'
    )
), (
    'eg.print.template.item_status', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.item_status',
        'Print Template: item_status',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.items_out', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.items_out',
        'Print Template Context: items_out',
        'cwst', 'label'
    )
), (
    'eg.print.template.items_out', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.items_out',
        'Print Template: items_out',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.patron_address', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.patron_address',
        'Print Template Context: patron_address',
        'cwst', 'label'
    )
), (
    'eg.print.template.patron_address', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.patron_address',
        'Print Template: patron_address',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.patron_data', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.patron_data',
        'Print Template Context: patron_data',
        'cwst', 'label'
    )
), (
    'eg.print.template.patron_data', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.patron_data',
        'Print Template: patron_data',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.patron_note', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.patron_note',
        'Print Template Context: patron_note',
        'cwst', 'label'
    )
), (
    'eg.print.template.patron_note', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.patron_note',
        'Print Template: patron_note',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.renew', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.renew',
        'Print Template Context: renew',
        'cwst', 'label'
    )
), (
    'eg.print.template.renew', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.renew',
        'Print Template: renew',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.transit_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.transit_list',
        'Print Template Context: transit_list',
        'cwst', 'label'
    )
), (
    'eg.print.template.transit_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.transit_list',
        'Print Template: transit_list',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.transit_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.transit_slip',
        'Print Template Context: transit_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template.transit_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.transit_slip',
        'Print Template: transit_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.offline_checkout', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.offline_checkout',
        'Print Template Context: offline_checkout',
        'cwst', 'label'
    )
), (
    'eg.print.template.offline_checkout', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.offline_checkout',
        'Print Template: offline_checkout',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.offline_renew', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.offline_renew',
        'Print Template Context: offline_renew',
        'cwst', 'label'
    )
), (
    'eg.print.template.offline_renew', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.offline_renew',
        'Print Template: offline_renew',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.offline_checkin', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.offline_checkin',
        'Print Template Context: offline_checkin',
        'cwst', 'label'
    )
), (
    'eg.print.template.offline_checkin', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.offline_checkin',
        'Print Template: offline_checkin',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.offline_in_house_use', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.offline_in_house_use',
        'Print Template Context: offline_in_house_use',
        'cwst', 'label'
    )
), (
    'eg.print.template.offline_in_house_use', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.offline_in_house_use',
        'Print Template: offline_in_house_use',
        'cwst', 'label'
    )
), (
    'eg.serials.stream_names', 'gui', 'array',
    oils_i18n_gettext(
        'eg.serials.stream_names',
        'Serials Local Stream Names',
        'cwst', 'label'
    )
), (
    'eg.serials.items.do_print_routing_lists', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.serials.items.do_print_routing_lists',
        'Serials Print Routing Lists',
        'cwst', 'label'
    )
), (
    'eg.serials.items.receive_and_barcode', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.serials.items.receive_and_barcode',
        'Serials Barcode On Receive',
        'cwst', 'label'
    )
);


-- More values with fm_class'es
INSERT INTO config.workstation_setting_type (name, grp, datatype, fm_class, label)
VALUES (
    'eg.search.search_lib', 'gui', 'link', 'aou',
    oils_i18n_gettext(
        'eg.search.search_lib',
        'Staff Catalog Default Search Library',
        'cwst', 'label'
    )
), (
    'eg.search.pref_lib', 'gui', 'link', 'aou',
    oils_i18n_gettext(
        'eg.search.pref_lib',
        'Staff Catalog Preferred Library',
        'cwst', 'label'
    )
);


COMMIT;


