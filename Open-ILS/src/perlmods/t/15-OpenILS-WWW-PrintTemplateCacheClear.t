#!perl

use warnings;
use strict;

use Test::More tests => 4;
use Test::MockModule;
use Test::MockObject;
use Apache2::Const -compile => qw(OK FORBIDDEN);
use CGI;

{
    package Fake::Response;

    sub new {
        return bless {content => []}, 'Fake::Response';
    }

    sub print {
        my ($self, $content) = @_;
        push @{$self->{content}}, $content;
        return;
    }

    sub assert_printed {
        my ($self, $content) = @_;
        return grep { $content } @{$self->{content}};
    }

    sub content_type {
        return 1;
    }
}

{
    package Fake::Cache;

    sub new {
        return bless {deleted => []}, 'Fake::Cache';
    }

    sub clear_templates {
        my ($self, $key) = @_;
        push @{$self->{deleted}}, $key;
        return $key;
    }

    sub assert_cleared {
        my ($self, $key) = @_;
        return grep { $key } @{$self->{deleted}};
    }
}

BEGIN {
    use_ok('OpenILS::WWW::PrintTemplateCacheClear');
}

my $cgi = CGI::new;
$cgi->param('template_owner', 12);

# Avoid bootstrapping, since this is an isolated unit test
my $system = Test::MockModule->new('OpenSRF::System')->mock('bootstrap_client', 1);

subtest 'when good auth and has ADMIN_PRINT_TEMPLATE permission', sub {
    plan tests => 3;

    my $response = Fake::Response->new;
    my $editor = Test::MockObject->new;
    $editor->set_true('checkauth');
    $editor->set_true('allowed');
    my $cache = Fake::Cache->new;

    is OpenILS::WWW::PrintTemplateCacheClear::handler($response, $cgi, $editor, $cache),
        Apache2::Const::OK,
        'it is ok';

    ok $response->assert_printed('OK'),
        'we print ok';

    ok $cache->assert_cleared(12),
        'we clear the templates for the requested OU';
};

subtest 'when auth is invalid', sub {
    plan tests => 2;

    my $response = Fake::Response->new;
    my $editor = Test::MockObject->new;
    $editor->set_false('checkauth');

    is OpenILS::WWW::PrintTemplateCacheClear::handler($response, $cgi, $editor, Fake::Cache->new),
        Apache2::Const::FORBIDDEN,
        'it is forbidden';

    ok $response->assert_printed('FORBIDDEN'),
        'we print forbidden';
};

subtest 'when missing the ADMIN_PRINT_TEMPLATE permission', sub {
    plan tests => 2;

    my $response = Fake::Response->new;
    my $editor = Test::MockObject->new;
    $editor->set_true('checkauth');
    $editor->set_false('allowed');

    is OpenILS::WWW::PrintTemplateCacheClear::handler($response, $cgi, $editor, Fake::Cache->new),
        Apache2::Const::FORBIDDEN,
        'it is forbidden';

    ok $response->assert_printed('FORBIDDEN'),
        'we print forbidden';
};
