--Upgrade Script for 3.11.4 to 3.11.5
\set eg_version '''3.11.5'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.11.5', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1403', :eg_version);

UPDATE action_trigger.event_definition SET template = 

$$
[%-
# target is the book list itself. The 'items' variable does not need to be in
# the environment because a special reactor will take care of filling it in.

FOR item IN items;
    bibxml = helpers.unapi_bre(item.target_biblio_record_entry, {flesh => '{mra}'});
    title = "";
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b" or @code="n" or @code="p"]');
        title = title _ part.textContent;
    END;
    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
    item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
    pub_date = "";
    FOR pdatum IN bibxml.findnodes('//*[@tag="260"]/*[@code="c"]');
        IF pub_date ;
            pub_date = pub_date _ ", " _ pdatum.textContent;
        ELSE ;
            pub_date = pdatum.textContent;
        END;
    END;
    helpers.csv_datum(title) %],[% helpers.csv_datum(author) %],[% helpers.csv_datum(pub_date) %],[% helpers.csv_datum(item_type) %],[% FOR note IN item.notes; helpers.csv_datum(note.note); ","; END; "\n";
END -%]
$$

WHERE hook = 'container.biblio_record_entry_bucket.csv' AND MD5(template) = '386d7ab2a78a69a44a47e2b0b8c5699b';


SELECT evergreen.upgrade_deps_block_check('1404', :eg_version);

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext('acq.default_owning_lib_for_auto_lids_strategy',
        'Strategy to use when setting the default owning library for line item items that are auto-created due to the provider''s default copy count being set. Valid values are "workstation" to use the workstation library, "blank" to leave it blank, and "use_setting" to use the "Default owning library for auto-created line item items" setting. If not set, the workstation library will be used.',
        'coust', 'description')
WHERE name = 'acq.default_owning_lib_for_auto_lids_strategy'
AND description = 'Stategy to use to set default owning library to set when line item items are auto-created because the provider''s default copy count has been set. Valid values are "workstation" to use the workstation library, "blank" to leave it blank, and "use_setting" to use the "Default owning library for auto-created line item items" setting. If not set, the workstation library will be used.';

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
