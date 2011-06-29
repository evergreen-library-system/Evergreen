package OpenILS::WWW::EGWeb::I18NFilter;
use Template::Plugin::Filter;
use base qw(Template::Plugin::Filter);
our $DYNAMIC = 1;
our $maketext;

sub filter {
    my ($self, $text, $args) = @_;
    return $maketext->($text, @$args);
}

sub init {
    my $self = shift;
    $self->install_filter('l');
    return $self;
}

1;

