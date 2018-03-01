BEGIN;

SELECT evergreen.upgrade_deps_block_check('1105', :eg_version);

INSERT into config.org_unit_setting_type (name, label, grp, description, datatype) 
values ('webstaff.circ.itemsout_notice_count_excludes_courtesies','Exclude Courtesy Notices from Patrons Itemsout Notices Count',
    'circ', 'Exclude Courtesy Notices from Patron Itemsout Notices Count', 'bool');

COMMIT;
