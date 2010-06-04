BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0294'); -- phasefx

INSERT INTO container.biblio_record_entry_bucket_type( code, label ) VALUES (
    'temp',
    oils_i18n_gettext(
        'temp',
        'Temporary bucket which gets deleted after use.',
        'cbrebt',
        'label'
    )
);

INSERT INTO action_trigger.cleanup ( module, description ) VALUES (
    'DeleteTempBiblioBucket',
    oils_i18n_gettext(
        'DeleteTempBiblioBucket',
        'Deletes a cbreb object used as a target if it has a btype of "temp"',
        'atclean',
        'description'
    )
);

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'biblio.format.record_entry.email',
        'cbreb', 
        oils_i18n_gettext(
            'biblio.format.record_entry.email',
            'An email has been requested for one or more biblio record entries.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'biblio.format.record_entry.print',
        'cbreb', 
        oils_i18n_gettext(
            'biblio.format.record_entry.print',
            'One or more biblio record entries need to be formatted for printing.',
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
        cleanup_success,
        cleanup_failure,
        group_field,
        granularity,
        template
    ) VALUES (
        31,
        TRUE,
        1,
        'biblio.record_entry.email',
        'biblio.format.record_entry.email',
        'NOOP_True',
        'SendEmail',
        'DeleteTempBiblioBucket',
        'DeleteTempBiblioBucket',
        'owner',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Bibliographic Records

    [% FOR cbreb IN target %]
    [% FOR cbrebi IN cbreb.items %]
        Bib ID# [% cbrebi.target_biblio_record_entry.id %] ISBN: [% crebi.target_biblio_record_entry.simple_record.isbn %]
        Title: [% cbrebi.target_biblio_record_entry.simple_record.title %]
        Author: [% cbrebi.target_biblio_record_entry.simple_record.author %]
        Publication Year: [% cbrebi.target_biblio_record_entry.simple_record.pubdate %]

    [% END %]
    [% END %]
$$
    )
    ,(
        32,
        TRUE,
        1,
        'biblio.record_entry.print',
        'biblio.format.record_entry.print',
        'NOOP_True',
        'ProcessTemplate',
        'DeleteTempBiblioBucket',
        'DeleteTempBiblioBucket',
        'owner',
        'print-on-demand',
$$
[%- USE date -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target %]
    [% FOR cbrebi IN cbreb.items %]
        <li>Bib ID# [% cbrebi.target_biblio_record_entry.id %] ISBN: [% crebi.target_biblio_record_entry.simple_record.isbn %]<br />
            Title: [% cbrebi.target_biblio_record_entry.simple_record.title %]<br />
            Author: [% cbrebi.target_biblio_record_entry.simple_record.author %]<br />
            Publication Year: [% cbrebi.target_biblio_record_entry.simple_record.pubdate %]
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$
    )
;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES -- for fleshing cbreb objects
         ( 31, 'owner' )
        ,( 31, 'items' )
        ,( 31, 'items.target_biblio_record_entry' )
        ,( 31, 'items.target_biblio_record_entry.simple_record' )
        ,( 31, 'items.target_biblio_record_entry.call_numbers' )
        ,( 31, 'items.target_biblio_record_entry.fixed_fields' )
        ,( 31, 'items.target_biblio_record_entry.notes' )
        ,( 31, 'items.target_biblio_record_entry.full_record_entries' )
        ,( 32, 'owner' )
        ,( 32, 'items' )
        ,( 32, 'items.target_biblio_record_entry' )
        ,( 32, 'items.target_biblio_record_entry.simple_record' )
        ,( 32, 'items.target_biblio_record_entry.call_numbers' )
        ,( 32, 'items.target_biblio_record_entry.fixed_fields' )
        ,( 32, 'items.target_biblio_record_entry.notes' )
        ,( 32, 'items.target_biblio_record_entry.full_record_entries' )
;

-- DELETE FROM action_trigger.environment WHERE event_def IN (31,32); DELETE FROM action_trigger.event where event_def IN (31,32); DELETE FROM action_trigger.event_definition WHERE id IN (31,32); DELETE FROM action_trigger.hook WHERE key IN ('biblio.format.record_entry.email','biblio.format.record_entry.print'); DELETE FROM action_trigger.cleanup WHERE module = 'DeleteTempBiblioBucket'; DELETE FROM container.biblio_record_entry_bucket_item WHERE bucket IN (SELECT id FROM container.biblio_record_entry_bucket WHERE btype = 'temp'); DELETE FROM container.biblio_record_entry_bucket WHERE btype = 'temp'; DELETE FROM container.biblio_record_entry_bucket_type WHERE code = 'temp'; DELETE FROM config.upgrade_log WHERE version = '0294'; -- from testing, this sql will remove these events, etc.

COMMIT;

