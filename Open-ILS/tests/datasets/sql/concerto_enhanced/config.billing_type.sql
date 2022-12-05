COPY config.billing_type (id, name, owner, default_price) FROM stdin;
102	Replacement Card	1	1.00
103	Reciprocal Borrower Fee (Annual)	105	10.00
104	Meeting Room Rental	101	15.00
105	Out-Of-State (Annual Fee)	1	25.00
106	Meeting Room Rental	107	5.00
107	Meeting Room Rental	2	10.00
108	Photocopy Charges	1	\N
109	Laminating Fee	104	1.00
\.

\echo sequence update column: id
SELECT SETVAL('config.billing_type_id_seq', (SELECT MAX(id) FROM config.billing_type));
