BEGIN;

SELECT evergreen.upgrade_deps_block_check('1177', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.booking.manage', 'gui', 'object',
    oils_i18n_gettext(
        'booking.manage',
        'Grid Config: Booking Manage Reservations',
        'cwst', 'label')
), (
    'eg.grid.booking.pickup.ready', 'gui', 'object',
    oils_i18n_gettext(
        'booking.pickup.ready',
        'Grid Config: Booking Ready to pick up grid',
        'cwst', 'label')
), (
    'eg.grid.booking.pickup.picked_up', 'gui', 'object',
    oils_i18n_gettext(
        'booking.pickup.picked_up',
        'Grid Config: Booking Already Picked Up grid',
        'cwst', 'label')
), (
    'eg.grid.booking.return.patron.picked_up', 'gui', 'object',
    oils_i18n_gettext(
        'booking.return.patron.picked_up',
        'Grid Config: Booking Return Patron tab Already Picked Up grid',
        'cwst', 'label')
), (
    'eg.grid.booking.return.patron.returned', 'gui', 'object',
    oils_i18n_gettext(
        'booking.return.patron.returned',
        'Grid Config: Booking Return Patron tab Returned Today grid',
        'cwst', 'label')
), (
    'eg.grid.booking.return.resource.picked_up', 'gui', 'object',
    oils_i18n_gettext(
        'booking.return.resourcce.picked_up',
        'Grid Config: Booking Return Resource tab Already Picked Up grid',
        'cwst', 'label')
), (
    'eg.grid.booking.return.resource.returned', 'gui', 'object',
    oils_i18n_gettext(
        'booking.return.resource.returned',
        'Grid Config: Booking Return Resource tab Returned Today grid',
        'cwst', 'label')
), (
    'eg.booking.manage.selected_org_family', 'gui', 'object',
    oils_i18n_gettext(
        'booking.manage.selected_org_family',
        'Sticky setting for pickup ou family in Manage Reservations screen',
        'cwst', 'label')
), (
    'eg.booking.return.tab', 'gui', 'string',
    oils_i18n_gettext(
        'booking.return.tab',
        'Sticky setting for tab in Booking Return',
        'cwst', 'label')
), (
    'eg.booking.create.granularity', 'gui', 'integer',
    oils_i18n_gettext(
        'booking.create.granularity',
        'Sticky setting for granularity combobox in Booking Create',
        'cwst', 'label')
), (
    'eg.booking.create.multiday', 'gui', 'bool',
    oils_i18n_gettext(
        'booking.create.multiday',
        'Default to creating multiday booking reservations',
        'cwst', 'label')
), (
    'eg.booking.pickup.ready.only_show_captured', 'gui', 'bool',
    oils_i18n_gettext(
        'booking.pickup.ready.only_show_captured',
        'Include only resources that have been captured in the Ready grid in the Pickup screen',
        'cwst', 'label')
);

COMMIT;
