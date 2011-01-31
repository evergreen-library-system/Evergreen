package OpenILS::Application;
use OpenSRF::Application;
use UNIVERSAL::require;
use base qw/OpenSRF::Application/;

sub ils_version {
    # version format is "x-y-z", for example "2-0-0" for Evergreen 2.0.0
    # For branches, format is "x-y"
    return "HEAD";
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

    local $OpenILS::Utils::CStoreEditor::always_xact = 1;

    $client->respond( $_ ) for ( $method->run(@args) );

    OpenILS::Utils::CStoreEditor->flush_forced_xacts();

    return undef;
}

1;

