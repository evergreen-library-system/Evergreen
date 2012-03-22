-- Evergreen DB patch 0689.data.record_print_format_update.sql
--
-- Updates print and email templates for bib record actions
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0689', :eg_version);

UPDATE action_trigger.event_definition SET template = $$
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target %]
    [% FOR item IN cbreb.items;
        bre_id = item.target_biblio_record_entry;

        bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
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

        <li>
            Bib ID# [% bre_id %]<br/>
            [% IF isbn %]ISBN: [% isbn %]<br/>[% END %]
            [% IF issn %]ISSN: [% issn %]<br/>[% END %]
            [% IF upc  %]UPC:  [% upc %]<br/>[% END %]
            Title: [% title %]<br />
            Author: [% author %]<br />
            Publication Info: [% publisher %] [% pubdate %]<br/>
            Item Type: [% item_type %]
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$ 
WHERE hook = 'biblio.format.record_entry.print' AND id < 100; -- sample data


UPDATE action_trigger.event_definition SET delay = '00:00:00', template = $$
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Bibliographic Records

[% FOR cbreb IN target %]
[% FOR item IN cbreb.items;
    bre_id = item.target_biblio_record_entry;

    bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
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
$$ 
WHERE hook = 'biblio.format.record_entry.email' AND id < 100; -- sample data

-- remove a swath of unused environment entries

DELETE FROM action_trigger.environment env 
    USING action_trigger.event_definition def 
    WHERE env.event_def = def.id AND 
        env.path != 'items' AND 
        def.hook = 'biblio.format.record_entry.print' AND 
        def.id < 100; -- sample data

DELETE FROM action_trigger.environment env 
    USING action_trigger.event_definition def 
    WHERE env.event_def = def.id AND 
        env.path != 'items' AND 
        env.path != 'owner' AND 
        def.hook = 'biblio.format.record_entry.email' AND 
        def.id < 100; -- sample data

COMMIT;
