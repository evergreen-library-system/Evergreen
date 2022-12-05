COPY asset.stat_cat_entry (id, stat_cat, owner, value) FROM stdin;
1	1	1	Friends of the Library Gift
2	1	1	State Funds
3	1	2	Mary McMasters Childrens Fund
4	1	105	Libraries Without Walls Grant
5	1	1	STEAM Grant
6	1	1	Gift
\.

\echo sequence update column: id
SELECT SETVAL('asset.stat_cat_entry_id_seq', (SELECT MAX(id) FROM asset.stat_cat_entry));
