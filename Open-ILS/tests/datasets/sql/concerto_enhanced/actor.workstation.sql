COPY actor.workstation (id, name, owning_lib) FROM stdin;
1	BR1-skiddoo	4
2	BR1-rfrasur_isl	4
3	CONS-lfloyd	1
4	BR1-lfloyd	4
5	CONS-rogan-laptop	1
6	CONS-roganlaptop	1
7	BR1-terran	4
8	HHPL-terran	105
9	CONS-CS	1
10	WAKA-MAIN-lfloyd	108
11	CONS-rfrasur	1
12	BR1-JP-SITKA	4
13	BR1-chrisy	4
14	BR2-CS	5
15	BR3-CS	6
16	HHPL-HHPL-sitka	106
17	RPLS-WEPL-tiffany	4
18	HHPL-HHPL-rfrasur	106
19	HHPL-HHPL-skiddoo	106
20	WAKA-MAIN-cwmars - jamundson	108
21	SMALL-SMALL-cwmars-jamundson	114
22	LPLS-terran	101
23	HHPL-HHPL-terran	106
24	SMALL-SMALL-terran	114
\.

\echo sequence update column: id
SELECT SETVAL('actor.workstation_id_seq', (SELECT MAX(id) FROM actor.workstation));

-- a case where the deleted workstation had payments
INSERT INTO actor.workstation(id,name,owning_lib)
SELECT missingworkstation.id, aou.shortname||FLOOR(RANDOM() * 100 + 1)::INT, 1
    FROM
    (
        SELECT
        DISTINCT mbdp.cash_drawer AS id
        FROM
        money.bnm_desk_payment mbdp
        LEFT JOIN actor.workstation aw ON (mbdp.cash_drawer = aw.id)
        WHERE
        aw.id IS NULL
    ) missingworkstation
JOIN actor.org_unit aou ON (aou.id=1);

-- anonymize workstation names
UPDATE
actor.workstation aw
    SET name=aou.shortname||'-'||aw.id
FROM actor.org_unit aou
WHERE
    aou.id=aw.owning_lib;
