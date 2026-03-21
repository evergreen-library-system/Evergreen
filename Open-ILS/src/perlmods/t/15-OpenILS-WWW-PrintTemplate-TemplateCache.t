#!perl

use warnings;
use strict;

use Test::More tests => 11;

{
    package Fake::OpenSRF::Cache;

    sub new {
        my $class = shift;
        return bless {}, $class;
    }

    sub put_cache {
        my($self, $key, $value, $expiretime ) = @_;
        $self->{$key} = $value;
        return $key;
    }

    sub get_cache {
        my($self, $key ) = @_;
        return $self->{$key};
    }

    sub delete_cache {
        my($self, $key ) = @_;
        $self->{$key} = undef;
        return $key;
    }
}


BEGIN {
    use_ok('OpenILS::WWW::PrintTemplate::TemplateCache');
}

my $cache = OpenILS::WWW::PrintTemplate::TemplateCache->new(Fake::OpenSRF::Cache->new);

is $cache->set_template('', '', '', 'my template'),
    undef,
    'It does not set if keys are invalid';

ok $cache->set_template(12, 'Special Checkout Receipt', 'ko-KR', 'My nice template'),
    'It sets if key is valid';

ok $cache->set_template(12, 'Special Checkout Receipt', 'cs-CZ', 'My nice cs-CZ template'),
    'It can set a second locale for the template';

ok $cache->set_template(12, 'Boring Checkout Receipt', 'cs-CZ', 'Boring template'),
    'It can set another type of template';

ok $cache->set_template(27, 'Special Checkout Receipt', 'cs-CZ', 'My nice cs-CZ template at 27'),
    'It can set a template at another org unit';

is $cache->get_template(12, 'Special Checkout Receipt', 'ko-KR'),
    'My nice template',
    'It can get the value of the first locale';

is $cache->get_template(12, 'Special Checkout Receipt', 'cs-CZ'),
    'My nice cs-CZ template',
    'It can get the value of the second locale';

is $cache->get_template(12, 'Boring Checkout Receipt', 'cs-CZ'),
    'Boring template',
    'It can get the value of the other kind of template';

is $cache->get_template(27, 'Special Checkout Receipt', 'cs-CZ'),
    'My nice cs-CZ template at 27',
    'It can get the template from another org unit';

$cache->clear_templates(12);

is $cache->get_template(12, 'Special Checkout Receipt', 'ko-KR'),
    undef,
    'We can clear the templates for an org unit';
