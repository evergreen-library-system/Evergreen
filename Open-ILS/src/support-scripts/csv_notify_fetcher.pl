#!/usr/bin/perl
use strict; 
use warnings;
use DateTime;
use Getopt::Long;
use OpenSRF::AppSession;
use OpenILS::Utils::CStoreEditor;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::RemoteAccount;
use OpenSRF::Utils::Logger qw/$logger/;

my $osrf_config     = '/openils/conf/opensrf_core.xml';
my $remote_account  = '';
my $remote_file     = '';
my $local_dir       = '/tmp'; # locally stored file directory
my $local_file      = ''; # locally stored file name
my $response_file   = ''; # local file with response data
my $delete_file     = 0;
my $verbose         = 0;
my $help            = 0;
my $remote_conn     = undef;

GetOptions(
    'osrf-config=s'     => \$osrf_config,
    'remote-account=s'  => \$remote_account,
    'remote-file=s'     => \$remote_file,
    'local-file=s'      => \$local_file,
    'local-dir=s'       => \$local_dir,
    'response-file=s'   => \$response_file,
    'delete-file'       => \$delete_file,
    'help'              => \$help,
    'verbose'           => \$verbose
);

sub help {
    print <<HELP;

Collect CSV notification results file and update affected events.  The assumed
format is "event-id","event-status".

# Fetch notification response file from a remote site and delete the file when
# done.

$0 \
    --osrf-config /openils/conf/opensrf_core.xml \
    --remote-account 1 \
    --remote-file some-file.csv \
    --local-dir /tmp \
    --local-file csv-result-file.csv \
    --delete-file \
    --verbose

Options

    --osrf-config [/openils/conf/opensrf_core.xml]
        Full path to opensrf_core.xml configuration file

    --remote-account
        Identifier of the config.remote_account entry from which files should
        be retrieved

    --remote-file
        Name of file on the remote site to retrieve and process

    --local-file
        Name given to local copy of retrieved files

    --local-dir [/tmp]
        Directory to store retrieved files

    --response-file
        Name of local file which contains results.  

    --delete-file
        Delete the remote file after processing.  If the user did not specify
        a value for --local-file, the local file will be deleted as well.

    --help
        Print this help

    --verbose
        Display debug information during execution

HELP
    exit;
}

help() if $help;

die "--response-file OR --remote-account and --remote-file required\n"
    unless $response_file or ($remote_account and $remote_file);

OpenSRF::System->bootstrap_client(config_file => $osrf_config);
Fieldmapper->import(IDL => 
    OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
OpenILS::Utils::CStoreEditor::init();
my $editor = OpenILS::Utils::CStoreEditor->new;

if (!$response_file and $remote_account) {

    # fetch data remotely and push the data into $response_file

    my $racct = $editor->retrieve_config_remote_account($remote_account);
    die "No such remote account $remote_account" unless $racct;

    my $type;
    my $host = $racct->host;
    ($host =~ s/^(S?FTP)://i and $type = uc($1)) or                   
    ($host =~ s/^(SSH|SCP)://i and $type = 'SCP');
    $host =~ s#//##;

    if ($local_file) {
        # user specified local file name
        $response_file = "$local_dir/$local_file";
    } else {
        $response_file = File::Temp->new()->filename;
    }

    print "Connecting to host $host\n" if $verbose;

    $remote_conn = OpenILS::Utils::RemoteAccount->new(
        type            => $type,
        remote_host     => $host,
        account_object  => $racct,
        local_file      => $response_file,
        remote_file     => $remote_file
    );

    my $res = $remote_conn->get;

    die "Unable to fetch from  remote server [$remote_account] : " . 
        $remote_conn->error . "\n" unless $res;

    print "Fetched file $remote_file => $response_file\n" if $verbose;
}

# at this point, $file contains CSV, because it was already 
# there or because we just fetched it from the remote account
open(FILE, $response_file) or 
    die "Unable to open response file: '$response_file' : $!\n";

binmode(FILE, ":utf8");
    
while (<FILE>) {
    chomp;

    my ($id, $stat) = /"(.+)","(.+)"/g;
    next unless $id and $stat;

    $logger->info("csv: processing event $id; stat $stat");

    my $event = $editor->retrieve_action_trigger_event($id);

    if (!$event) {
        $logger->warn("csv: unable to find event $id");
        next;
    }

    if ($event->async_output) {
        $logger->info("csv: skipping event $id; async_output already set");
        next;
    }

    $editor->xact_begin;

    # store the response output
    my $output = Fieldmapper::action_trigger::event_output->new;
    $output->data($stat);

    unless ($editor->create_action_trigger_event_output($output)) {
        $logger->warn("csv: error creating event ".
            "output for event $id: ". $editor->die_event);
        next;
    }

    # link the async response output to the original event
    $event->async_output($output->id);

    unless ($editor->update_action_trigger_event($event)) {
        $logger->warn("csv: error updating event $id: ". $editor->die_event);
        next;
    }

    $editor->xact_commit;
}

$editor->disconnect;

if ($delete_file) {
    # after we have successfully processed the file, 
    # delete it from the remote server.

    $remote_conn->delete($remote_file);

    # delete the local file unless the user 
    # specified a location to save the file
    unlink($response_file) unless $local_file;
}
