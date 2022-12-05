COPY asset.call_number_prefix (id, owning_lib, label, label_sortkey) FROM stdin;
1	4	REF BR1	refbr0000000001
2	5	DVD BR2	dvdbr0000000002
3	7	STORAGE BR4	storagebr0000000004
\.

\echo sequence update column: id
SELECT SETVAL('asset.call_number_prefix_id_seq', (SELECT MAX(id) FROM asset.call_number_prefix));
