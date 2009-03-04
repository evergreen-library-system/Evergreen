package OpenILS::Application::Trigger::Reactor::MarkItemLost;
use base 'OpenILS::Application::Trigger::Reactor';
use strict; use warnings;
use Error qw/:try/;
use Data::Dumper;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Cat::AssetCommon;
$Data::Dumper::Indent = 0;


sub ABOUT {
    return <<ABOUT;
    
    Marks circulation and corresponding item as lost.  This uses
    the standard mark-lost functionality, creating billings where appropriate.

    Required event parameters:
        "editor" which points to a user ID.  This is the user that effectively
        performs the action.  For example, when the copy status is updated,
        this user is entered as the last editor of the copy.

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;
    my $e = new_editor(xact => 1);
    $e->requestor($e->retrieve_actor_user($$env{params}{editor}));

    my $evt = OpenILS::Application::Cat::AssetCommon->set_item_lost($e, $$env{target}->target_copy);
    if($evt) {
        $logger->error("trigger: MarkItemLost failed with event ".$evt->{textcode});
        return 0;
    }

    $e->commit;
    return 1;
}

1;
