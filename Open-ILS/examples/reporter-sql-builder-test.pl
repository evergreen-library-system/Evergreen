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
		{	relation=> 'circ-id-mb',
			column	=> { transform => sum => colname => 'amount' },
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
				type	=> 'inner',
				key	=> 'id',
				join	=> {
					card => {
						table	=> 'actor.card',
						alias	=> 'circ-circ_staff-au-card-ac',
						type	=> 'inner',
						key	=> 'id',
					},
				},
			},
			checkin_lib => {
				table	=> 'actor.org_unit',
				alias	=> 'circ-checkin_lib-aou',
				type	=> 'inner',
				key	=> 'id',
			},
			'id-billings' => {
				table	=> 'money.billing',
				alias	=> 'circ-id-mb',
				type	=> 'left',
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
	having => [],
	order_by => [
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
	pivot_default => 0,
	pivot_data => 4,
	pivot_label => 2,
};

my $params = {
	PARAM1 => [ 18, 19, 20, 21, 22, 23 ],
	#PARAM2 => ['2006-07','2006-08','2006-09'],
	PARAM2 => [{transform => 'relative_month', params => [-2]},{transform => 'relative_month', params => [-3]}],
	PARAM3 => 'Billed Amount',
	PARAM4 => 'Checkin Date',
	PARAM5 => [{ transform => 'Bare', params => [10] },{ transform => 'Bare', params => [100] }],
	PARAM6 => [ 1, 4 ],
	PARAM7 => 'f',
};

my $r = OpenILS::Reporter::SQLBuilder->new;

$r->register_params( $params );
my $rs = $r->parse_report( $report );
$rs->relative_time('2006-10-01T00:00:00-4');

print "Column Labels: " . join(', ', $rs->column_label_list) . "\n";
print $rs->toSQL;

print "\n\n";

print "SQL group by list: ".join(',',$rs->group_by_list)."\n";
print "Perl group by list: ".join(',',$rs->group_by_list(0))."\n";

