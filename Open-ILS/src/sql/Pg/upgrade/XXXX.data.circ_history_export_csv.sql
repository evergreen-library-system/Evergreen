
BEGIN;

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'circ.format.history.csv',
    'circ',
    oils_i18n_gettext(
        'circ.format.history.csv',
        'Produce CSV of circulation history',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.event_definition (
    active, owner, name, hook, reactor, validator, group_field, template) 
VALUES (
    TRUE, 1, 'Circ History CSV', 'circ.format.history.csv', 'ProcessTemplate', 'NOOP_True', 'usr',
$$
Title,Author,Call Number,Barcode,Format
[%-
FOR circ IN target;
    bibxml = helpers.unapi_bre(circ.target_copy.call_number.record, {flesh => '{mra}'});
    title = "";
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
        title = title _ part.textContent;
    END;
    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
    item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value') %]

    [%- helpers.csv_datum(title) -%],
    [%- helpers.csv_datum(author) -%],
    [%- helpers.csv_datum(circ.target_copy.call_number.label) -%],
    [%- helpers.csv_datum(circ.target_copy.barcode) -%],
    [%- helpers.csv_datum(item_type) %]
[%- END -%]
$$
);

INSERT INTO action_trigger.environment (event_def, path)
    VALUES (
        currval('action_trigger.event_definition_id_seq'),
        'target_copy.call_number'
    );

COMMIT;

/* UNDO
DELETE FROM action_trigger.event WHERE event_def = (
    SELECT id FROM action_trigger.event_definition WHERE hook = 'circ.format.history.csv');
DELETE FROM action_trigger.event_definition WHERE hook = 'circ.format.history.csv');
DELETE FROM action_trigger.hook WHERE key = 'circ.format.history.csv';
*/
