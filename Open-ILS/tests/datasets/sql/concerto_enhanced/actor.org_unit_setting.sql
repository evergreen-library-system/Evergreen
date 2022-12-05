COPY actor.org_unit_setting (id, org_unit, name, value) FROM stdin;
16	5	lib.info_url	"http://example.com/BR2"
17	6	lib.info_url	"http://br3.example.com"
18	7	lib.info_url	"http://br4.example.com/info"
20	1	circ.patron_edit.clone.copy_address	true
\.

\echo sequence update column: id
SELECT SETVAL('actor.org_unit_setting_id_seq', (SELECT MAX(id) FROM actor.org_unit_setting));
