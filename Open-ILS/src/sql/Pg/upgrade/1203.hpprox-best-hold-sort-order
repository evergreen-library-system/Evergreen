BEGIN;

SELECT evergreen.upgrade_deps_block_check('1203', :eg_version);

ALTER TABLE config.best_hold_order ADD COLUMN owning_lib_to_home_lib_prox INT; -- copy owning lib <-> user home lib prox

ALTER table config.best_hold_order DROP CONSTRAINT best_hold_order_check;

-- At least one of these columns must contain a non-null value
ALTER TABLE config.best_hold_order ADD CHECK ((
    pprox IS NOT NULL OR
    hprox IS NOT NULL OR
    owning_lib_to_home_lib_prox IS NOT NULL OR
    aprox IS NOT NULL OR
    priority IS NOT NULL OR
    cut IS NOT NULL OR
    depth IS NOT NULL OR
    htime IS NOT NULL OR
    rtime IS NOT NULL
));

INSERT INTO config.best_hold_order (
    name,
    owning_lib_to_home_lib_prox, hprox, approx, pprox, aprox, priority, cut, depth, rtime
) VALUES (
    'Traditional with Holds-chase-home-lib-patrons',
    1, 2, 3, 4, 5, 6, 7, 8, 9
);

COMMIT;
