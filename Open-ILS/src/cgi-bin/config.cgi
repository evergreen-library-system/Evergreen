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
			<li><a href='/cgi-bin/usr_group-setup.cgi'>User Groups and Group Permissions </a></li>
			<li><a href='/cgi-bin/org_unit_types.cgi'>Organizational Unit Types </a></li>
			<li><a href='/cgi-bin/lib-setup.cgi'>Organizational Units</a></li>
			<li><a href='/cgi-bin/copy_statuses.cgi'>Copy Statuses</a></li>
			<li><a href='/cgi-bin/circ-rules.cgi'>Circulation and Holds Rules</a></li>
			<li><a href='/cgi-bin/perms-setup.cgi'>System Permission Editor</a> <b>Developers only!<b></li>
		</ul>
	</body>
</html>
CGI
