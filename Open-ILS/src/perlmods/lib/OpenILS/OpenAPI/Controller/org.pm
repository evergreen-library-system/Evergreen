package OpenILS::OpenAPI::Controller::org;
use OpenILS::OpenAPI::Controller;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Application::AppUtils;

our $VERSION = 1;
our $U = "OpenILS::Application::AppUtils";

sub full_tree {
    my ($c) = @_;
    return one_tree($c, new_editor()->search_actor_org_unit({parent_ou => undef})->[0]->id);
}

sub one_tree {
    my ($c, $org) = @_;

    return new_editor()->retrieve_actor_org_unit([
        $org,
        {flesh => 100, flesh_fields => {aou => [qw/ou_type children/]}}
    ]);
}

sub one_org {
    my ($c, $org) = @_;
    return new_editor()->retrieve_actor_org_unit([
        $org,
        {flesh => 1, flesh_fields => {aou => [qw/ou_type ill_address holds_address mailing_address billing_address/]}}
    ]);
}

sub flat_org_list {
    my ($c, $fields, $ops, $values) = @_;

    my $where = ($fields and @$fields) ?
        OpenILS::OpenAPI::Controller::where_clause_from_triples($fields, $ops, $values) :
        {id => {'!=' => undef}};

    return new_editor()->search_actor_org_unit([
        $where,
        {flesh => 1, flesh_fields => {aou => [qw/ou_type ill_address holds_address mailing_address billing_address/]}}
    ]);
}

1;
