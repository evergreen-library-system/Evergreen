package OpenILS::WWW::PrintTemplate::TemplateCache;

use warnings;
use strict;

use OpenSRF::Utils::Cache;

# This class provides a cache of print templates, so we
# don't need to bother the database for a print template
# that we already have cached.
# It assumes that it is being called from some other Perl
# that has bootstrapped already.

sub new {
    my $class = shift;
    my $cache_impl = shift || OpenSRF::Utils::Cache->new;
    return bless {cache_impl => $cache_impl}, $class;
}

sub get_template {
    my ($self, $owner, $name, $locale) = @_;
    return unless _valid_key($owner) && _valid_key($name) && _valid_key($locale);
    my $found = $self->_get_cache($owner);
    if ($found && $found->{$name} && $found->{$name}->{$locale}) {
        return $found->{$name}->{$locale};
    }
    return;
}

sub set_template {
    my ($self, $owner, $name, $locale, $template) = @_;
    return unless _valid_key($owner) && _valid_key($name) && _valid_key($locale);
    my $current_val = $self->_get_cache($owner) || {};
    $current_val->{$name} ||= {};
    $current_val->{$name}->{$locale} = $template;

    $self->{cache_impl}
        ->put_cache(
            _cache_key($owner),
            $current_val,
            60 * 60
        );

    return 1;
}

sub clear_templates {
    my ($self, $owner) = @_;
    return unless _valid_key($owner);
    return $self->{cache_impl}->delete_cache(_cache_key($owner));
}

sub _get_cache {
    my ($self, $owner) = @_;
    return $self->{cache_impl}
        ->get_cache(_cache_key($owner));
}

sub _cache_key {
    my $owner = shift;
    return "print-template-org-$owner";
}

sub _valid_key {
    my $term = shift // '';
    return length($term) > 0;
}

1;
