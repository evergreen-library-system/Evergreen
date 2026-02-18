package OpenILS::Application;
use OpenSRF::Application;
use UNIVERSAL::require;
use base qw/OpenSRF::Application/;
use OpenILS::Utils::Fieldmapper;

__PACKAGE__->register_method(
    api_name    => 'opensrf.open-ils.system.use_authoritative',
    api_level   => 1,
    method      => 'use_authoritative',
);

# Do authoritative methods do anything different or are they simply
# clones of their non-authoritative variant?
my $_use_authoritative;
sub use_authoritative {
    if (!defined $_use_authoritative) {
        my $ua = OpenSRF::Utils::SettingsClient
            ->new->config_value('uses_pooled_read_replica_dbs') || '';
        $_use_authoritative = lc($ua) eq 'true';
    }

    return $_use_authoritative;
}

sub ils_version {
    # version format is "x-y-z", for example "2-0-0" for Evergreen 2.0.0
    # For branches, format is "x-y"
    return "3-15-10";
}

__PACKAGE__->register_method(
    api_name    => 'opensrf.open-ils.system.ils_version',
    api_level   => 1,
    method      => 'ils_version',
);

__PACKAGE__->register_method(
    api_name => 'opensrf.open-ils.fetch_idl.file',
    api_level => 1,
    method => 'get_idl_file',
);
sub get_idl_file {
    use OpenSRF::Utils::SettingsClient;
    return OpenSRF::Utils::SettingsClient->new->config_value('IDL');
}

sub publish_fieldmapper {
    my ($self,$client,$class) = @_;

    return $Fieldmapper::fieldmap unless (defined $class);
    return undef unless (exists($$Fieldmapper::fieldmap{$class}));
    return {$class => $$Fieldmapper::fieldmap{$class}};
}
__PACKAGE__->register_method(
    api_name    => 'opensrf.open-ils.system.fieldmapper',
    api_level   => 1,
    method      => 'publish_fieldmapper',
);

sub register_method {
    my $class = shift;
    my %args = @_;
    my %dup_args = %args;

    $class = ref($class) || $class;

    $args{package} ||= $class;
    __PACKAGE__->SUPER::register_method( %args );

    if (exists($dup_args{authoritative}) and $dup_args{authoritative}) {
        (my $name = $dup_args{api_name}) =~ s/$/.authoritative/o;
        if ($name ne $dup_args{api_name}) {
            $dup_args{real_api_name} = $dup_args{api_name};
            $dup_args{method} = 'authoritative_wrapper';
            $dup_args{api_name} = $name;
            $dup_args{package} = __PACKAGE__;
            __PACKAGE__->SUPER::register_method( %dup_args );
        }
    }
}

sub authoritative_wrapper {

    if (!$OpenILS::Utils::CStoreEditor::_loaded) {
        die "Couldn't load OpenILS::Utils::CStoreEditor!" unless 'OpenILS::Utils::CStoreEditor'->use;
    }

    my $self = shift;
    my $client = shift;
    my @args = @_;

    my $method = $self->method_lookup($self->{real_api_name});
    die unless $method;

    local $OpenILS::Utils::CStoreEditor::always_xact = use_authoritative();

    $client->respond( $_ ) for ( $method->run(@args) );

    OpenILS::Utils::CStoreEditor->flush_forced_xacts();

    return undef;
}

1;

