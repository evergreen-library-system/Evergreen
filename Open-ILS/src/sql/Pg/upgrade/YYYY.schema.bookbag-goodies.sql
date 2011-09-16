-- Evergreen DB patch YYYY.schema.bookbag-goodies.sql

BEGIN;

SELECT evergreen.upgrade_deps_block_check('YYYY', :eg_version);

ALTER TABLE container.biblio_record_entry_bucket
    ADD COLUMN description TEXT;

ALTER TABLE container.call_number_bucket
    ADD COLUMN description TEXT;

ALTER TABLE container.copy_bucket
    ADD COLUMN description TEXT;

ALTER TABLE container.user_bucket
    ADD COLUMN description TEXT;

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'container.biblio_record_entry_bucket.csv',
    'cbreb',
    oils_i18n_gettext(
        'container.biblio_record_entry_bucket.csv',
        'Produce a CSV file representing a bookbag',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.reactor (module, description)
VALUES (
    'ContainerCSV',
    oils_i18n_gettext(
        'ContainerCSV',
        'Facilitates produce a CSV file representing a bookbag by introducing an "items" variable into the TT environment, sorted as dictated according to user params',
        'atr',
        'description'
    )
);

INSERT INTO action_trigger.event_definition (
    id, active, owner,
    name, hook, reactor,
    validator, template
) VALUES (
    48, TRUE, 1,
    'Bookbag CSV', 'container.biblio_record_entry_bucket.csv', 'ContainerCSV',
    'NOOP_True',
$$
[%-
# target is the bookbag itself. The 'items' variable does not need to be in
# the environment because a special reactor will take care of filling it in.

FOR item IN items;
    bibxml = helpers.xml_doc(item.target_biblio_record_entry.marc);
    title = "";
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
        title = title _ part.textContent;
    END;
    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;

    helpers.csv_datum(title) %],[% helpers.csv_datum(author) %],[% FOR note IN item.notes; helpers.csv_datum(note.note); ","; END; "\n";
END -%]
$$
);

COMMIT;
