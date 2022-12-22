COPY actor.org_unit_setting (org_unit, name, value) FROM stdin;
1	circ.patron_edit.clone.copy_address	true
4	lib.info_url	"http://example.com/BR1"
5	lib.info_url	"http://example.com/BR2"
6	lib.info_url	"http://br3.example.com"
7	lib.info_url	"http://br4.example.com/info"
\.

\echo sequence update column: id
SELECT SETVAL('actor.org_unit_setting_id_seq', (SELECT MAX(id) FROM actor.org_unit_setting));
