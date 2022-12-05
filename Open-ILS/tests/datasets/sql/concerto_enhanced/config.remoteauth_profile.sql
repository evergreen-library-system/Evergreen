COPY config.remoteauth_profile (name, description, context_org, enabled, perm, restrict_to_org, allow_inactive, allow_expired, block_list, usr_activity_type) FROM stdin;
Basic	Basic HTTP Authentication for SYS1	2	1	1	1	0	0	\N	1001
EZProxyCGI	EZProxy CGI Authentication for SYS2	3	1	1	1	0	0	\N	1002
PatronAPI	PatronAPI Authentication for SYS1	2	1	1	1	0	0	\N	1003
\.

