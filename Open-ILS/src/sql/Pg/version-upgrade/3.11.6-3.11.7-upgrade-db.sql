--Upgrade Script for 3.11.6 to 3.11.7
\set eg_version '''3.11.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.11.7', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1414', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
  654,
  'VIEW_SHIPMENT_NOTIFICATION',
  oils_i18n_gettext(654,
    'View shipment notifications', 'ppl', 'description'
  )
  FROM permission.perm_list
  WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_SHIPMENT_NOTIFICATION');
 
INSERT INTO permission.perm_list ( id, code, description )  SELECT DISTINCT
  655,
  'MANAGE_SHIPMENT_NOTIFICATION',
  oils_i18n_gettext(655,
    'Manage shipment notifications', 'ppl', 'description'
  )
  FROM permission.perm_list
  WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'MANAGE_SHIPMENT_NOTIFICATION');


SELECT evergreen.upgrade_deps_block_check('1415', :eg_version);
INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   656,
   'PATRON_BARRED.override',
   oils_i18n_gettext(656,
     'Override the PATRON_BARRED event', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'PATRON_BARRED.override');



SELECT evergreen.upgrade_deps_block_check('1418', :eg_version);

INSERT INTO config.global_flag (name, enabled, value, label) 
    VALUES (
        'search.max_suggestion_search_terms',
        TRUE,
        3,
        oils_i18n_gettext(
            'search.max_suggestion_search_terms',
            'Limit suggestion generation to searches with this many terms or less',
            'cgf',
            'label'
        )
    );


/* UNDO
DELETE FROM config.global_flag WHERE name = 'search.max_suggestion_search_terms';
*/

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
