BEGIN;

SELECT evergreen.upgrade_deps_block_check('0915', :eg_version);

INSERT INTO permission.perm_list (id, code, description) 
VALUES (  
    560, 
    'TOTAL_HOLD_COPY_RATIO_EXCEEDED.override',
    oils_i18n_gettext(
        560,
        'Override the TOTAL_HOLD_COPY_RATIO_EXCEEDED event',
        'ppl', 
        'description'
    )
);

INSERT INTO permission.perm_list (id, code, description) 
VALUES (  
    561, 
    'AVAIL_HOLD_COPY_RATIO_EXCEEDED.override',
    oils_i18n_gettext(
        561,
        'Override the AVAIL_HOLD_COPY_RATIO_EXCEEDED event',
        'ppl', 
        'description'
    )
);

COMMIT;
