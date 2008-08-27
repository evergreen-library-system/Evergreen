#!/usr/bin/perl
use strict; use warnings;

my $config = shift || die "Please specify a config file\n";
my $context = shift || 'opensrf';

my $oils_reqr = 'BINDIR/oils_requestor'; # XXX command line param

if(1) { # XXX command line param

    # ------------------------------------------------------------
    # This sends the method calls to storage via oils_requestor,
    # which is able to process the results much faster
    # Make this the default for now.
    # ------------------------------------------------------------

    use OpenSRF::Utils::JSON;
    use IPC::Open2 qw/open2/;
    use Net::Domain qw/hostfqdn/;

    sub runmethod {
        my $method = shift;
        my $flag = shift;
        my $hostname = hostfqdn();
        my $command = "echo \"open-ils.storage $method\" | $oils_reqr -f $config -c $context -h $hostname";
        warn "-> $command\n";

        my ($child_stdout, $child_stdin);
        my $pid = open2($child_stdout, $child_stdin, $command);
        my $x = 0;
        for my $barcode (<$child_stdout>) {
            next if $barcode =~ /^oils/o; # hack to chop out the oils_requestor prompt
            chomp $barcode;
            $barcode = OpenSRF::Utils::JSON->JSON2perl($barcode);
            print "$barcode $flag\n" if $barcode;
        }
        close($child_stdout);
        close($child_stdin);
        waitpid($pid, 0); # don't leave any zombies (see ipc::open2)
    }

    runmethod('open-ils.storage.actor.user.lost_barcodes', 'L');
    runmethod('open-ils.storage.actor.user.barred_barcodes', 'B');
    runmethod('open-ils.storage.actor.user.penalized_barcodes', 'D');
    # too many, makes the file too large for download
    #runmethod('open-ils.storage.actor.user.expired_barcodes', 'E');  

} else {


    # ------------------------------------------------------------
    # Uses the traditional opensrf Perl API approach
    # ------------------------------------------------------------

    use OpenSRF::EX qw(:try);
    use OpenSRF::System;
    use OpenSRF::AppSession;

    OpenSRF::System->bootstrap_client( config_file => $config );

    my $ses = OpenSRF::AppSession->connect( 'open-ils.storage' );

    my $lost = $ses->request( 'open-ils.storage.actor.user.lost_barcodes' );
    while (my $resp = $lost->recv ) {
        print $resp->content . " L\n";
    }
    $lost->finish;

    if(0) { # XXX just too many... arg
        my $expired = $ses->request( 'open-ils.storage.actor.user.expired_barcodes' );
        while (my $resp = $expired->recv ) {
            print $resp->content . " E\n";
        }
        $expired->finish;
    }

    my $barred = $ses->request( 'open-ils.storage.actor.user.barred_barcodes' );
    while (my $resp = $barred->recv ) {
        print $resp->content . " B\n";
    }
    $barred->finish;

    my $penalized = $ses->request( 'open-ils.storage.actor.user.penalized_barcodes' );
    while (my $resp = $penalized->recv ) {
        print $resp->content . " D\n";
    }
    $penalized->finish;

    $ses->disconnect;
    $ses->finish;

}

