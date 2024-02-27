BEGIN;

SELECT evergreen.upgrade_deps_block_check('1403', :eg_version);

UPDATE action_trigger.event_definition SET template = 

$$
[%-
# target is the book list itself. The 'items' variable does not need to be in
# the environment because a special reactor will take care of filling it in.

FOR item IN items;
    bibxml = helpers.unapi_bre(item.target_biblio_record_entry, {flesh => '{mra}'});
    title = "";
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b" or @code="n" or @code="p"]');
        title = title _ part.textContent;
    END;
    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
    item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
    pub_date = "";
    FOR pdatum IN bibxml.findnodes('//*[@tag="260"]/*[@code="c"]');
        IF pub_date ;
            pub_date = pub_date _ ", " _ pdatum.textContent;
        ELSE ;
            pub_date = pdatum.textContent;
        END;
    END;
    helpers.csv_datum(title) %],[% helpers.csv_datum(author) %],[% helpers.csv_datum(pub_date) %],[% helpers.csv_datum(item_type) %],[% FOR note IN item.notes; helpers.csv_datum(note.note); ","; END; "\n";
END -%]
$$

WHERE hook = 'container.biblio_record_entry_bucket.csv' AND MD5(template) = '386d7ab2a78a69a44a47e2b0b8c5699b';

COMMIT;
