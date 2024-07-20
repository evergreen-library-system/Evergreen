=head1 NAME

OpenILS::WWW::EResourceLinkClick::Click.pm

=head1 DESCRIPTION
This module is responsible for validating and
persisting information about a click on
an eresource link.
=cut

package OpenILS::WWW::EResourceLinkClick::Click;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use Duadua;
use strict; use warnings;

use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;

use constant Success => 'Success';
use constant NotConfigured => 'NotConfigured';
use constant BadInput => 'BadInput';
use constant InternalError => 'InternalError';

sub add_click {
    my ($self, $record_id, $url, $referer, $user_agent) = @_;

    # We do not check auth for this editor, since links
    # can be clicked by unauthenticated users and we
    # still want to record those in the db
    my $editor = new_editor;
    return NotConfigured unless ($self->_feature_enabled($editor));
    return BadInput if $self->_input_is_bad($record_id, $url, $referer, $user_agent);

    return $self->_create_link($record_id, $url, $editor) ? Success : InternalError;
}


sub _create_link {
    my ($self, $record_id, $url, $editor) = @_;
    my $click = Fieldmapper::action::eresource_link_click->new;
    $click->record($record_id);
    $click->url($url);
    $editor->xact_begin;
    $editor->create_action_eresource_link_click($click) or return 0;
    my $associated_courses = $editor->search_asset_course_module_course_materials({record => $record_id});
    foreach(@{ $associated_courses }) {
        my $course = $editor->retrieve_asset_course_module_course($_->course) or next;
        my $click_course = Fieldmapper::action::eresource_link_click_course->new;
        $click_course->click($click->id);
        $click_course->course($course->id);
        $click_course->course_name($course->name);
        $click_course->course_number($course->course_number);
        $editor->create_action_eresource_link_click_course($click_course);
    }
    $editor->xact_commit;
    return 1;
}

sub _input_is_bad {
    my ($self, $record_id, $url, $referer, $user_agent) = @_;
    return 1 unless ($self->_referer_valid($referer));
    return 1 if Duadua->new($user_agent)->is_bot;
    return 1 unless $self->_url_exists_on_record($url, $record_id);
    return 0;
}

sub _feature_enabled {
    my ($self, $editor) = @_;
    $editor->init;
    my $flag = $editor->retrieve_config_global_flag('opac.eresources.link_click_tracking');
    return ($flag->enabled eq 't');
}

sub _referer_valid {
    my ($self, $referer) = @_;
    return ($referer =~ /eg\/opac\/(record|results)/);
}

# Confirm that the URL and record ID we received from
# the client actually match, since anybody could send
# a request to this endpoint with mismatched data,
# resulting in garbage for anybody running a report
sub _url_exists_on_record {
    my ($self, $url, $record_id) = @_;
    my $root_org = $U->get_org_tree->id;
    my $uris = $apputils->simplereq(
        'open-ils.search',
        'open-ils.search.asset.uri.retrieve_by_bib.atomic',
        $record_id,
        $root_org
    );
    my @matches = grep {$_->href eq $url} @{$uris};
    return scalar @matches;
}

1;
