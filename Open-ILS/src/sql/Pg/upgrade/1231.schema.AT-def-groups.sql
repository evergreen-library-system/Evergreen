BEGIN;

SELECT evergreen.upgrade_deps_block_check('1231', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'opac.email_record.allow_without_login', 'opac',
    oils_i18n_gettext('opac.email_record.allow_without_login',
        'Allow record emailing without login',
        'coust', 'label'),
    oils_i18n_gettext('opac.email_record.allow_without_login',
        'Instead of forcing a patron to log in in order to email the details of a record, just challenge them with a simple catpcha.',
        'coust', 'description'),
    'bool', null)
;

CREATE TABLE action_trigger.event_def_group (
    id      SERIAL  PRIMARY KEY,
    owner   INT     NOT NULL REFERENCES actor.org_unit (id)
                        ON DELETE RESTRICT ON UPDATE CASCADE
                        DEFERRABLE INITIALLY DEFERRED,
    hook    TEXT    NOT NULL REFERENCES action_trigger.hook (key)
                        ON DELETE RESTRICT ON UPDATE CASCADE
                        DEFERRABLE INITIALLY DEFERRED,
    active  BOOL    NOT NULL DEFAULT TRUE,
    name    TEXT    NOT NULL
);
SELECT SETVAL('action_trigger.event_def_group_id_seq'::TEXT, 100, TRUE);

CREATE TABLE action_trigger.event_def_group_member (
    id          SERIAL  PRIMARY KEY,
    grp         INT     NOT NULL REFERENCES action_trigger.event_def_group (id)
                            ON DELETE CASCADE ON UPDATE CASCADE
                            DEFERRABLE INITIALLY DEFERRED,
    event_def   INT     NOT NULL REFERENCES action_trigger.event_definition (id)
                            ON DELETE RESTRICT ON UPDATE CASCADE
                            DEFERRABLE INITIALLY DEFERRED,
    sortable    BOOL    NOT NULL DEFAULT TRUE,
    holdings    BOOL    NOT NULL DEFAULT FALSE,
    external    BOOL    NOT NULL DEFAULT FALSE,
    name        TEXT    NOT NULL
);

INSERT INTO action_trigger.event_def_group (id, owner, hook, name)
    VALUES (1, 1, 'biblio.format.record_entry.print','Print Record(s)');

INSERT INTO action_trigger.event_def_group (id, owner, hook, name)
    VALUES (2,1,'biblio.format.record_entry.email','Email Record(s)');

DO $block$
BEGIN
  PERFORM * FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email' AND owner = 1 AND active AND template =
$$
[%- USE date -%]
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Bibliographic Records
Auto-Submitted: auto-generated

[% FOR cbreb IN target %]
[% FOR item IN cbreb.items;
    bre_id = item.target_biblio_record_entry;

    bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
    title = '';
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
        title = title _ part.textContent;
    END;

    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
    item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
    publisher = bibxml.findnodes('//*[@tag="260"]/*[@code="b"]').textContent;
    pubdate = bibxml.findnodes('//*[@tag="260"]/*[@code="c"]').textContent;
    isbn = bibxml.findnodes('//*[@tag="020"]/*[@code="a"]').textContent;
    issn = bibxml.findnodes('//*[@tag="022"]/*[@code="a"]').textContent;
    upc = bibxml.findnodes('//*[@tag="024"]/*[@code="a"]').textContent;
%]

[% loop.count %]/[% loop.size %].  Bib ID# [% bre_id %]
[% IF isbn %]ISBN: [% isbn _ "\n" %][% END -%]
[% IF issn %]ISSN: [% issn _ "\n" %][% END -%]
[% IF upc  %]UPC:  [% upc _ "\n" %] [% END -%]
Title: [% title %]
Author: [% author %]
Publication Info: [% publisher %] [% pubdate %]
Item Type: [% item_type %]

[% END %]
[% END %]
$$;

  IF FOUND THEN -- update

    INSERT INTO action_trigger.event_def_group_member (grp, name, event_def)
        SELECT 2, 'Brief', id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email';

    INSERT INTO action_trigger.event_def_group_member (grp, name, holdings, event_def)
        SELECT 2, 'Full', TRUE, id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email';

    UPDATE action_trigger.event_definition SET template = $$
[%- USE date -%]
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user_data.0.email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: [%- user_data.0.subject || 'Bibliographic Records' %]
Auto-Submitted: auto-generated

[%- FOR cbreb IN target;

    flesh_list = '{mra';
    IF user_data.0.type == 'full';
        flesh_list = flesh_list _ ',holdings_xml,acp';
        IF params.holdings_limit;
            flimit = 'acn=>' _ params.holdings_limit _ ',acp=>' _ params.holdings_limit;
        END;
    END;
    flesh_list = flesh_list _ '}';

    item_list = helpers.sort_bucket_unapi_bre(cbreb.items,{flesh => flesh_list, site => user_data.0.context_org, flesh_limit => flimit}, user_data.0.sort_by, user_data.0.sort_dir);

FOR item IN item_list -%]

[% loop.count %]/[% loop.size %].  Bib ID# [% item.id %]
[% IF item.isbn %]ISBN: [% item.isbn _ "\n" %][% END -%]
[% IF item.issn %]ISSN: [% item.issn _ "\n" %][% END -%]
[% IF item.upc  %]UPC:  [% item.upc _ "\n" %][% END -%]
Title: [% item.title %]
[% IF item.author %]Author: [% item.author _ "\n" %][% END -%]
Publication Info: [% item.publisher %] [% item.pubdate %]
Item Type: [% item.item_type %]
[% IF user_data.0.type == 'full' && item.holdings.size == 0 %]
 * No items for this record at the selected location
[%- END %]
[% FOR cp IN item.holdings -%]
 * Library: [% cp.circ_lib %]
   Location: [% cp.location %]
   Call Number: [% cp.prefix _ ' ' _ cp.callnumber _ ' ' _ cp.suffix %]
[% IF cp.parts %]   Parts: [% cp.parts _ "\n" %][% END -%]
   Status: [% cp.status_label %]
   Barcode: [% cp.barcode %]
 
[% END -%]
[%- END -%]
[%- END -%]
$$ WHERE hook = 'biblio.format.record_entry.email' AND owner = 1 AND active;

  ELSE -- insert full and add existing brief

    INSERT INTO action_trigger.event_def_group_member (grp, name, event_def)
        SELECT 2, 'Brief', id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email' AND active;

    INSERT INTO action_trigger.event_definition (
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
        delay,
        template
    ) SELECT
        TRUE,
        owner,
        'biblio.record_entry.email.full',
        'biblio.format.record_entry.email',
        'NOOP_True',
        'SendEmail',
        'DeleteTempBiblioBucket',
        'DeleteTempBiblioBucket',
        'owner',
        NULL,
        '00:00:00',
        $$
[%- USE date -%]
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user_data.0.email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: [%- user_data.0.subject || 'Bibliographic Records' %]
Auto-Submitted: auto-generated

[%- FOR cbreb IN target;

    flesh_list = '{mra';
    IF user_data.0.type == 'full';
        flesh_list = flesh_list _ ',holdings_xml,acp';
        IF params.holdings_limit;
            flimit = 'acn=>' _ params.holdings_limit _ ',acp=>' _ params.holdings_limit;
        END;
    END;
    flesh_list = flesh_list _ '}';

    item_list = helpers.sort_bucket_unapi_bre(cbreb.items,{flesh => flesh_list, site => user_data.0.context_org, flesh_limit => flimit}, user_data.0.sort_by, user_data.0.sort_dir);

FOR item IN item_list -%]

[% loop.count %]/[% loop.size %].  Bib ID# [% item.id %]
[% IF item.isbn %]ISBN: [% item.isbn _ "\n" %][% END -%]
[% IF item.issn %]ISSN: [% item.issn _ "\n" %][% END -%]
[% IF item.upc  %]UPC:  [% item.upc _ "\n" %][% END -%]
Title: [% item.title %]
[% IF item.author %]Author: [% item.author _ "\n" %][% END -%]
Publication Info: [% item.publisher %] [% item.pubdate %]
Item Type: [% item.item_type %]
[% IF user_data.0.type == 'full' && item.holdings.size == 0 %]
 * No items for this record at the selected location
[%- END %]
[% FOR cp IN item.holdings -%]
 * Library: [% cp.circ_lib %]
   Location: [% cp.location %]
   Call Number: [% cp.prefix _ ' ' _ cp.callnumber _ ' ' _ cp.suffix %]
[% IF cp.parts %]   Parts: [% cp.parts _ "\n" %][% END -%]
   Status: [% cp.status_label %]
   Barcode: [% cp.barcode %]
 
[% END -%]
[%- END -%]
[%- END -%]
$$ FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email' AND active;

    INSERT INTO action_trigger.event_def_group_member (grp, name, holdings, event_def)
        SELECT 2, 'Full', TRUE, id FROM action_trigger.event_definition WHERE name = 'biblio.record_entry.email.full' and active;

  END IF;
END
$block$;

DO $block$
BEGIN
  PERFORM * FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print' AND owner = 1 AND active AND template =
$$
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target %]
    [% FOR item IN cbreb.items;
        bre_id = item.target_biblio_record_entry;

        bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
        title = '';
        FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
            title = title _ part.textContent;
        END;

        author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
        item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
        publisher = bibxml.findnodes('//*[@tag="260"]/*[@code="b"]').textContent;
        pubdate = bibxml.findnodes('//*[@tag="260"]/*[@code="c"]').textContent;
        isbn = bibxml.findnodes('//*[@tag="020"]/*[@code="a"]').textContent;
        %]

        <li>
            Bib ID# [% bre_id %] ISBN: [% isbn %]<br />
            Title: [% title %]<br />
            Author: [% author %]<br />
            Publication Info: [% publisher %] [% pubdate %]<br/>
            Item Type: [% item_type %]
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$;

  IF FOUND THEN -- update

    INSERT INTO action_trigger.event_def_group_member (grp, name, event_def)
        SELECT 1, 'Brief', id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print';

    INSERT INTO action_trigger.event_def_group_member (grp, name, holdings, event_def)
        SELECT 1, 'Full', TRUE, id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print';

    UPDATE action_trigger.event_definition SET template = $$
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target;

    flesh_list = '{mra';
    IF user_data.0.type == 'full';
        flesh_list = flesh_list _ ',holdings_xml,acp';
        IF params.holdings_limit;
            flimit = 'acn=>' _ params.holdings_limit _ ',acp=>' _ params.holdings_limit;
        END;
    END;
    flesh_list = flesh_list _ '}';

    item_list = helpers.sort_bucket_unapi_bre(cbreb.items,{flesh => flesh_list, site => user_data.0.context_org, flesh_limit => flimit}, user_data.0.sort_by, user_data.0.sort_dir);
    FOR item IN item_list %]
        <li>
            Bib ID# [% item.id %]<br />
            [% IF item.isbn %]ISBN: [% item.isbn %]<br />[% END %]
            [% IF item.issn %]ISSN: [% item.issn %]<br />[% END %]
            [% IF item.upc  %]UPC:  [% item.upc %]<br />[% END %]
            Title: [% item.title %]<br />
[% IF item.author %]            Author: [% item.author %]<br />[% END -%]
            Publication Info: [% item.publisher %] [% item.pubdate %]<br/>
            Item Type: [% item.item_type %]
            <ul>
            [% IF user_data.0.type == 'full' && item.holdings.size == 0 %]
                <li>No items for this record at the selected location</li>
            [% END %]
            [% FOR cp IN item.holdings -%]
                <li>
                    Library: [% cp.circ_lib %]<br/>
                    Location: [% cp.location %]<br/>
                    Call Number: [% cp.prefix _ ' ' _ cp.callnumber _ ' ' _ cp.suffix %]<br/>
                    [% IF cp.parts %]Parts: [% cp.parts %]<br/>[% END %]
                    Status: [% cp.status_label %]<br/>
                    Barcode: [% cp.barcode %]
                </li>
            [% END %]
            </ul>
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$ WHERE hook = 'biblio.format.record_entry.print' AND owner = 1 AND active;

    ELSE -- insert full and add brief

    INSERT INTO action_trigger.event_def_group_member (grp, name, event_def)
        SELECT 1, 'Brief', id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print' AND active;

    INSERT INTO action_trigger.event_definition (
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
        delay,
        template
    ) SELECT
        TRUE,
        owner,
        'biblio.record_entry.print.full',
        'biblio.format.record_entry.print',
        'NOOP_True',
        'ProcessTemplate',
        'DeleteTempBiblioBucket',
        'DeleteTempBiblioBucket',
        'owner',
        'print-on-demand',
        '00:00:00',
        $$
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target;

    flesh_list = '{mra';
    IF user_data.0.type == 'full';
        flesh_list = flesh_list _ ',holdings_xml,acp';
        IF params.holdings_limit;
            flimit = 'acn=>' _ params.holdings_limit _ ',acp=>' _ params.holdings_limit;
        END;
    END;
    flesh_list = flesh_list _ '}';

    item_list = helpers.sort_bucket_unapi_bre(cbreb.items,{flesh => flesh_list, site => user_data.0.context_org, flesh_limit => flimit}, user_data.0.sort_by, user_data.0.sort_dir);
    FOR item IN item_list %]
        <li>
            Bib ID# [% item.id %]<br />
            [% IF item.isbn %]ISBN: [% item.isbn %]<br />[% END %]
            [% IF item.issn %]ISSN: [% item.issn %]<br />[% END %]
            [% IF item.upc  %]UPC:  [% item.upc %]<br />[% END %]
            Title: [% item.title %]<br />
[% IF item.author %]            Author: [% item.author %]<br />[% END -%]
            Publication Info: [% item.publisher %] [% item.pubdate %]<br/>
            Item Type: [% item.item_type %]
            <ul>
            [% IF user_data.0.type == 'full' && item.holdings.size == 0 %]
                <li>No items for this record at the selected location</li>
            [% END %]
            [% FOR cp IN item.holdings -%]
                <li>
                    Library: [% cp.circ_lib %]<br/>
                    Location: [% cp.location %]<br/>
                    Call Number: [% cp.prefix _ ' ' _ cp.callnumber _ ' ' _ cp.suffix %]<br/>
                    [% IF cp.parts %]Parts: [% cp.parts %]<br/>[% END %]
                    Status: [% cp.status_label %]<br/>
                    Barcode: [% cp.barcode %]
                </li>
            [% END %]
            </ul>
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$ FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print' AND active;

    INSERT INTO action_trigger.event_def_group_member (grp, name, holdings, event_def)
        SELECT 1, 'Full', TRUE, id FROM action_trigger.event_definition WHERE name = 'biblio.record_entry.print.full' and active;

  END IF;
END
$block$;

COMMIT;

