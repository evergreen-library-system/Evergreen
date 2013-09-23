BEGIN;

SELECT evergreen.upgrade_deps_block_check('0834', :eg_version);

INSERT INTO config.org_unit_setting_type 
    (name, grp, datatype, label, description)
VALUES (
    'ui.circ.items_out.longoverdue', 'gui', 'integer',
    oils_i18n_gettext(
        'ui.circ.items_out.longoverdue',
        'Items Out Long-Overdue display setting',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.circ.items_out.longoverdue',
'Value is a numeric code, describing which list the circulation '||
'should appear while checked out and whether the circulation should '||
'continue to appear in the bottom list, when checked in with '||
'oustanding fines.  '||
'1 = top list, bottom list.  2 = bottom list, bottom list.  ' ||
'5 = top list, do not display.  6 = bottom list, do not display.',
        'coust',
        'description'
    )
), (
    'ui.circ.items_out.lost', 'gui', 'integer',
    oils_i18n_gettext(
        'ui.circ.items_out.lost',
        'Items Out Lost display setting',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.circ.items_out.lost',
'Value is a numeric code, describing which list the circulation '||
'should appear while checked out and whether the circulation should '||
'continue to appear in the bottom list, when checked in with '||
'oustanding fines.  '||
'1 = top list, bottom list.  2 = bottom list, bottom list.  ' ||
'5 = top list, do not display.  6 = bottom list, do not display.',
        'coust',
        'description'
    )
), (
    'ui.circ.items_out.claimsreturned', 'gui', 'integer',
    oils_i18n_gettext(
        'ui.circ.items_out.claimsreturned',
        'Items Out Claims Returned display setting',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.circ.items_out.claimsreturned',
'Value is a numeric code, describing which list the circulation '||
'should appear while checked out and whether the circulation should '||
'continue to appear in the bottom list, when checked in with '||
'oustanding fines.  '||
'1 = top list, bottom list.  2 = bottom list, bottom list.  ' ||
'5 = top list, do not display.  6 = bottom list, do not display.',
        'coust',
        'description'
    )
);

COMMIT;
