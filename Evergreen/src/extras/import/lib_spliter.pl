#!/usr/bin/perl -w
use strict;
use Data::Dumper;
use DBI;

unless (@ARGV) {
	print <<"	USAGE";
	Usage:	$0 <db-name> <lib-map-output> < <lib-file>
	USAGE
	exit;
}

my %libs;
my $lib_map = {};
while (<STDIN>) {
	chomp;
	my ($policy, $lib, $sys) = split "\t";
	my ($sys_pol) = split '-', $policy;

	$libs{$sys_pol}{libs} ||= [];
	$libs{$sys_pol}{name} = $sys;
	$libs{$sys_pol}{type} = 2;
	push @{ $libs{$sys_pol}{libs} }, {name => $lib, shortname => $policy, type => 3 };
}

my $dbh = DBI->connect("dbi:Pg:host=localhost;dbname=$ARGV[0]",'postgres');

$dbh->begin_work;

my $find_lib_ou = 'select id from actor.org_unit where shortname = ?';
for my $sname (keys %libs) {
	($libs{$sname}{id}) = $dbh->selectrow_array($find_lib_ou,{},$sname);
	$lib_map->{$sname} = $libs{$sname}{id};
	for my $lib (@{ $libs{$sname}{libs} }) {
		($$lib{id}) = $dbh->selectrow_array($find_lib_ou,{},$$lib{shortname});
		$lib_map->{$$lib{shortname}} = $$lib{id};
	}
}

my $find_parent_ou = 'select parent_ou from actor.org_unit where shortname = ?';
my $create_lib_ou = 'insert into actor.org_unit (name,shortname,parent_ou,ou_type) VALUES (?,?,?,?)';
for my $sname (keys %libs) {
	unless ($libs{$sname}{id}) {
		$dbh->do($create_lib_ou,{},$libs{$sname}{name},$sname, 1,$libs{$sname}{type});
		($libs{$sname}{id}) = $dbh->selectrow_array($find_lib_ou,{},$sname);
		$lib_map->{$sname} = $libs{$sname}{id};
	}
	($libs{$sname}{parent_ou}) = $dbh->selectrow_array($find_parent_ou,{},$libs{$sname}{shortname});
	my $pid = $libs{$sname}{id};
	for my $lib (@{ $libs{$sname}{libs} }) {
		unless ($$lib{id}) {
			$dbh->do($create_lib_ou,{},$$lib{name},$$lib{shortname}, $pid,$$lib{type});
			($$lib{id}) = $dbh->selectrow_array($find_lib_ou,{},$$lib{shortname});
			$lib_map->{$$lib{shortname}} = $$lib{id};
		}
		($$lib{parent_ou}) = $dbh->selectrow_array($find_parent_ou,{},$$lib{shortname});
	}
}

open FH, ">$ARGV[1]" or die "Can't open $ARGV[1] to write the map file! $!";
print FH Data::Dumper->Dump([$lib_map],['lib_map']);

$dbh->commit;

