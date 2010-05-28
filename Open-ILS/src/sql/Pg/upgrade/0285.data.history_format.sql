BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0285'); -- phasefx

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'circ.format.history.email',
        'circ', 
        oils_i18n_gettext(
            'circ.format.history.email',
            'An email has been requested for a circ history.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'circ.format.history.print',
        'circ', 
        oils_i18n_gettext(
            'circ.format.history.print',
            'A circ history needs to be formatted for printing.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'ahr.format.history.email',
        'ahr', 
        oils_i18n_gettext(
            'ahr.format.history.email',
            'An email has been requested for a hold request history.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'ahr.format.history.print',
        'ahr', 
        oils_i18n_gettext(
            'ahr.format.history.print',
            'A hold request history needs to be formatted for printing.',
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
        25,
        TRUE,
        1,
        'circ.history.email',
        'circ.format.history.email',
        'NOOP_True',
        'SendEmail',
        'usr',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Circulation History

    [% FOR circ IN target %]
            [% helpers.get_copy_bib_basics(circ.target_copy.id).title %]
            Barcode: [% circ.target_copy.barcode %]
            Checked Out: [% date.format(helpers.format_date(circ.xact_start), '%Y-%m-%d') %]
            Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
            Returned: [% date.format(helpers.format_date(circ.checkin_time), '%Y-%m-%d') %]
    [% END %]
$$
    )
    ,(
        26,
        TRUE,
        1,
        'circ.history.print',
        'circ.format.history.print',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR circ IN target %]
        <li>
            <div>[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]</div>
            <div>Barcode: [% circ.target_copy.barcode %]</div>
            <div>Checked Out: [% date.format(helpers.format_date(circ.xact_start), '%Y-%m-%d') %]</div>
            <div>Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]</div>
            <div>Returned: [% date.format(helpers.format_date(circ.checkin_time), '%Y-%m-%d') %]</div>
        </li>
    [% END %]
    </ol>
</div>
$$
    )
    ,(
        27,
        TRUE,
        1,
        'ahr.history.email',
        'ahr.format.history.email',
        'NOOP_True',
        'SendEmail',
        'usr',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Hold Request History

    [% FOR hold IN target %]
            [% helpers.get_copy_bib_basics(hold.current_copy.id).title %]
            Requested: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]
            [% IF hold.fulfillment_time %]Fulfilled: [% date.format(helpers.format_date(hold.fulfillment_time), '%Y-%m-%d') %][% END %]
    [% END %]
$$
    )
    ,(
        28,
        TRUE,
        1,
        'ahr.history.print',
        'ahr.format.history.print',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR hold IN target %]
        <li>
            <div>[% helpers.get_copy_bib_basics(hold.current_copy.id).title %]</div>
            <div>Requested: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]</div>
            [% IF hold.fulfillment_time %]<div>Fulfilled: [% date.format(helpers.format_date(hold.fulfillment_time), '%Y-%m-%d') %]</div>[% END %]
        </li>
    [% END %]
    </ol>
</div>
$$
    )

;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES 
         ( 25, 'target_copy')
        ,( 25, 'usr' )
        ,( 26, 'target_copy' )
        ,( 26, 'usr' )
        ,( 27, 'current_copy' )
        ,( 27, 'usr' )
        ,( 28, 'current_copy' )
        ,( 28, 'usr' )
;

-- DELETE FROM action_trigger.environment WHERE event_def IN (25,26,27,28); DELETE FROM action_trigger.event where event_def IN (25,26,27,28); DELETE FROM action_trigger.event_definition WHERE id IN (25,26,27,28); DELETE FROM action_trigger.hook WHERE key IN ('circ.format.history.email','circ.format.history.print','ahr.format.history.email','ahr.format.history.print'); DELETE FROM config.upgrade_log WHERE version = 'test'; -- from testing, this sql will remove these events, etc.

COMMIT;

