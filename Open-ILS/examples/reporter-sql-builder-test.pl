#!/usr/bin/perl
use diagnostics;
use warnings;
use strict;
use OpenILS::Reporter::SQLBuilder;

my $report = {
	select => [
		{	relation=> 'circ',
			column	=> { month_trunc => ['checkin_time'] },
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
			column		=> { month_trunc => ['checkin_time'] },
			condition	=> { 'in' => '::PARAM2' },
		},
	],
	having => [
		{	relation	=> 'circ',
			column		=> { count => 'id' },
			condition	=> { '>' => '::PARAM5' },
		},
	],
	order_by => [
		{	relation=> 'circ',
			column	=> { count => 'id' },
			direction => 'descending',
		},
		{	relation=> 'circ-checkin_lib-aou',
			column	=> 'shortname',
		},
		{	relation=> 'circ',
			column	=> { month_trunc => ['checkin_time'] },
			direction => 'descending'
		},
		{	relation=> 'circ-circ_staff-au-card-ac',
			column	=> 'barcode',
		},
	],

};

my $params = {
	PARAM1 => [ 18, 19, 20, 21, 22, 23 ],
	PARAM2 => ['2006-07','2006-08','2006-09'],
	PARAM3 => 'Circ Count',
	PARAM4 => 'Checkin Date',
	PARAM5 => 100,
};

my $r = OpenILS::Reporter::SQLBuilder->new;

$r->register_params( $params );
$r->parse_report( $report );

print $r->toSQL;

