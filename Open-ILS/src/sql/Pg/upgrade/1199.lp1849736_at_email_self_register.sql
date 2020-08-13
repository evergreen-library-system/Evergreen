BEGIN;


SELECT evergreen.upgrade_deps_block_check('1199', :eg_version);

INSERT INTO action_trigger.hook
(key,core_type,description,passive)
VALUES
('stgu.created','stgu','Patron requested a card using self registration','t');


INSERT INTO action_trigger.event_definition(active,owner,name,hook,validator,reactor,delay,max_delay,delay_field,group_field,template,retention_interval)
SELECT 'f',1,'Patron Registered for a card stgu.created','stgu.created','NOOP_True','SendEmail','00:01:00'::interval,'1 day'::interval,'row_date','home_ou',
$$[%- USE date -%]
[%- lib = target.0.home_ou -%]
To: [% lib.name %] <[% params.recipient_email || helpers.get_org_setting(target.0.home_ou.id, 'org.bounced_emails') || lib.email || default_sender %]>
From: [% lib.name %] <[%  helpers.get_org_setting(target.0.home_ou.id, 'org.bounced_emails') || lib.email || params.recipient_email || default_sender %]>
Date: [% date.format(format => '%a, %d %b %Y %H:%M:%S %Z') %]
Subject: Patron card requested
Auto-Submitted: auto-generated


Dear Staff Admin,

There are some pending patrons waiting for your attention.

[% FOR patron IN target %]
    [% patron.first_given_name %]

[% END %]

These requests can be tended via the staff interface. Located "Circulation" -> "Pending Patrons"


$$,
'1 year'::interval

WHERE NOT EXISTS (SELECT 1 FROM action_trigger.event_definition WHERE name='Patron Registered for a card stgu.created');

INSERT INTO action_trigger.environment (event_def,path)
SELECT id,'home_ou' from action_trigger.event_definition WHERE name='Patron Registered for a card stgu.created'
AND NOT EXISTS (SELECT 1 FROM action_trigger.environment WHERE
event_def=(SELECT id FROM action_trigger.event_definition WHERE name='Patron Registered for a card stgu.created' AND owner=1 LIMIT 1)
AND path='home_ou');


COMMIT;
