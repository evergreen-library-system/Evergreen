package OpenILS::WWW::EGWeb::I18NFilter;
use Template::Plugin::Filter;
use base qw(Template::Plugin::Filter);
our $DYNAMIC = 1;

sub filter {
    my ($self, $text, $args) = @_;
    return $maketext->($text, @$args);
}

1;

