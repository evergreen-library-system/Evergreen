-- Evergreen DB patch XXXX.data.org-setting-circ.offline.skip_foo_if_newer_status_changed_time.sql
--
-- New org setting circ.offline.skip_checkout_if_newer_status_changed_time
-- New org setting circ.offline.skip_renew_if_newer_status_changed_time
-- New org setting circ.offline.skip_checkin_if_newer_status_changed_time
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) 
    VALUES ( 
        'circ.offline.skip_checkout_if_newer_status_changed_time',
        oils_i18n_gettext(
            'circ.offline.skip_checkout_if_newer_status_changed_time',
            'Offline: Skip offline checkout if newer item Status Changed Time.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.offline.skip_checkout_if_newer_status_changed_time',
            'Skip offline checkout transaction (raise exception when'
            || ' processing) if item Status Changed Time is newer than the'
            || ' recorded transaction time.  WARNING: The Reshelving to'
            || ' Available status rollover will trigger this.',
            'coust',
            'description'
        ),
        'bool'
    ),( 
        'circ.offline.skip_renew_if_newer_status_changed_time',
        oils_i18n_gettext(
            'circ.offline.skip_renew_if_newer_status_changed_time',
            'Offline: Skip offline renewal if newer item Status Changed Time.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.offline.skip_renew_if_newer_status_changed_time',
            'Skip offline renewal transaction (raise exception when'
            || ' processing) if item Status Changed Time is newer than the'
            || ' recorded transaction time.  WARNING: The Reshelving to'
            || ' Available status rollover will trigger this.',
            'coust',
            'description'
        ),
        'bool'
    ),( 
        'circ.offline.skip_checkin_if_newer_status_changed_time',
        oils_i18n_gettext(
            'circ.offline.skip_checkin_if_newer_status_changed_time',
            'Offline: Skip offline checkin if newer item Status Changed Time.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.offline.skip_checkin_if_newer_status_changed_time',
            'Skip offline checkin transaction (raise exception when'
            || ' processing) if item Status Changed Time is newer than the'
            || ' recorded transaction time.  WARNING: The Reshelving to'
            || ' Available status rollover will trigger this.',
            'coust',
            'description'
        ),
        'bool'
    );

COMMIT;
