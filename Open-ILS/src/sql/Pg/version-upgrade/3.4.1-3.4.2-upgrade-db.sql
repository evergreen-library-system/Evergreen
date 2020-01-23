--Upgrade Script for 3.4.1 to 3.4.2
\set eg_version '''3.4.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.4.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1197', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.hatch.enable.printing', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.hatch.enable.printing',
        'Use Hatch for printing',
        'cwst', 'label'
    )
);


DO $SQL$
BEGIN

    PERFORM COUNT(*), workstation, name 
    FROM actor.workstation_setting GROUP BY 2, 3 HAVING COUNT(*) > 1;

    IF FOUND THEN

        RAISE NOTICE $NOTICE$

---
The actor.workstation_setting table contains duplicate rows.  The duplicates 
should be removed before applying a new UNIQUE constraint.  To find the rows, 
execute the following SQL:

SELECT COUNT(*), workstation, name FROM actor.workstation_setting 
    GROUP BY 2, 3 HAVING COUNT(*) > 1;  
    
Once the duplicates are cleared, execute the following SQL: 

ALTER TABLE actor.workstation_setting 
    ADD CONSTRAINT ws_once_per_key UNIQUE (workstation, name);
---

$NOTICE$;

    ELSE

        ALTER TABLE actor.workstation_setting
            ADD CONSTRAINT ws_once_per_key UNIQUE (workstation, name);
    END IF;

END;
$SQL$;



COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
