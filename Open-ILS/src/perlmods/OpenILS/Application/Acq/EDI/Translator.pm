package OpenILS::Application::Acq::EDI::Translator;

use warnings;
use strict;

use RPC::XML::Client;
use Data::Dumper;

# DEFAULTS
my $proto = 'http://';
my $host  = $proto . 'localhost';
my $path  = '/EDI';
my $port  = 9191;
my $verbose = 0;

sub new {
    my ($class, %args) = @_;
    my $self = bless(\%args, $class);
    $self->init;
    return $self;
}

sub init {
    my $self = shift;
    $self->host_cleanup;
}

sub host_cleanup {
    my $self = shift;
    my $target = $self->{host} || $host;
    $target =~ /^\S+:\/\// or $target  = ($self->{proto} || $proto) . $target;
    $target =~ /:\d+$/     or $target .= ':' . ($self->{port} || $port);
    $target .= ($self->{path} || $path);
    $self->{verbose} and print "Cleanup: $self->{host} ==> $target\n";
    $self->{host} = $target;
    return $target;
}

sub client {
    my $self = shift;
    return $self->{client} ||= RPC::XML::Client->new($self->{host});     # TODO: auth
}

sub json2edi {
    my $self = shift;
    my $text = shift;
    my $client = $self->client();
    $self->{verbose} and print "Trying json2edi on host: $self->{host}\n";
    my $resp = $client->send_request('edi2json', $text);
    $self->{verbose} and print Dumper($resp);
    return $resp;
}

sub edi2json {
    my $self = shift;
    my $text  = shift;
    my $client = $self->client();
    $self->{verbose} and print "Trying edi2json on host: $self->{host}\n";
    my $resp = $client->send_request('json2edi', $text);
    $self->{verbose} and print Dumper($resp);
    return $resp;
}

1;

