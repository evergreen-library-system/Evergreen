COPY serial.pattern_template (id, name, pattern_code, owning_lib, share_depth) FROM stdin;
1	Daily	["2","0","8",0,"a","v.","b","no.","u","und","v","c","i","(year)","j","(month)","k","(day)","w","d"]	1	0
2	Weekly	["2","0","8",0,"a","v.","b","no.","u","52","v","r","i","(year)","j","(month)","k","(day)","w","w"]	1	0
3	Biweekly	["2","0","8",0,"a","v.","b","no.","u","26","v","r","i","(year)","j","(month)","k","(day)","w","e"]	1	0
4	Monthly	["2","0","8",0,"a","v.","b","no.","u","12","v","r","i","(year)","j","(month)","w","m"]	1	0
5	Monthly w/ J/F & J/A	["2","0","8",0,"a","v.","b","no.","u","10","v","r","i","(year)","j","(month)","w","m","y","cm01/02,07/08"]	1	0
6	Monthly w/ D/J & J/J	["2","0","8",0,"a","v.","b","no.","u","10","v","r","i","(year)","j","(month)","w","m","y","cm12/01,06/07"]	1	0
7	Bimonthly	["2","0","8",0,"a","v.","b","no.","u","6","v","r","i","(year)","j","(month)","w","m","y","cm01/02,03/04,05/06,07/08,09/10,11/12"]	1	0
8	Bimonthly - Single months	["2","0","8",0,"a","v.","b","no.","u","6","v","r","i","(year)","j","(month)","w","b"]	1	0
9	Bimonthly w/ D/J	["2","0","8",0,"a","v.","b","no.","u","6","v","r","i","(year)","j","(month)","w","m","y","cm12/01,02/03,04/05,06/07,08/09,10/11"]	1	0
10	Quarterly - Seasons	["2","0","8",0,"a","v.","b","no.","u","4","v","r","i","(year)","j","(season)","w","q"]	1	0
11	Quarterly - Months	["2","0","8",0,"a","v.","b","no.","u","4","v","c","i","(year)","j","(month)","w","q"]	1	0
12	Daily - M-F	["2","0","8",0,"a","v.","b","no.","u","249","v","r","i","(year)","j","(month)","k","(day)","w","d","y","odsa,su"]	1	0
\.

\echo sequence update column: id
SELECT SETVAL('serial.pattern_template_id_seq', (SELECT MAX(id) FROM serial.pattern_template));
