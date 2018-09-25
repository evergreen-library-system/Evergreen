BEGIN;

SELECT evergreen.upgrade_deps_block_check('1089', :eg_version);

-- Add the circ.holds.max_duplicate_holds org. unit setting type.
INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class )
VALUES
( 'circ.holds.max_duplicate_holds', 'holds',
   oils_i18n_gettext(
     'circ.holds.max_duplicate_holds',
     'Maximum number of duplicate holds allowed.',
     'coust', 'label'),
   oils_i18n_gettext(
     'circ.holds.max_duplicate_holds',
     'Maximum number of duplicate title or metarecord holds allowed per patron.',
     'coust', 'description'),
   'integer', null );

COMMIT;
