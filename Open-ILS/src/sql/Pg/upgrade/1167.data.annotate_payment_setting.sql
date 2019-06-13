BEGIN;

SELECT evergreen.upgrade_deps_block_check('1167', :eg_version);

INSERT INTO config.workstation_setting_type (name,label,grp,datatype) VALUES ('eg.circ.bills.annotatepayment','Bills: Annotate Payment', 'circ', 'bool');

COMMIT;

