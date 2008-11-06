package OpenILS::Application;
use OpenSRF::Application;
use base qw/OpenSRF::Application/;

sub ils_version {
    return "1-2-4-0";
}

__PACKAGE__->register_method(
    api_name    => 'opensrf.open-ils.system.ils_version',
    api_level   => 1,
    method      => 'ils_version',
);

1;

