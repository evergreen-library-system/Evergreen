package OpenILS::WWW::BadDebt;
use strict;
use warnings;
use bytes;

use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use APR::Table;

use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;

use OpenSRF::EX qw(:try);
use OpenSRF::System;
use OpenSRF::AppSession;
use XML::LibXML;
use XML::LibXSLT;

use Encode;
use Unicode::Normalize;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/$logger/;

use UNIVERSAL::require;

# set the bootstrap config when this module is loaded
my $bootstrap;

sub import {
        my $self = shift;
        $bootstrap = shift;
}


sub child_init {
        OpenSRF::System->bootstrap_client( config_file => $bootstrap );
        return Apache2::Const::OK;
}

sub handler {
	my $r = shift;
	my $cgi = new CGI;
    my $auth_ses = $cgi->cookie('ses') || $cgi->param('ses');

	# find some IDs ...
	my @xacts;

    my $user = verify_login($auth_ses);
    return 403 unless $user;

	my $mark_bad = $cgi->param('action') eq 'unmark' ? 'f' : 't';
	my $format = $cgi->param('format') || 'csv';

	my $file = $cgi->param('idfile');
	if ($file) {
		my $col = $cgi->param('idcolumn') || 0;
		my $csv = new Text::CSV;

		while (<$file>) {
			$csv->parse($_);
			my @data = $csv->fields;
			my $id = $data[$col];
			$id =~ s/\D+//o;
			next unless ($id);
			push @xacts, $id;
		}
	}

	if (!@xacts) { # try pathinfo
		my $path_rec = $cgi->path_info();
		if ($path_rec) {
			@xacts = map { $_ ? ($_) : () } split '/', $path_rec;
		}
	}

    return 404 unless @xacts;

    my @lines;

    my ($yr,$mon,$day) = (localtime())[5,4,3]; $yr += 1900;
    my $date = sprintf('%d-%02d-%02d',$yr,$mon,$day);

    my @header = ( '"Transaction ID"', '"Message"', '"Amount Owed"', '"Transaction Start Date"', '"User Barcode"' );

	my $cstore = OpenSRF::AppSession->create('open-ils.cstore');
    my $actor = OpenSRF::AppSession->create('open-ils.actor');

    $cstore->connect();
    $cstore->request('open-ils.cstore.transaction.begin')->gather(1);
    $cstore->request('open-ils.cstore.set_audit_info', $auth_ses, $user->id, $user->wsid)->gather(1);

    for my $xact ( @xacts ) {
        try {
    
            my $x = $cstore->request('open-ils.cstore.direct.money.billable_xact.retrieve' => $xact)->gather(1);
            my $s = $cstore->request('open-ils.cstore.direct.money.billable_xact_summary.retrieve' => $xact)->gather(1);
            my $u = $cstore->request('open-ils.cstore.direct.actor.usr.retrieve' => $s->usr)->gather(1);
            my $c = $cstore->request('open-ils.cstore.direct.actor.card.retrieve' => $u->card)->gather(1);
            my $w;

            if ($s->xact_type eq 'circulation') {
                $w = $cstore->request('open-ils.cstore.direct.action.circulation.retrieve' => $xact)->gather(1)->circ_lib;
            } elsif ($s->xact_type eq 'grocery') {
                $w = $cstore->request('open-ils.cstore.direct.money.grocery.retrieve' => $xact)->gather(1)->billing_location;
            } elsif ($s->xact_type eq 'reservation') {
                $w = $cstore->request('open-ils.cstore.direct.booking.reservation.retrieve' => $xact)->gather(1)->pickup_lib;
            } else {
                die;
            }
    
            my $failures = $actor->request('open-ils.actor.user.perm.check', $auth_ses, $user->id, $w, ['MARK_BAD_DEBT'])->gather(1);
    
            if (@$failures) {
                push @lines, [ $xact, '"Permission Failure"', '""', '""', '""' ];
            } else {
                $x->unrecovered($mark_bad);
                my $result = $cstore->request('open-ils.cstore.direct.money.billable_xact.update' => $x)->gather(1);
                if ($result != $x->id) {
                    push @lines, [ $xact, '"Update Failure"', '""', '""', '""' ];
                } else {
                    my $amount = $s->balance_owed;
                    my $start = $s->xact_start;
                    my $barcode = $c->barcode;

                    if ( $mark_bad eq 't' ) {
                        push @lines, [ $xact, '"Marked Bad Debt"', $amount, "\"$start\"", "\"$barcode\"" ];
                    } else {
                        push @lines, [ $xact, '"Unmarked Bad Debt"', $amount, "\"$start\"", "\"$barcode\"" ];
                    }
                }
            }
        } otherwise {
            push @lines, [ $xact, '"Update Failure"', '""', '""', '""' ];
        };
    }

    $cstore->request('open-ils.cstore.transaction.commit')->gather(1);
    $cstore->disconnect();

    if ($format eq 'csv') {
        $r->headers_out->set("Content-Disposition" => "inline; filename=bad_debt_$date.csv");
	    $r->content_type('application/octet-stream');

        $r->print( join(',', @header) . "\n" );
        $r->print( join(',', @$_    ) . "\n" ) for (@lines);

    } elsif ($format eq 'json') {

	    $r->content_type('application/json');

        $r->print( '[' );

        my $first = 1;
        for my $line ( @lines ) {
            $r->print( ',' ) if $first;
            $first = 0;

            $r->print( '{' );
            for my $field ( 0 .. 4 ) {
                $r->print( "$header[$field] : $$line[$field]" );
                $r->print( ',' ) if ($field < 4);
            }
            $r->print( '}' );
        }

        $r->print( ']' );
    }

	return Apache2::Const::OK;

}

sub verify_login {
        my $auth_token = shift;
        return undef unless $auth_token;

        my $user = OpenSRF::AppSession
                ->create("open-ils.auth")
                ->request( "open-ils.auth.session.retrieve", $auth_token )
                ->gather(1);

        if (ref($user) eq 'HASH' && $user->{ilsevent} == 1001) {
                return undef;
        }

        return $user if ref($user);
        return undef;
}

sub show_template {
	my $r = shift;

	$r->content_type('text/html');
	$r->print(<<HTML);

<html>
	<head>
		<title>Record Export</title>
	</head>
	<body>
		<form method="POST" enctype="multipart/form-data">
			Use field number <input type="text" size="2" maxlength="2" name="idcolumn" value="0"/> (starting from 0)
			from CSV file <input type="file" name="idfile"/>
			<input type="submit" value="Mark Transactions Unrecoverable"/>
		</form>
	</body>
</html>

HTML

	return Apache2::Const::OK;
}

1;
