COPY config.remote_account (id, label, host, username, password, account, path, owner, last_activity) FROM stdin;
1	Brodart (Full processing)	ftp://ftp.com	username	password	12345	/in	2	\N
2	Initech (Covers only)	ftp://ftp.com	user	pw	\N	.in	4	\N
\.

\echo sequence update column: id
SELECT SETVAL('config.remote_account_id_seq', (SELECT MAX(id) FROM config.remote_account));
