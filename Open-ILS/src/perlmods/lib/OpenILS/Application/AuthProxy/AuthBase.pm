package OpenILS::Application::AuthProxy::AuthBase;
use strict;
use warnings;
use vars '$AUTOLOAD';
use OpenSRF::Utils::Logger qw(:logger);

sub new {
    my( $class, $args ) = @_;
    $class = ref $class || $class;
    return bless($args, $class);
}

# --------------------------------------------------------------------------
# Add automatic getter/setter methods
# --------------------------------------------------------------------------
my @AUTOLOAD_FIELDS = qw/
    name
    org_units
    login_types
/;
sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) or die "$self is not an object";
    my $data = shift;
    my $name = $AUTOLOAD;
    $name =~ s/.*://o;

    # return immediately if called as the DESTROY method
    return if $name eq 'DESTROY';

    unless (grep { $_ eq $name } @AUTOLOAD_FIELDS) {
        $logger->error("$type: invalid autoload field: $name");
        die "$type: invalid autoload field: $name\n"
    }

    {
        no strict 'refs';
        *{"${type}::${name}"} = sub {
            my $s = shift;
            my $v = shift;
            $s->{$name} = $v if defined $v;
            return $s->{$name};
        }
    }
    return $self->$name($data);
}

1;
