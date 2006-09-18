#!/usr/bin/perl
use diagnostics;
use warnings;
use strict;
use OpenILS::Reporter::SQLBuilder;

my $report = {
	select => [
		{	relation=> 'circ',
			column	=> { date => 'checkin_time' },
			alias	=> '::PARAM4',
		},
		{	relation=> 'circ-checkin_lib-aou',
			column	=> 'shortname',
			alias	=> 'Library Short Name',
		},
		{	relation=> 'circ-circ_staff-au-card-ac',
			column	=> 'barcode',
			alias	=> 'User Barcode',
		},
		{	relation=> 'circ',
			column	=> { count => 'id' },
			alias	=> '::PARAM3',
		},
	],
	from => {
		table	=> 'action.circulation',
		alias	=> 'circ',
		join	=> {
			checkin_staff => {
				table	=> 'actor.usr',
				alias	=> 'circ-circ_staff-au',
				key	=> 'id',
				join	=> {
					card => {
						table	=> 'actor.card',
						alias	=> 'circ-circ_staff-au-card-ac',
						key	=> 'id',
					},
				},
			},
			checkin_lib => {
				table	=> 'actor.org_unit',
				alias	=> 'circ-checkin_lib-aou',
				key	=> 'id',
			},
		},
	},
	where => [
		{	relation	=> 'circ-checkin_lib-aou',
			column		=> 'id',
			condition	=> { 'in' => '::PARAM1' },
		},
		{	relation	=> 'circ',
			column		=> 'checkin_time',
			condition	=> { between => '::PARAM2' },
		},
	],
};

my $params = {
	PARAM1 => [ 1, 2, 3, 4, 5, 6 ],
	PARAM2 => [ '2006-09-01', '2006-10-01' ],
	PARAM3 => 'Circ Count',
	PARAM4 => 'Checkin Date',
};

my $r = OpenILS::Reporter::SQLBuilder->new;

$r->register_params( $params );
$r->parse_report( $report );

print $r->toSQL;

