BEGIN;

SELECT evergreen.upgrade_deps_block_check('0776', :eg_version);

ALTER TABLE acq.lineitem_attr
    ADD COLUMN order_ident BOOLEAN NOT NULL DEFAULT FALSE;

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    547, -- VERIFY
    'ACQ_ADD_LINEITEM_IDENTIFIER',
    oils_i18n_gettext(
        547,-- VERIFY
        'When granted, newly added lineitem identifiers will propagate to linked bib records',
        'ppl',
        'description'
    )
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    548, -- VERIFY
    'ACQ_SET_LINEITEM_IDENTIFIER',
    oils_i18n_gettext(
        548,-- VERIFY
        'Allows staff to change the lineitem identifier',
        'ppl',
        'description'
    )
);

COMMIT;
