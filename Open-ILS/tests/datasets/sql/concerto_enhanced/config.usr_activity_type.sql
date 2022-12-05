COPY config.usr_activity_type (id, ewho, ewhat, ehow, label, egroup, enabled, transient) FROM stdin;
1001	basicauth	login	apache	RemoteAuth Login: HTTP Basic Authentication	authen	1	1
1002	ezproxy	login	apache	RemoteAuth Login: EZProxy CGI Authentication	authen	1	1
1003	patronapi	login	apache	RemoteAuth Login: PatronAPI Authentication	authen	1	1
\.

\echo sequence update column: id
SELECT SETVAL('config.usr_activity_type_id_seq', (SELECT MAX(id) FROM config.usr_activity_type));
