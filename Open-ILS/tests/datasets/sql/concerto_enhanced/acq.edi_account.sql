COPY acq.edi_account (id, label, host, username, password, account, path, owner, last_activity, provider, in_dir, vendcode, vendacct, attr_set, use_attrs) FROM stdin;
1	Brodart (Full processing)	ftp://ftp.com	username	password	12345	/in	2	\N	2	/out	\N	\N	3	1
2	Initech (Covers only)	ftp://ftp.com	user	pw	\N	.in	4	\N	4	.out	\N	\N	2	1
\.

