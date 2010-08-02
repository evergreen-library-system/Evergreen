BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0355'); -- phasefx

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES 
    (   'circ.format.missing_pieces.slip.print',
        'circ', 
        oils_i18n_gettext(
            'circ.format.missing_pieces.slip.print',
            'A missing pieces slip needs to be formatted for printing.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(  'circ.format.missing_pieces.letter.print',
        'circ', 
        oils_i18n_gettext(
            'circ.format.missing_pieces.letter.print',
            'A missing pieces patron letter needs to be formatted for printing.',
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
        33,
        TRUE,
        1,
        'circ.missing_pieces.slip.print',
        'circ.format.missing_pieces.slip.print',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
<div style="li { padding: 8px; margin 5px; }">
    <div>[% date.format %]</div><br/>
    Missing pieces for:
    <ol>
    [% FOR circ IN target %]
        <li>Barcode: [% circ.target_copy.barcode %] Transaction ID: [% circ.id %] Due: [% circ.due_date.format %]<br />
            [% helpers.get_copy_bib_basics(circ.target_copy.id).title %]
        </li>
    [% END %]
    </ol>
</div>
$$
    )
    ,(
        34,
        TRUE,
        1,
        'circ.missing_pieces.letter.print',
        'circ.format.missing_pieces.letter.print',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
[% date.format %]
Dear [% user.prefix %] [% user.first_given_name %] [% user.family_name %],

We are missing pieces for the following returned items:
[% FOR circ IN target %]
Barcode: [% circ.target_copy.barcode %] Transaction ID: [% circ.id %] Due: [% circ.due_date.format %]
[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]
[% END %]

Please return these pieces as soon as possible.

Thanks!

Library Staff
$$
    )
;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES -- for fleshing circ objects
         ( 33, 'usr')
        ,( 33, 'target_copy')
        ,( 33, 'target_copy.circ_lib')
        ,( 33, 'target_copy.circ_lib.mailing_address')
        ,( 33, 'target_copy.circ_lib.billing_address')
        ,( 33, 'target_copy.call_number')
        ,( 33, 'target_copy.call_number.owning_lib')
        ,( 33, 'target_copy.call_number.owning_lib.mailing_address')
        ,( 33, 'target_copy.call_number.owning_lib.billing_address')
        ,( 33, 'circ_lib')
        ,( 33, 'circ_lib.mailing_address')
        ,( 33, 'circ_lib.billing_address')
        ,( 34, 'usr')
        ,( 34, 'target_copy')
        ,( 34, 'target_copy.circ_lib')
        ,( 34, 'target_copy.circ_lib.mailing_address')
        ,( 34, 'target_copy.circ_lib.billing_address')
        ,( 34, 'target_copy.call_number')
        ,( 34, 'target_copy.call_number.owning_lib')
        ,( 34, 'target_copy.call_number.owning_lib.mailing_address')
        ,( 34, 'target_copy.call_number.owning_lib.billing_address')
        ,( 34, 'circ_lib')
        ,( 34, 'circ_lib.mailing_address')
        ,( 34, 'circ_lib.billing_address')
;

-- DELETE FROM config.upgrade_log WHERE version = 'temp'; DELETE FROM action_trigger.event WHERE event_def IN (33,34); DELETE FROM action_trigger.environment WHERE event_def IN (33,34); DELETE FROM action_trigger.event_definition WHERE id IN (33,34); DELETE FROM action_trigger.hook WHERE key IN ( 'circ.format.missing_pieces.slip.print', 'circ.format.missing_pieces.letter.print' );

COMMIT;

