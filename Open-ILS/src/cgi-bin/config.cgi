#!/usr/bin/perl
print <<CGI;
Content-type: text/html

<html>
	<head>
		<title>Open-ILS Bootstrapping Scripts</title>
	</head>
	<body>
		<h2>Open-ILS Bootstrapping Scripts</h2>
		<hr>
		<ul>
			<!-- <li><a href='/cgi-bin/superuser-setup.cgi'>Set up Superusers</a></li> -->
			<!-- <li><a href='/cgi-bin/user-profiles.cgi'>Configure User Profiles</a></li> -->
			<li><a href='/cgi-bin/perms-setup.cgi'>Configure Permisssions</a></li>
			<li><a href='/cgi-bin/usr_group-setup.cgi'>Configure User Permission Groups</a></li>
			<li><a href='/cgi-bin/org_unit_types.cgi'>Configure Library Types and Levels</a></li>
			<li><a href='/cgi-bin/lib-setup.cgi'>Configure Library Hierarchy</a></li>
			<li><a href='/cgi-bin/copy_statuses.cgi'>Configure Copy Statuses</a></li>
			<li><a href='/cgi-bin/circ-rules.cgi'>Configure Circulation Rules</a></li>
		</ul>
	</body>
</html>
CGI
