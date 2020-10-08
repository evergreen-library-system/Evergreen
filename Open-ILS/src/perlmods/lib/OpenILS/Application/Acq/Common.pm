package OpenILS::Application::Acq::Common;
use strict; use warnings;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

# retrieves a lineitem, fleshes its PO and PL, checks perms
# returns ($li, $evt, $org)
sub fetch_and_check_li {
    my ($class, $e, $li_id, $perm_mode) = @_;
    $perm_mode ||= 'read';

    my $li = $e->retrieve_acq_lineitem([
        $li_id,
        {   flesh => 1,
            flesh_fields => {jub => ['purchase_order', 'picklist']}
        }
    ]) or return (undef, $e->die_event);

    my $org;
    if(my $po = $li->purchase_order) {
        $org = $po->ordering_agency;
        my $perms = ($perm_mode eq 'read') ? 'VIEW_PURCHASE_ORDER' : 'CREATE_PURCHASE_ORDER';
        return ($li, $e->die_event) unless $e->allowed($perms, $org);

    } elsif(my $pl = $li->picklist) {
        $org = $pl->org_unit;
        my $perms = ($perm_mode eq 'read') ? 'VIEW_PICKLIST' : 'CREATE_PICKLIST';
        return ($li, $e->die_event) unless $e->allowed($perms, $org);
    }

    return ($li, undef, $org);
}

sub li_existing_copies {
    my ($class, $e, $li_id) = @_;

    my ($li, $evt, $org) = $class->fetch_and_check_li($e, $li_id);
    return 0 if $evt;

    # No fuzzy matching here (e.g. on ISBN).  Only exact matches are supported.
    return 0 unless $li->eg_bib_id;

    my $counts = $e->json_query({
        select => {acp => [{
            column => 'id', 
            transform => 'count', 
            aggregate => 1
        }]},
        from => {
            acp => {
                acqlid => {
                    fkey => 'id',
                    field => 'eg_copy_id',
                    type => 'left'
                },
                acn => {join => {bre => {}}}
            }
        },
        where => {
            '+bre' => {id => $li->eg_bib_id},
            # don't count copies linked to the lineitem in question
            '+acqlid' => {
                '-or' => [
                    {lineitem => undef},
                    {lineitem => {'<>' => $li_id}}
                ]
            },
            '+acn' => {
                owning_lib => $U->get_org_descendants($org)
            },
            # NOTE: should the excluded copy statuses be an AOUS?
            '+acp' => {status => {'not in' => [3, 4, 13, 17]}}
        }
    });

    return $counts->[0]->{id};
}



