COPY actor.workstation (id, name, owning_lib) FROM stdin;
1	RPLS-WEPL-1	4
2	RPLS-WEPL-2	4
3	CONS-3	1
4	RPLS-WEPL-4	4
5	CONS-5	1
6	CONS-6	1
7	RPLS-WEPL-7	4
8	HHPL-8	105
9	CONS-9	1
10	WAKA-MAIN-10	108
11	CONS-11	1
12	RPLS-WEPL-12	4
13	RPLS-WEPL-13	4
14	RPLS-HDPL-14	5
15	SPLS-HPL-15	6
16	HHPL-HHPL-16	106
17	RPLS-WEPL-17	4
18	HHPL-HHPL-18	106
19	HHPL-HHPL-19	106
20	WAKA-MAIN-20	108
21	SMALL-SMALL-21	114
22	LPLS-22	101
23	HHPL-HHPL-23	106
24	SMALL-SMALL-24	114
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
