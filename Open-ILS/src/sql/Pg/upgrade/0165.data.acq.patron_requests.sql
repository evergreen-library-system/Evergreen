BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0165'); -- phasefx

INSERT INTO action_trigger.hook (
        key,
        core_type,
        description,
        passive
    ) VALUES (
        'aur.ordered',
        'aur',
        'A patron acquisition request has been marked On-Order.',
        TRUE
    ), (
        'aur.received',
        'aur',
        'A patron acquisition request has been marked Received.',
        TRUE
    ), (
        'aur.cancelled',
        'aur',
        'A patron acquisition request has been marked Cancelled.',
        TRUE
    );

INSERT INTO action_trigger.validator (module,description) VALUES (
        'Acq::UserRequestOrdered',
        'Tests to see if the corresponding Line Item has a state of "on-order".'
    ), (
        'Acq::UserRequestReceived',
        'Tests to see if the corresponding Line Item has a state of "received".'
    ), (
        'Acq::UserRequestCancelled',
        'Tests to see if the corresponding Line Item has a state of "cancelled".'
    );

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
        15,
        FALSE,
        1,
        'Email Notice: Patron Acquisition Request marked On-Order.',
        'aur.ordered',
        'Acq::UserRequestOrdered',
        'SendEmail',
$$
[%- USE date -%]
[%- SET li = target.lineitem; -%]
[%- SET user = target.usr -%]
[%- SET title = helpers.get_li_attr("title", "", li.attributes) %]
[%- SET author = helpers.get_li_attr("author", "", li.attributes) %]
[%- SET edition = helpers.get_li_attr("edition", "", li.attributes) %]
[%- SET isbn = helpers.get_li_attr("isbn", "", li.attributes) %]
[%- SET publisher = helpers.get_li_attr("publisher", "", li.attributes) -%]
[%- SET pubdate = helpers.get_li_attr("pubdate", "", li.attributes) -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate the following acquisition request has been placed on order.

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISBN: [% isbn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
Lineitem ID: [% li.id %]
$$
    ), (
        16,
        FALSE,
        1,
        'Email Notice: Patron Acquisition Request marked Received.',
        'aur.received',
        'Acq::UserRequestReceived',
        'SendEmail',
$$
[%- USE date -%]
[%- SET li = target.lineitem; -%]
[%- SET user = target.usr -%]
[%- SET title = helpers.get_li_attr("title", "", li.attributes) %]
[%- SET author = helpers.get_li_attr("author", "", li.attributes) %]
[%- SET edition = helpers.get_li_attr("edition", "", li.attributes) %]
[%- SET isbn = helpers.get_li_attr("isbn", "", li.attributes) %]
[%- SET publisher = helpers.get_li_attr("publisher", "", li.attributes) -%]
[%- SET pubdate = helpers.get_li_attr("pubdate", "", li.attributes) -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate the materials for the following acquisition request have been received.

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISBN: [% isbn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
Lineitem ID: [% li.id %]
$$
    ), (
        17,
        FALSE,
        1,
        'Email Notice: Patron Acquisition Request marked Cancelled.',
        'aur.cancelled',
        'Acq::UserRequestCancelled',
        'SendEmail',
$$
[%- USE date -%]
[%- SET li = target.lineitem; -%]
[%- SET user = target.usr -%]
[%- SET title = helpers.get_li_attr("title", "", li.attributes) %]
[%- SET author = helpers.get_li_attr("author", "", li.attributes) %]
[%- SET edition = helpers.get_li_attr("edition", "", li.attributes) %]
[%- SET isbn = helpers.get_li_attr("isbn", "", li.attributes) %]
[%- SET publisher = helpers.get_li_attr("publisher", "", li.attributes) -%]
[%- SET pubdate = helpers.get_li_attr("pubdate", "", li.attributes) -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate the following acquisition request has been cancelled.

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISBN: [% isbn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
Lineitem ID: [% li.id %]
$$
    );

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES 
        ( 15, 'lineitem' ),
        ( 15, 'lineitem.attributes' ),
        ( 15, 'usr' ),

        ( 16, 'lineitem' ),
        ( 16, 'lineitem.attributes' ),
        ( 16, 'usr' ),

        ( 17, 'lineitem' ),
        ( 17, 'lineitem.attributes' ),
        ( 17, 'usr' )
    ;

COMMIT;

