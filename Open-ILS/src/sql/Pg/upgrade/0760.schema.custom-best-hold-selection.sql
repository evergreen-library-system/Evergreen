BEGIN;

SELECT evergreen.upgrade_deps_block_check('0760', :eg_version);

CREATE TABLE config.best_hold_order(
    id          SERIAL      PRIMARY KEY,    -- (metadata)
    name        TEXT        UNIQUE,   -- i18n (metadata)
    pprox       INT, -- copy capture <-> pickup lib prox
    hprox       INT, -- copy circ lib <-> request lib prox
    aprox       INT, -- copy circ lib <-> pickup lib ADJUSTED prox on ahcm
    approx      INT, -- copy capture <-> pickup lib ADJUSTED prox from function
    priority    INT, -- group hold priority
    cut         INT, -- cut-in-line
    depth       INT, -- selection depth
    htime       INT, -- time since last home-lib circ exceeds org-unit setting
    rtime       INT, -- request time
    shtime      INT  -- time since copy last trip home exceeds org-unit setting
);

-- At least one of these columns must contain a non-null value
ALTER TABLE config.best_hold_order ADD CHECK ((
    pprox IS NOT NULL OR
    hprox IS NOT NULL OR
    aprox IS NOT NULL OR
    priority IS NOT NULL OR
    cut IS NOT NULL OR
    depth IS NOT NULL OR
    htime IS NOT NULL OR
    rtime IS NOT NULL
));

INSERT INTO config.best_hold_order (
    name,
    pprox, aprox, priority, cut, depth, rtime, htime, hprox
) VALUES (
    'Traditional',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    hprox, pprox, aprox, priority, cut, depth, rtime, htime
) VALUES (
    'Traditional with Holds-always-go-home',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    htime, hprox, pprox, aprox, priority, cut, depth, rtime
) VALUES (
    'Traditional with Holds-go-home',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    priority, cut, rtime, depth, pprox, hprox, aprox, htime
) VALUES (
    'FIFO',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    hprox, priority, cut, rtime, depth, pprox, aprox, htime
) VALUES (
    'FIFO with Holds-always-go-home',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    htime, priority, cut, rtime, depth, pprox, aprox, hprox
) VALUES (
    'FIFO with Holds-go-home',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO permission.perm_list (
    id, code, description
) VALUES (
    546,
    'ADMIN_HOLD_CAPTURE_SORT',
    oils_i18n_gettext(
        546,
        'Allows a user to make changes to best-hold selection sort order',
        'ppl',
        'description'
    )
);

INSERT INTO config.org_unit_setting_type (
    name, label, description, datatype, fm_class, update_perm, grp
) VALUES (
    'circ.hold_capture_order',
    oils_i18n_gettext(
        'circ.hold_capture_order',
        'Best-hold selection sort order',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.hold_capture_order',
        'Defines the sort order of holds when selecting a hold to fill using a given copy at capture time',
        'coust',
        'description'
    ),
    'link',
    'cbho',
    546,
    'holds'
);

INSERT INTO config.org_unit_setting_type (
    name, label, description, datatype, update_perm, grp
) VALUES (
    'circ.hold_go_home_interval',
    oils_i18n_gettext(
        'circ.hold_go_home_interval',
        'Max foreign-circulation time',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.hold_go_home_interval',
        'Time a copy can spend circulating away from its circ lib before returning there to fill a hold (if one exists there)',
        'coust',
        'description'
    ),
    'interval',
    546,
    'holds'
);

INSERT INTO actor.org_unit_setting (
    org_unit, name, value
) VALUES (
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    'circ.hold_go_home_interval',
    '"6 months"'
);

UPDATE actor.org_unit_setting SET
    name = 'circ.hold_capture_order',
    value = (SELECT id FROM config.best_hold_order WHERE name = 'FIFO')
WHERE
    name = 'circ.holds_fifo' AND value ILIKE '%true%';

COMMIT;
