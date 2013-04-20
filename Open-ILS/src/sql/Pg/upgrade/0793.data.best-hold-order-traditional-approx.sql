BEGIN;

SELECT evergreen.upgrade_deps_block_check('0793', :eg_version);

UPDATE config.best_hold_order
SET
    approx = 1,
    pprox = 2,
    aprox = 3,
    priority = 4,
    cut = 5,
    depth = 6,
    rtime = 7,
    hprox = NULL,
    htime = NULL
WHERE name = 'Traditional' AND
    pprox = 1 AND
    aprox = 2 AND
    priority = 3 AND
    cut = 4 AND
    depth = 5 AND
    rtime = 6 ;

UPDATE config.best_hold_order
SET
    hprox = 1,
    approx = 2,
    pprox = 3,
    aprox = 4,
    priority = 5,
    cut = 6,
    depth = 7,
    rtime = 8,
    htime = NULL
WHERE name = 'Traditional with Holds-always-go-home' AND
    hprox = 1 AND
    pprox = 2 AND
    aprox = 3 AND
    priority = 4 AND
    cut = 5 AND
    depth = 6 AND
    rtime = 7 AND
    htime = 8;

UPDATE config.best_hold_order
SET
    htime = 1,
    approx = 2,
    pprox = 3,
    aprox = 4,
    priority = 5,
    cut = 6,
    depth = 7,
    rtime = 8,
    hprox = NULL
WHERE name = 'Traditional with Holds-go-home' AND
    htime = 1 AND
    hprox = 2 AND
    pprox = 3 AND
    aprox = 4 AND
    priority = 5 AND
    cut = 6 AND
    depth = 7 AND
    rtime = 8 ;


COMMIT;
