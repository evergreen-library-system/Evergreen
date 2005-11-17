#!/usr/bin/perl -w

use strict;
use DBI;
use XML::LibXML;
use Getopt::Long;
use DateTime;
use DateTime::Format::ISO8601;
use JSON;
use Data::Dumper;
use OpenILS::WWW::Reporter::transforms;

my $current_time = DateTime->from_epoch( epoch => time() )->strftime('%FT%T%z');

my ($base_xml, $count) = ('/openils/conf/reporter.xml', 1);

GetOptions(
	"file=s"	=> \$base_xml,
	"concurrency=i"	=> \$count,
);

my $parser = XML::LibXML->new;
$parser->expand_xinclude(1);

my $doc = $parser->parse_file($base_xml);

warn $doc->toString;

my $db_driver = $doc->findvalue('/reporter/setup/database/driver');
my $db_host = $doc->findvalue('/reporter/setup/database/host');
my $db_name = $doc->findvalue('/reporter/setup/database/name');
my $db_user = $doc->findvalue('/reporter/setup/database/user');
my $db_pw = $doc->findvalue('/reporter/setup/database/password');

my $dsn = "dbi:" . $db_driver . ":dbname=" . $db_name .';host=' . $db_host;

my $dbh = DBI->connect($dsn,$db_user,$db_pw);

# make sure we're not already running $count reports
my ($running) = $dbh->selectrow_array(<<SQL);
SELECT	count(*)
  FROM	reporter.run_queue
  WHERE	state = 'running';
SQL

if ($count <= $running) {
	print "Already running maximum ($running) concurrent reports\n";
	exit 1;
}

# if we have some open slots then generate the sql
my $run = $count - $running;
my $sth = $dbh->prepare(<<SQL);
SELECT	*
  FROM	reporter.stage3
  WHERE	runtime <= ?
  ORDER BY runtime
  LIMIT $run
SQL

$sth->execute($current_time);

my @reports;
while (my $r = $sth->fetchrow_hashref) {
	$r->{sql} = generate_query( $r );
	push @reports, $r;
}
$sth->finish;

for my $r ( @reports ) {
	my $sql = shift @{ $r->{sql} };

	$sth = $dbh->prepare($sql);

	$sth->execute(@{ $r->{sql} });
	while (my $row = $sth->fetchrow_hashref) {
		print join(', ', map {"$_\t=> $$row{$_}"} keys %$row)."\n";
	}
}


#-------------------------------------------------------------------

sub table_by_id {
	my $id = shift;
	my ($node) = $doc->findnodes("//*[\@id='$id']");
	if ($node && $node->findvalue('@table')) {
		($node) = $doc->findnodes("//*[\@id='".$node->getAttribute('table')."']");
	}
	return $node;
}

sub generate_query {
	my $s3 = shift;
	warn Dumper($s3);

	my $r = JSON->JSON2perl( $s3->{params} );
	warn Dumper($r);

	my $s2 = $dbh->selectrow_hashref(<<"	SQL", {}, $s3->{stage2});
		SELECT	*
		  FROM	reporter.stage2
		  WHERE	id = ?
	SQL
	warn Dumper($s2);

	my @group_by;
	my @aggs;
	my $core = $s2->{stage1};
	my @dims;

	for my $t (keys %{$$r{filter}}) {
		if ($t ne $core) {
			push @dims, $t;
		}
	}

	for my $t (keys %{$$r{output}}) {
		if ($t ne $core && !grep { $t } @dims ) {
			push @dims, $t;
		}
	}
	warn Dumper(\@dims);

	my @dim_select;
	my @dim_from;
	for my $d (@dims) {
		my $t = table_by_id($d);
		my $t_name = $t->findvalue('tablename');
		push @dim_from, "$t_name AS \"$d\"";

		my $k = $doc->findvalue("//*[\@id='$d']/\@key");
		push @dim_select, "\"$d\".\"$k\" AS \"${d}_${k}\"";

		for my $c ( keys %{$$r{output}{$d}} ) {
			push @dim_select, "\"$d\".\"$c\" AS \"${d}_${c}\"";
		}

		for my $c ( keys %{$$r{filter}{$d}} ) {
			next if (exists $$r{output}{$d}{$c});
			push @dim_select, "\"$d\".\"$c\" AS \"${d}_${c}\"";
		}
	}

	my $d_select =
		'(SELECT ' . join(',', @dim_select) .
		'  FROM ' . join(',', @dim_from) . ') AS dims';
	
	warn "*** [$d_select]\n";

	my $col = 1;
	my @groupby;
	my @output;
	my @join;
	for my $t ( keys %{$$r{output}} ) {
		my $t_name = $t;
		$t_name = "dims" if ($t ne $core);

		my $t_node = table_by_id($t);

		for my $c ( keys %{$$r{output}{$t}} ) {
			my $label = $t_node->findvalue("fields/field[\@name='$c']/label");

			my $full_col = $c;
			$full_col = "${t}_${c}" if ($t ne $t_name);
			$full_col = "\"$t_name\".\"$full_col\"";

			
			if (my $xform_type = $$r{xform}{type}{$t}{$c}) {
				my $xform = $$OpenILS::WWW::Reporter::dtype_xforms{$xform_type};
				if ($xform->{group}) {
					push @groupby, $col;
				}
				$label = "$$xform{label} -- $label";

				my $tmp = $xform->{'select'};
				$tmp =~ s/\?COLNAME\?/$full_col/gs;
				$tmp =~ s/\?PARAM\?/$$r{xform}{param}{$t}{$c}/gs;
				$full_col = $tmp;
			} else {
				push @groupby, $col;
			}

			push @output, "$full_col AS \"$label\"";
			$col++;
		}

		if ($t ne $t_name) {
			my $k = $doc->findvalue("//*[\@id='$t']/\@key");
			my $f = $doc->findvalue("//*[\@id='$t']/\@field");
			push @join, "dims.\"${t}_${k}\" = \"$core\".\"$f\"";
		}
	}

	my @where;
	my @bind;
	for my $t ( keys %{$$r{filter}} ) {
		my $t_name = $t;
		$t_name = "dims" if ($t ne $core);

		my $t_node = table_by_id($t);

		for my $c ( keys %{$$r{filter}{$t}} ) {
			my $label = $t_node->findvalue("fields/field[\@name='$c']/label");

			my $full_col = $c;
			$full_col = "${t}_${c}" if ($t ne $t_name);
			$full_col = "\"$t_name\".\"$full_col\"";

			# XXX make this use widget specific code

			my ($fam) = keys %{ $$r{filter}{$t}{$c} };
			my ($w) = keys %{ $$r{filter}{$t}{$c}{$fam} };
			my $val = $$r{filter}{$t}{$c}{$fam}{$w};

			if (ref $val) {
				push @where, "$full_col IN (".join(",",map {'?'}@$val).")";
				push @bind, @$val;
			} else {
				push @where, "$full_col = ?";
				push @bind, $val;
			}
		}
	}

	my $t = table_by_id($core)->findvalue('tablename');
	my $from = " FROM $t AS \"$core\" RIGHT JOIN $d_select ON (". join(' AND ', @join).")";
	my $select =
		"SELECT ".join(',', @output).
		  $from.
		  ' WHERE '.join(' AND ', @where).
		  ' GROUP BY '.join(',',@groupby);

	warn " !!! [$select]\n";
	warn " !!! [".join(', ',@bind)."]\n";

	return [ $select, @bind ];
}






