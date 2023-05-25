BEGIN;

INSERT INTO config.usr_setting_type (name, grp, datatype, label)
VALUES
(
    'eg.cat.z3950.default_field', 'gui', 'string',
    oils_i18n_gettext(
        'eg.cat.z3950.default_field',
        'Z39.50 Search default field',
        'cust', 'label')
),(
    'eg.cat.z3950.default_targets', 'gui', 'object',
    oils_i18n_gettext(
        'eg.cat.z3950.default_targets',
        'Z39.50 Search default targets',
        'cust', 'label')
);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES
(
    'eg.grid.global_z3950.search_results', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.global_z3950.search_results',
        'Grid Config: Z39.50 Search Results',
        'cwst', 'label')
),(
    'acq.default_bib_marc_template', 'gui', 'integer',
    oils_i18n_gettext(
        'acq.default_bib_marc_template',
        'Default ACQ Brief Record Bibliographic Template',
        'cwst', 'label')
),(
    'eg.grid.cat.vandelay.queue.list.acq', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.list.acq',
        'Grid Config: Vandelay ACQ Queue List',
        'cwst', 'label'
    )
),(
    'eg.grid.cat.vandelay.background-import.list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.background-import.list',
        'Grid Config: Vandelay Background Import List',
        'cwst', 'label'
    )
);

INSERT into config.org_unit_setting_type
    (name, datatype, grp, label, description)
VALUES (
    'acq.import_tab_display', 'string', 'gui',
    oils_i18n_gettext(
        'acq.import_tab_display',
        'ACQ: Which import tab(s) display in general Import/Export?',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'acq.import_tab_display',
        'Valid values are: "cat" for Import for Cataloging, '
        || '"acq" for Import for Acquisitions, "both" or unset to display both.',
        'coust', 'description'
    )
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 645, 'VIEW_BACKGROUND_IMPORT', oils_i18n_gettext(645,
                    'View background record import jobs', 'ppl', 'description')),
 ( 646, 'CREATE_BACKGROUND_IMPORT', oils_i18n_gettext(646,
                    'Create background record import jobs', 'ppl', 'description')),
 ( 647, 'UPDATE_BACKGROUND_IMPORT', oils_i18n_gettext(647,
                    'Update background record import jobs', 'ppl', 'description'))
;

CREATE TABLE vandelay.background_import (
    id              SERIAL      PRIMARY KEY,
    owner           INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    workstation     INT         REFERENCES actor.workstation (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    import_type     TEXT        NOT NULL DEFAULT 'bib' CHECK (import_type IN ('bib','acq','authority')),
    params          TEXT,
    email           TEXT,
    state           TEXT        NOT NULL DEFAULT 'new' CHECK (state IN ('new','running','complete')),
    request_time    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    complete_time   TIMESTAMPTZ,
    queue           BIGINT      -- no fkey, could be either bib_queue or authority_queue, based on import_type
);

INSERT INTO action_trigger.hook (key, core_type, passive, description) VALUES
(  'vandelay.background_import.requested', 'vbi', TRUE,
   oils_i18n_gettext('vandelay.background_import.requested','A Import/Overlay background job was requested','ath', 'description')
),('vandelay.background_import.completed', 'vbi', TRUE,
   oils_i18n_gettext('vandelay.background_import.completed','A Import/Overlay background job was completed','ath', 'description')
);

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, group_field, usr_field, template)
    VALUES (120, 'f', 1, 'Vandelay Background Import Requested', 'vandelay.background_import.requested', 'NOOP_True', 'SendEmail', 'email', 'owner',
$$
[%- USE date -%]
[%- hostname = '' # set this in order to generate a link -%]
To: [%- target.0.email || params.recipient_email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Background Import Requested
Auto-Submitted: auto-generated

[% target.size %] new background import requests were added:

[% FOR bi IN target %]
    [%- IF bi.queue; summary = helpers.fetch_vbi_queue_summary(bi)%]
  * Queue: [% summary.queue.name %] ([% bi.import_type %])
    Records in queue: [% summary.total %]
    Items in queue: [% summary.total_items %]
     [% IF bi.state != 'new' %]
     - Records imported: [% summary.imported %]
     - Items imported: [% summary.total_items_imported %]
     - Records import errors: [% summary.rec_import_errors %]
     - Items import errors: [% summary.item_import_errors %]
     [% END %]
    [% END %]
  [% IF hostname %]View queue at: https://[% hostname %]/eg2/staff/cat/vandelay/queue/[% bi.import_type %]/[% bi.queue %][% END %]

[% END %]

[% IF hostname %]Manage background imports at: https://[% hostname %]/eg2/staff/cat/vandelay/background-import[% END %]

$$);

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, group_field, usr_field, template)
    VALUES (121, 'f', 1, 'Vandelay Background Import Completed', 'vandelay.background_import.completed', 'NOOP_True', 'SendEmail', 'email', 'owner',
$$
[%- USE date -%]
[%- hostname = '' # set this in order to generate a link -%]
To: [%- target.0.email || params.recipient_email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Background Import Completed
Auto-Submitted: auto-generated

[% target.size %] new background import requests were completed:

[% FOR bi IN target %]
    [%- summary = helpers.fetch_vbi_queue_summary(bi) -%]
  * Queue: [% summary.queue.name %] ([% bi.import_type %])
    Records in queue: [% summary.total %]
    Items in queue: [% summary.total_items %]
     - Records imported: [% summary.imported %]
     - Items imported: [% summary.total_items_imported %]
     - Records import errors: [% summary.rec_import_errors %]
     - Items import errors: [% summary.item_import_errors %]
  [% IF hostname %]View queue at: https://[% hostname %]/eg2/staff/cat/vandelay/queue/[% bi.import_type %]/[% bi.queue %][% END %]

[% END %]

[% IF hostname %]Manage background imports at: https://[% hostname %]/eg2/staff/cat/vandelay/background-import[% END %]

$$);

COMMIT;

