package OpenILS::WWW::EGCatLoader;

use strict;
use warnings;

use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::Normalize qw/search_normalize/;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::SettingsClient;

use Digest::MD5 qw/md5_hex/;
use Apache2::Const -compile => qw/OK/;
use MARC::Record;
use List::Util qw/first/;
#use Data::Dumper;
#$Data::Dumper::Indent = 0;

my $U = 'OpenILS::Application::AppUtils';
my $browse_cache;
my $browse_timeout;

# Object methods start here.

# Returns cache key and a list of parameters for DB proc metabib.browse().
sub prepare_browse_parameters {
    my ($self) = @_;

    no warnings 'uninitialized';

    # XXX TODO add config.global_flag rows for browse limit-limit ?

    return {
        browse_class => scalar($self->cgi->param('qtype')),
        term => scalar($self->cgi->param('bterm')),
        org_unit => $self->ctx->{copy_location_group_org} ||
            $self->ctx->{aou_tree}->()->id,
        copy_location_group => $self->ctx->{copy_location_group},
        pivot => scalar($self->cgi->param('bpivot')),
        limit => int(
            $self->cgi->param('blimit') ||
            $self->ctx->{opac_hits_per_page} || 10
        )
    };
}

# Find paging information, put it into $self->ctx, and return "real"
# rows from $results, excluding those that contain only paging
# information.
sub infer_browse_paging {
    my ($self, $results) = @_;

    foreach (@$results) {
        if ($_->{pivot_point}) {
            if ($_->{row_number} < 0) { # sic
                $self->ctx->{forward_pivot} = $_->{pivot_point};
            } else {
                $self->ctx->{back_pivot} = $_->{pivot_point};
            }
        }
    }

    return [ grep { not defined $_->{pivot_point} } @$results ];
}

sub load_browse {
    my ($self) = @_;

    # If there's a user logged in, flesh extended user info so we can get
    # her opac.hits_per_page setting, if any.
    if ($self->ctx->{user}) {
        $self->prepare_extended_user_info('settings');
        if (my $setting = first { $_->name eq 'opac.hits_per_page' }
            @{$self->ctx->{user}->settings}) {

            $self->ctx->{opac_hits_per_page} =
                int(OpenSRF::Utils::JSON->JSON2perl($setting->value));
        }
    }

    my $pager_shortcuts = $self->ctx->{get_org_setting}->(
        $self->ctx->{physical_loc} || $self->ctx->{search_ou} ||
            $self->ctx->{aou_tree}->id, 'opac.browse.pager_shortcuts'
    );
    if ($pager_shortcuts) {
        my @pager_shortcuts;
        while ($pager_shortcuts =~ s/(\*(.+?)\*)//) {
            push @pager_shortcuts, [substr($2, 0, 1), $2];
        }
        push @pager_shortcuts, map { [$_, $_] } split //, $pager_shortcuts;
        $self->ctx->{pager_shortcuts} = \@pager_shortcuts;
    }

    if ($self->cgi->param('qtype') and defined $self->cgi->param('bterm')) {

        my $method = 'open-ils.search.browse';
        $method .= '.staff' if $self->ctx->{is_staff};
        $method .= '.atomic';

        my $results = $U->simplereq('open-ils.search', 
            $method, $self->prepare_browse_parameters);

        if ($results) {
            $self->ctx->{browse_results} = $self->infer_browse_paging($results);
        }

        # We don't need an else clause to send the user a 5XX error or
        # anything. Errors will have been logged, and $ctx will be
        # prepared so a template can show a nicer error to the user.
    }

    return Apache2::Const::OK;
}

1;
