BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('test'); -- phasefx

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'vandelay.queued_bib_record.print',
        'vqbr', 
        oils_i18n_gettext(
            'vandelay.queued_bib_record.print',
            'Print output has been requested for records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_bib_record.csv',
        'vqbr', 
        oils_i18n_gettext(
            'vandelay.queued_bib_record.csv',
            'CSV output has been requested for records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_bib_record.email',
        'vqbr', 
        oils_i18n_gettext(
            'vandelay.queued_bib_record.email',
            'An email has been requested for records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_auth_record.print',
        'vqar', 
        oils_i18n_gettext(
            'vandelay.queued_auth_record.print',
            'Print output has been requested for records in an Importer Authority Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_auth_record.csv',
        'vqar', 
        oils_i18n_gettext(
            'vandelay.queued_auth_record.csv',
            'CSV output has been requested for records in an Importer Authority Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_auth_record.email',
        'vqar', 
        oils_i18n_gettext(
            'vandelay.queued_auth_record.email',
            'An email has been requested for records in an Importer Authority Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.import_items.print',
        'vii', 
        oils_i18n_gettext(
            'vandelay.import_items.print',
            'Print output has been requested for Import Items from records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.import_items.csv',
        'vii', 
        oils_i18n_gettext(
            'vandelay.import_items.csv',
            'CSV output has been requested for Import Items from records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.import_items.email',
        'vii', 
        oils_i18n_gettext(
            'vandelay.import_items.email',
            'An email has been requested for Import Items from records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        38,
        TRUE,
        1,
        'Print Output for Queued Bib Records',
        'vandelay.queued_bib_record.print',
        'NOOP_True',
        'ProcessTemplate',
        'queue.owner',
        'print-on-demand',
$$
[%- USE date -%]
<pre>
Queue ID: [% target.0.queue.id %]
Queue Name: [% target.0.queue.name %]
Queue Type: [% target.0.queue.queue_type %]
Complete? [% target.0.queue.complete %]

    [% FOR vqbr IN target %]
=-=-=
 Title of work    | [% helpers.get_queued_bib_attr('title',vqbr.attributes) %]
 Author of work   | [% helpers.get_queued_bib_attr('author',vqbr.attributes) %]
 Language of work | [% helpers.get_queued_bib_attr('language',vqbr.attributes) %]
 Pagination       | [% helpers.get_queued_bib_attr('pagination',vqbr.attributes) %]
 ISBN             | [% helpers.get_queued_bib_attr('isbn',vqbr.attributes) %]
 ISSN             | [% helpers.get_queued_bib_attr('issn',vqbr.attributes) %]
 Price            | [% helpers.get_queued_bib_attr('price',vqbr.attributes) %]
 Accession Number | [% helpers.get_queued_bib_attr('rec_identifier',vqbr.attributes) %]
 TCN Value        | [% helpers.get_queued_bib_attr('eg_tcn',vqbr.attributes) %]
 TCN Source       | [% helpers.get_queued_bib_attr('eg_tcn_source',vqbr.attributes) %]
 Internal ID      | [% helpers.get_queued_bib_attr('eg_identifier',vqbr.attributes) %]
 Publisher        | [% helpers.get_queued_bib_attr('publisher',vqbr.attributes) %]
 Publication Date | [% helpers.get_queued_bib_attr('pubdate',vqbr.attributes) %]
 Edition          | [% helpers.get_queued_bib_attr('edition',vqbr.attributes) %]
 Item Barcode     | [% helpers.get_queued_bib_attr('item_barcode',vqbr.attributes) %]

    [% END %]
</pre>
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    38, 'attributes')
    ,( 38, 'queue')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        39,
        TRUE,
        1,
        'CSV Output for Queued Bib Records',
        'vandelay.queued_bib_record.csv',
        'NOOP_True',
        'ProcessTemplate',
        'queue.owner',
        'print-on-demand',
$$
[%- USE date -%][%- FOR vqbr IN target -%]"[% helpers.get_queued_bib_attr('title',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('author',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('language',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('pagination',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('isbn',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('issn',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('price',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('rec_identifier',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('eg_tcn',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('eg_tcn_source',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('eg_identifier',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('publisher',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('pubdate',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('edition',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('item_barcode',vqbr.attributes) | replace('"', '""') %]"[%- END -%]
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    39, 'attributes')
    ,( 39, 'queue')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        40,
        TRUE,
        1,
        'Email Output for Queued Bib Records',
        'vandelay.queued_bib_record.email',
        'NOOP_True',
        'SendEmail',
        'queue.owner',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.queue.owner -%]
To: [%- params.recipient_email || user.email || 'root@localhost' %]
From: [%- params.sender_email || default_sender %]
Subject: Bibs from Import Queue

Queue ID: [% target.0.queue.id %]
Queue Name: [% target.0.queue.name %]
Queue Type: [% target.0.queue.queue_type %]
Complete? [% target.0.queue.complete %]

    [% FOR vqbr IN target %]
=-=-=
 Title of work    | [% helpers.get_queued_bib_attr('title',vqbr.attributes) %]
 Author of work   | [% helpers.get_queued_bib_attr('author',vqbr.attributes) %]
 Language of work | [% helpers.get_queued_bib_attr('language',vqbr.attributes) %]
 Pagination       | [% helpers.get_queued_bib_attr('pagination',vqbr.attributes) %]
 ISBN             | [% helpers.get_queued_bib_attr('isbn',vqbr.attributes) %]
 ISSN             | [% helpers.get_queued_bib_attr('issn',vqbr.attributes) %]
 Price            | [% helpers.get_queued_bib_attr('price',vqbr.attributes) %]
 Accession Number | [% helpers.get_queued_bib_attr('rec_identifier',vqbr.attributes) %]
 TCN Value        | [% helpers.get_queued_bib_attr('eg_tcn',vqbr.attributes) %]
 TCN Source       | [% helpers.get_queued_bib_attr('eg_tcn_source',vqbr.attributes) %]
 Internal ID      | [% helpers.get_queued_bib_attr('eg_identifier',vqbr.attributes) %]
 Publisher        | [% helpers.get_queued_bib_attr('publisher',vqbr.attributes) %]
 Publication Date | [% helpers.get_queued_bib_attr('pubdate',vqbr.attributes) %]
 Edition          | [% helpers.get_queued_bib_attr('edition',vqbr.attributes) %]
 Item Barcode     | [% helpers.get_queued_bib_attr('item_barcode',vqbr.attributes) %]

    [% END %]

$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    40, 'attributes')
    ,( 40, 'queue')
    ,( 40, 'queue.owner')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        41,
        TRUE,
        1,
        'Print Output for Queued Authority Records',
        'vandelay.queued_auth_record.print',
        'NOOP_True',
        'ProcessTemplate',
        'queue.owner',
        'print-on-demand',
$$
[%- USE date -%]
<pre>
Queue ID: [% target.0.queue.id %]
Queue Name: [% target.0.queue.name %]
Queue Type: [% target.0.queue.queue_type %]
Complete? [% target.0.queue.complete %]

    [% FOR vqar IN target %]
=-=-=
 Record Identifier | [% helpers.get_queued_auth_attr('rec_identifier',vqar.attributes) %]

    [% END %]
</pre>
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    41, 'attributes')
    ,( 41, 'queue')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        42,
        TRUE,
        1,
        'CSV Output for Queued Authority Records',
        'vandelay.queued_auth_record.csv',
        'NOOP_True',
        'ProcessTemplate',
        'queue.owner',
        'print-on-demand',
$$
[%- USE date -%][%- FOR vqar IN target -%]"[% helpers.get_queued_auth_attr('rec_identifier',vqar.attributes) | replace('"', '""') %]"[%- END -%]
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    42, 'attributes')
    ,( 42, 'queue')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        43,
        TRUE,
        1,
        'Email Output for Queued Authority Records',
        'vandelay.queued_auth_record.email',
        'NOOP_True',
        'SendEmail',
        'queue.owner',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.queue.owner -%]
To: [%- params.recipient_email || user.email || 'root@localhost' %]
From: [%- params.sender_email || default_sender %]
Subject: Authorities from Import Queue

Queue ID: [% target.0.queue.id %]
Queue Name: [% target.0.queue.name %]
Queue Type: [% target.0.queue.queue_type %]
Complete? [% target.0.queue.complete %]

    [% FOR vqar IN target %]
=-=-=
 Record Identifier | [% helpers.get_queued_auth_attr('rec_identifier',vqar.attributes) %]

    [% END %]

$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    43, 'attributes')
    ,( 43, 'queue')
    ,( 43, 'queue.owner')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        44,
        TRUE,
        1,
        'Print Output for Import Items from Queued Bib Records',
        'vandelay.import_items.print',
        'NOOP_True',
        'ProcessTemplate',
        'record.queue.owner',
        'print-on-demand',
$$
[%- USE date -%]
<pre>
Queue ID: [% target.0.record.queue.id %]
Queue Name: [% target.0.record.queue.name %]
Queue Type: [% target.0.record.queue.queue_type %]
Complete? [% target.0.record.queue.complete %]

    [% FOR vii IN target %]
=-=-=
 Import Item ID         | [% vii.id %]
 Title of work          | [% helpers.get_queued_bib_attr('title',vii.record.attributes) %]
 ISBN                   | [% helpers.get_queued_bib_attr('isbn',vii.record.attributes) %]
 Attribute Definition   | [% vii.definition %]
 Import Error           | [% vii.import_error %]
 Import Error Detail    | [% vii.error_detail %]
 Owning Library         | [% vii.owning_lib %]
 Circulating Library    | [% vii.circ_lib %]
 Call Number            | [% vii.call_number %]
 Copy Number            | [% vii.copy_number %]
 Status                 | [% vii.status.name %]
 Shelving Location      | [% vii.location.name %]
 Circulate              | [% vii.circulate %]
 Deposit                | [% vii.deposit %]
 Deposit Amount         | [% vii.deposit_amount %]
 Reference              | [% vii.ref %]
 Holdable               | [% vii.holdable %]
 Price                  | [% vii.price %]
 Barcode                | [% vii.barcode %]
 Circulation Modifier   | [% vii.circ_modifier %]
 Circulate As MARC Type | [% vii.circ_as_type %]
 Alert Message          | [% vii.alert_message %]
 Public Note            | [% vii.pub_note %]
 Private Note           | [% vii.priv_note %]
 OPAC Visible           | [% vii.opac_visible %]

    [% END %]
</pre>
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    44, 'record')
    ,( 44, 'record.attributes')
    ,( 44, 'record.queue')
    ,( 44, 'record.queue.owner')
;

COMMIT;

-- BEGIN; DELETE FROM action_trigger.event_output WHERE id IN ((SELECT template_output FROM action_trigger.event WHERE event_def IN (38,39,40,41,42,43,44))UNION(SELECT error_output FROM action_trigger.event WHERE event_def IN (38,39,40,41,42,43,44))); DELETE FROM action_trigger.event WHERE event_def IN (38,39,40,41,42,43,44); DELETE FROM action_trigger.environment WHERE event_def IN (38,39,40,41,42,43,44); DELETE FROM action_trigger.event_definition WHERE id IN (38,39,40,41,42,43,44); DELETE FROM action_trigger.hook WHERE key IN ('vandelay.queued_bib_record.print','vandelay.queued_bib_record.csv','vandelay.queued_bib_record.email','vandelay.queued_auth_record.print','vandelay.queued_auth_record.csv','vandelay.queued_auth_record.email','vandelay.import_items.print','vandelay.import_items.csv','vandelay.import_items.email'); DELETE FROM config.upgrade_log WHERE version = 'test'; COMMIT;
