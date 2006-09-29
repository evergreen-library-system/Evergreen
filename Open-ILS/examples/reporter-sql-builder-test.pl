#!/usr/bin/perl
use diagnostics;
use warnings;
use strict;
use OpenILS::Reporter::SQLBuilder;

my $report = {
	select => [
		{	relation=> 'circ',
			column	=> { transform => month_trunc => colname => 'checkin_time' },
			alias	=> '::PARAM4',
		},
		{	relation=> 'circ-checkin_lib-aou',
			column	=> { colname => 'shortname', transform => 'Bare'},
			alias	=> 'Library Short Name',
		},
		{	relation=> 'circ-circ_staff-au-card-ac',
			column	=> 'barcode',
			alias	=> 'User Barcode',
		},
		{	relation=> 'circ',
			column	=> { transform => count => colname => 'id' },
			alias	=> '::PARAM3',
		},
		{	relation=> 'circ-id-mb',
			column	=> { transform => sum => colname => 'amount' },
			alias	=> 'total bills',
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
			'id-billings' => {
				table	=> 'money.billing',
				alias	=> 'circ-id-mb',
				key	=> 'xact',
			},
		},
	},
	where => [
		{	relation	=> 'circ-checkin_lib-aou',
			column		=> 'id',
			condition	=> { 'in' => '::PARAM1' },
		},
		{	relation	=> 'circ',
			column		=> { transform => month_trunc => colname => 'checkin_time' },
			condition	=> { 'in' => '::PARAM2' },
		},
		{	relation	=> 'circ-id-mb',
			column		=> 'voided',
			condition	=> { '=' => '::PARAM7' },
		},
	],
	having => [
		{	relation	=> 'circ',
			column		=> { transform => count => colname => 'id' },
			condition	=> { 'between' => '::PARAM5' },
		},
	],
	order_by => [
		{	relation=> 'circ',
			column	=> { transform => count => colname => 'id' },
			direction => 'descending',
		},
		{	relation=> 'circ-checkin_lib-aou',
			column	=> { colname => 'shortname', transform => 'Bare' },
		},
		{	relation=> 'circ',
			column	=> { transform => month_trunc => colname => 'checkin_time' },
			direction => 'descending'
		},
		{	relation=> 'circ-circ_staff-au-card-ac',
			column	=> 'barcode',
		},
	],
};

my $params = {
	PARAM1 => [ 18, 19, 20, 21, 22, 23 ],
	#PARAM2 => ['2006-07','2006-08','2006-09'],
	PARAM2 => [{transform => 'relative_month', params => [-2]},{transform => 'relative_month', params => [-3]}],
	PARAM3 => 'Circ Count',
	PARAM4 => 'Checkin Date',
	PARAM5 => [{ transform => 'Bare', params => [10] },{ transform => 'Bare', params => [100] }],
	PARAM6 => [ 1, 4 ],
	PARAM7 => 'f',
};

my $r = OpenILS::Reporter::SQLBuilder->new;

$r->register_params( $params );
my $rs = $r->parse_report( $report );

print "Column Labels: " . join(', ', $rs->column_label_list) . "\n";
print $rs->toSQL;

