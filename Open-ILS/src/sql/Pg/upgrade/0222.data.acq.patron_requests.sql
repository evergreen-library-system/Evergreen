BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0222'); -- phasefx

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'aur.created',
        'aur',
        oils_i18n_gettext(
            'aur.created',
            'A patron has made an acquisitions request.',
            'ath',
            'description'
        ),
        TRUE
    ), (
        'aur.rejected',
        'aur',
        oils_i18n_gettext(
            'aur.rejected',
            'A patron acquisition request has been rejected.',
            'ath',
            'description'
        ),
        TRUE
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
        template
    ) VALUES (
        18,
        FALSE,
        1,
        'Email Notice: Acquisition Request created.',
        'aur.created',
        'NOOP_True',
        'SendEmail',
$$
[%- USE date -%]
[%- SET user = target.usr -%]
[%- SET title = target.title -%]
[%- SET author = target.author -%]
[%- SET isxn = target.isxn -%]
[%- SET publisher = target.publisher -%]
[%- SET pubdate = target.pubdate -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate that you have made the following acquisition request:

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISXN: [% isxn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
$$
    ), (
        19,
        FALSE,
        1,
        'Email Notice: Acquisition Request Rejected.',
        'aur.rejected',
        'NOOP_True',
        'SendEmail',
$$
[%- USE date -%]
[%- SET user = target.usr -%]
[%- SET title = target.title -%]
[%- SET author = target.author -%]
[%- SET isxn = target.isxn -%]
[%- SET publisher = target.publisher -%]
[%- SET pubdate = target.pubdate -%]
[%- SET cancel_reason = target.cancel_reason.description -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate the following acquisition request has been rejected for this reason: [% cancel_reason %]

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISBN: [% isbn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
$$
    );

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES 
        ( 18, 'usr' ),
        ( 19, 'usr' ),
        ( 19, 'cancel_reason' )
    ;

COMMIT;

