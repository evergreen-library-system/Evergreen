#!perl
use strict; use warnings;
use Test::More tests => 80;

use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);
use OpenILS::Utils::Fieldmapper;
use Data::Dumper;

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap();

my $U = 'OpenILS::Application::AppUtils';

diag("Test LP 1752334 BadContact");

use constant {
    BR1_ID => 4,
    BR3_ID => 6,
    PHONE => '218-555-0177',
    EMAIL => 'nouser@evergreen-ils.test',
    TESTMESSAGE => '123456 TEST Invalidate Message',
    TESTMESSAGE_ZERO => '0',
    PROFILE => 2, #patrons
};

### Fields that can be invalidated
# email
# day_phone
# evening_phone
# other_phone

my @fields = ('email','day_phone','evening_phone','other_phone');
### Notification data, field index 0 is the penalty type code
my %data =(
    email => [ 31,'nouser1@evergreen-ils.test','nouser2@evergreen-ils.test',
               'nouser3@evergreen-ils.test','nouser4@example.com',
               'nouser5@example.test'],
    day_phone => [32,'218-555-0177','218-555-0129','218-555-0110','218-555-0196','218-555-0181'],
    evening_phone => [33,'701-555-0130','701-555-0104','701-555-0155','701-555-0156','701-555-0143'],
    other_phone => [34,'612-555-0111','612-555-0115','612-555-0157','612-555-0162','612-555-0192'],
);

### Options for invalidation
# Additional Note
# Penalty Org Unit -- ignore
# Notification string - invalidates all occurences of that type of notification.


# We are deliberately NOT using the admin user to check for a perm failure.
my $credentials = {
    username => 'br1mtownsend',
    password => 'demo123',
    type => 'staff'
};

sub remove_penalty_from_patron {
    my $penalty = shift;

    #Fetch the ausp object, we have aump
    my $ausp = $U->simplereq(
        'open-ils.pcrud',
        'open-ils.pcrud.search.ausp.atomic',
        $script->authtoken,
        {id => $penalty->id() }
    );

    #Use the ausp to remove the penalty
    return $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.penalty.remove',
        $script->authtoken,
        $ausp->[0]
    );

}

sub set_notifications {
    my ($user,$i) = @_;
    #Set notifications
    $user->email($data{email}[$i]);
    $user->day_phone($data{day_phone}[$i]);
    $user->evening_phone($data{evening_phone}[$i]);
    $user->other_phone($data{other_phone}[$i]);
    $user->ischanged(1); ## Has to be included or update won't happen

    my $resp = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.patron.update',
        $script->authtoken,
        $user
    );

    return($resp);
}

sub invalidate {
    my ($userid,$type,$note,$ou,$search) = @_;
    my $respi = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.invalidate.'.$type,
        $script->authtoken,
        $userid,
        $note,
        $ou,
        $search
    );
    return $respi
}

sub invalidate_all {
    my ($userid,$note,$ou,$search) = @_;

    foreach( @fields ){
      my $respi = invalidate($userid,$_,$note,$ou, defined($search) ? $data{$_}[$search] : undef);
      is($respi->{textcode},'SUCCESS',$_.' Invalidation was a success');
    }
}

sub check_all_penalties {
    my ($userid,$note,$ou,$search,$i) = @_;

    foreach( @fields ){
        my $respi = check_penalty($userid,$_,$note,$ou,
                                  defined($search) ? $data{$_}[$search] : undef,$i);

        
    }
}

sub check_penalty {
    my ($userid,$type,$note,$ou,$search,$i) = @_;

    my $code = $data{$type}[0]; #Penalty Type Code
    my $ausp = $U->simplereq(
        'open-ils.pcrud',
        'open-ils.pcrud.search.aump.atomic',
        $script->authtoken,
        {usr => $userid, standing_penalty => $code, stop_date => undef },
        {limit => 1}
    );

    my $penalty = $ausp->[0];
    #print ref($penalty)."\n";
    my $message = $data{$type}[$i].(defined($note) ? ' '.$note : '');

    isa_ok($penalty, 'Fieldmapper::actor::usr_message_penalty', 'User Penalty Found -- '.$type);
    is($penalty->message(), $message, $type.' penalty note matches expected format.');

    ## Remove penalty
    ok( ! ref (remove_penalty_from_patron($penalty)), $type.' invalid notification penalty pemoved');
}


# Log in as staff.
my $authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    'Logged in'
) or BAIL_OUT('Must log in');

# Get a cstore editor for later use.
my $editor = $script->editor(authtoken=>$script->authtoken);


# Find a patron to use.
my $aus = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.au.atomic',
    $authtoken,
    {profile => PROFILE, active => 't', home_ou => BR1_ID },
    {limit => 5}
);
ok(@{$aus} == 5, 'Found 5 patrons');
my $user = $aus->[0];
isa_ok(
    $user,
    'Fieldmapper::actor::user',
    'Found a patron'
) or BAIL_OUT('Patron not found');


my $resp = set_notifications($user,1);
isa_ok($resp, 'Fieldmapper::actor::user', 'Notifications added patron 1');

#print Dumper($resp);

## Next user
$user = $aus->[1];
$resp = set_notifications($user,2);
isa_ok($resp, 'Fieldmapper::actor::user', 'Notifications added patron 2');

## Users 3,4,5 have the same notifications set
$user = $aus->[2];
$resp = set_notifications($user,3);
isa_ok($resp, 'Fieldmapper::actor::user', 'Notifications added patron 3');

$user = $aus->[3];
$resp = set_notifications($user,3);
isa_ok($resp, 'Fieldmapper::actor::user', 'Notifications added patron 4');

$user = $aus->[4];
$resp = set_notifications($user,3);
isa_ok($resp, 'Fieldmapper::actor::user', 'Notifications added patron 5');

#Invalidate all notifications for user 1 - default settings
diag("Patron 1 - default invalidate settings");
$user = $aus->[0];
invalidate_all($user->id(),undef,$user->home_ou(),undef);

#Invalidate all notifications for user 2 - added note
diag("Patron 2 - Added note");
$user = $aus->[1];
invalidate_all($user->id(),TESTMESSAGE_ZERO,$user->home_ou(),undef);

#Invalidate notifications for users 3,4,5 - using search method with test message
diag("Patron 3,4,5 - Added note - same contact info");
$user = $aus->[2];
invalidate_all(undef,TESTMESSAGE,$user->home_ou(),3); #Search is index to notification data


## Check and clear standing penalties
diag("Patron 1 - default invalidate settings");
$user = $aus->[0];
check_all_penalties($user->id(),undef,$user->home_ou(),undef,1);

diag("Patron 2 - Added note");
$user = $aus->[1];
check_all_penalties($user->id(),TESTMESSAGE_ZERO,$user->home_ou(),undef,2);

diag("Patron 3 - Added note - same contact info");
$user = $aus->[2];
check_all_penalties($user->id(),TESTMESSAGE,$user->home_ou(),undef,3);

diag("Patron 4 - Added note - same contact info");
$user = $aus->[3];
check_all_penalties($user->id(),TESTMESSAGE,$user->home_ou(),undef,3);

diag("Patron 5 - Added note - same contact info");
$user = $aus->[4];
check_all_penalties($user->id(),TESTMESSAGE,$user->home_ou(),undef,3);

# Logout
$script->logout(); # Not a test, just to be pedantic.
