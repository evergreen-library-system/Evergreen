COPY asset.call_number_suffix (id, owning_lib, label, label_sortkey) FROM stdin;
1	4	REFERENCE	reference
2	5	MEDIA	media
3	7	DEPOSITORY	depository
\.

\echo sequence update column: id
SELECT SETVAL('asset.call_number_suffix_id_seq', (SELECT MAX(id) FROM asset.call_number_suffix));
