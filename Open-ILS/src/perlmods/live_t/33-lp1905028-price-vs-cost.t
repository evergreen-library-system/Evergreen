#!perl

use Test::More tests => 54;

diag('Item price vs cost settings');

use constant WORKSTATION_NAME => 'BR1-test-33-lp1905028-price-vs-cost.t';
use constant WORKSTATION_LIB => 4;

use strict; use warnings;

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw(:const);
use OpenILS::Application::AppUtils;
our $U = 'OpenILS::Application::AppUtils';

our $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

our $e = new_editor(xact => 1);
$e->init;

setupLogin();

delete_setting(1, OILS_SETTING_DEF_ITEM_PRICE);
delete_setting(1, OILS_SETTING_MIN_ITEM_PRICE);
delete_setting(1, OILS_SETTING_MAX_ITEM_PRICE);
delete_setting(1, OILS_SETTING_CHARGE_LOST_ON_ZERO);
delete_setting(1, OILS_SETTING_PRIMARY_ITEM_VALUE_FIELD);
delete_setting(1, OILS_SETTING_SECONDARY_ITEM_VALUE_FIELD);
$e->commit; $e = new_editor(xact => 1); $e->init;

my $def_price;
my $min_price;
my $max_price;
my $charge_on_0;
my $primary_field;
my $backup_field;
fetchSettings();

my $price;
my $cost;
my $value;

my $copy = $e->search_asset_copy([{ id => 404 }, {} ])->[0];
$copy->clear_price();
$copy->clear_cost();
summarize();
is($value, 0, 'no settings, price = undef, cost = undef, value = 0');

$copy->price(0);
$copy->clear_cost();
summarize();
is($value, 0, 'no settings, price = 0, cost = undef, value = 0');

$copy->price(2);
$copy->clear_cost();
summarize();
is($value, 2, 'no settings, price = 2, cost = undef, value = 2');

$copy->clear_price();
$copy->cost(0);
summarize();
is($value, 0, 'no settings, price = undef, cost = 0, value = 0');

$copy->price(0);
$copy->cost(0);
summarize();
is($value, 0, 'no settings, price = 0, cost = 0, value = 0');

$copy->price(2);
$copy->cost(0);
summarize();
is($value, 2, 'no settings, price = 2, cost = 0, value = 2');

$copy->clear_price();
$copy->cost(3);
summarize();
is($value, 0, 'no settings, price = undef, cost = 3, value = 0');

$copy->price(0);
$copy->cost(0);
summarize();
is($value, 0, 'no settings, price = 0, cost = 3, value = 0');

$copy->price(2);
$copy->cost(0);
summarize();
is($value, 2, 'no settings, price = 2, cost = 3, value = 2');

adjust_setting(1, OILS_SETTING_DEF_ITEM_PRICE, 4);
$e->commit; $e = new_editor(xact => 1); $e->init;
fetchSettings();

$copy->clear_price();
$copy->clear_cost();
summarize();
is($value, 4, 'def item price = 4, price = undef, cost = undef, value = 4');

$copy->price(0);
$copy->clear_cost();
summarize();
is($value, 0, 'def item price = 4, price = 0, cost = undef, value = 0');

$copy->price(2);
$copy->clear_cost();
summarize();
is($value, 2, 'def item price = 4, price = 2, cost = undef, value = 2');

$copy->clear_price();
$copy->cost(0);
summarize();
is($value, 4, 'def item price = 4, price = undef, cost = 0, value = 4');

$copy->price(0);
$copy->cost(0);
summarize();
is($value, 0, 'def item price = 4, price = 0, cost = 0, value = 0');

$copy->price(2);
$copy->cost(0);
summarize();
is($value, 2, 'def item price = 4, price = 2, cost = 0, value = 2');

$copy->clear_price();
$copy->cost(3);
summarize();
is($value, 4, 'def item price = 4, price = undef, cost = 3, value = 4');

$copy->price(0);
$copy->cost(3);
summarize();
is($value, 0, 'def item price = 4, price = 0, cost = 3, value = 0');

$copy->price(2);
$copy->cost(3);
summarize();
is($value, 2, 'def item price = 4, price = 2, cost = 3, value = 2');

delete_setting(1, OILS_SETTING_DEF_ITEM_PRICE);
$e->commit; $e = new_editor(xact => 1); $e->init;
adjust_setting(1, OILS_SETTING_PRIMARY_ITEM_VALUE_FIELD, '"cost"');
$e->commit; $e = new_editor(xact => 1); $e->init;
fetchSettings();

$copy->clear_price();
$copy->clear_cost();
summarize();
is($value, 0, 'primary = cost, price = undef, cost = undef, value = 0');

$copy->price(0);
$copy->clear_cost();
summarize();
is($value, 0, 'primary = cost, price = 0, cost = undef, value = 0');

$copy->price(2);
$copy->clear_cost();
summarize();
is($value, 0, 'primary = cost, price = 2, cost = undef, value = 0');

$copy->clear_price();
$copy->cost(0);
summarize();
is($value, 0, 'primary = cost, price = undef, cost = 0, value = 0');

$copy->price(0);
$copy->cost(0);
summarize();
is($value, 0, 'primary = cost, price = 0, cost = 0, value = 0');

$copy->price(2);
$copy->cost(0);
summarize();
is($value, 0, 'primary = cost, price = 2, cost = 0, value = 0');

$copy->clear_price();
$copy->cost(3);
summarize();
is($value, 3, 'primary = cost, price = undef, cost = 3, value = 3');

$copy->price(0);
$copy->cost(3);
summarize();
is($value, 3, 'primary = cost, price = 0, cost = 3, value = 3');

$copy->price(2);
$copy->cost(3);
summarize();
is($value, 3, 'primary = cost, price = 2, cost = 3, value = 3');

adjust_setting(1, OILS_SETTING_DEF_ITEM_PRICE, 4);
$e->commit; $e = new_editor(xact => 1); $e->init;
adjust_setting(1, OILS_SETTING_PRIMARY_ITEM_VALUE_FIELD, '"cost"');
$e->commit; $e = new_editor(xact => 1); $e->init;
fetchSettings();

$copy->clear_price();
$copy->clear_cost();
summarize();
is($value, 4, 'def item price = 4, primary = cost, price = undef, cost = undef, value = 4');

$copy->price(0);
$copy->clear_cost();
summarize();
is($value, 4, 'def item price = 4, primary = cost, price = 0, cost = undef, value = 4');

$copy->price(2);
$copy->clear_cost();
summarize();
is($value, 4, 'def item price = 4, primary = cost, price = 2, cost = undef, value = 4');

$copy->clear_price();
$copy->cost(0);
summarize();
is($value, 0, 'def item price = 4, primary = cost, price = undef, cost = 0, value = 0');

$copy->price(0);
$copy->cost(0);
summarize();
is($value, 0, 'def item price = 4, primary = cost, price = 0, cost = 0, value = 0');

$copy->price(2);
$copy->cost(0);
summarize();
is($value, 0, 'def item price = 4, primary = cost, price = 2, cost = 0, value = 0');

$copy->clear_price();
$copy->cost(3);
summarize();
is($value, 3, 'def item price = 4, primary = cost, price = undef, cost = 3, value = 3');

$copy->price(0);
$copy->cost(3);
summarize();
is($value, 3, 'def item price = 4, primary = cost, price = 0, cost = 3, value = 3');

$copy->price(2);
$copy->cost(3);
summarize();
is($value, 3, 'def item price = 4, primary = cost, price = 2, cost = 3, value = 3');

adjust_setting(1, OILS_SETTING_DEF_ITEM_PRICE, 4);
$e->commit; $e = new_editor(xact => 1); $e->init;
adjust_setting(1, OILS_SETTING_PRIMARY_ITEM_VALUE_FIELD, '"cost"');
$e->commit; $e = new_editor(xact => 1); $e->init;
adjust_setting(1, OILS_SETTING_SECONDARY_ITEM_VALUE_FIELD, '"price"');
$e->commit; $e = new_editor(xact => 1); $e->init;
fetchSettings();

$copy->clear_price();
$copy->clear_cost();
summarize();
is($value, 4, 'def item price = 4, primary = cost, secondary = price, price = undef, cost = undef, value = 4');

$copy->price(0);
$copy->clear_cost();
summarize();
is($value, 0, 'def item price = 4, primary = cost, secondary = price, price = 0, cost = undef, value = 0');

$copy->price(2);
$copy->clear_cost();
summarize();
is($value, 2, 'def item price = 4, primary = cost, secondary = price, price = 2, cost = undef, value = 2');

$copy->clear_price();
$copy->cost(0);
summarize();
is($value, 0, 'def item price = 4, primary = cost, secondary = price, price = undef, cost = 0, value = 0');

$copy->price(0);
$copy->cost(0);
summarize();
is($value, 0, 'def item price = 4, primary = cost, secondary = price, price = 0, cost = 0, value = 0');

$copy->price(2);
$copy->cost(0);
summarize();
is($value, 0, 'def item price = 4, primary = cost, secondary = price, price = 2, cost = 0, value = 0');

$copy->clear_price();
$copy->cost(3);
summarize();
is($value, 3, 'def item price = 4, primary = cost, secondary = price, price = undef, cost = 3, value = 3');

$copy->price(0);
$copy->cost(3);
summarize();
is($value, 3, 'def item price = 4, primary = cost, secondary = price, price = 0, cost = 3, value = 3');

$copy->price(2);
$copy->cost(3);
summarize();
is($value, 3, 'def item price = 4, primary = cost, secondary = price, price = 2, cost = 3, value = 3');

adjust_setting(1, OILS_SETTING_DEF_ITEM_PRICE, 4);
$e->commit; $e = new_editor(xact => 1); $e->init;
adjust_setting(1, OILS_SETTING_PRIMARY_ITEM_VALUE_FIELD, '"cost"');
$e->commit; $e = new_editor(xact => 1); $e->init;
adjust_setting(1, OILS_SETTING_SECONDARY_ITEM_VALUE_FIELD, '"price"');
$e->commit; $e = new_editor(xact => 1); $e->init;
adjust_setting(1, OILS_SETTING_CHARGE_LOST_ON_ZERO, '"true"');
$e->commit; $e = new_editor(xact => 1); $e->init;
fetchSettings();

$copy->clear_price();
$copy->clear_cost();
summarize();
is($value, 4, 'charge_on_zero = true, def item price = 4, primary = cost, secondary = price, price = undef, cost = undef, value = 4');

$copy->price(0);
$copy->clear_cost();
summarize();
is($value, 4, 'charge_on_zero = true, def item price = 4, primary = cost, secondary = price, price = 0, cost = undef, value = 4');

$copy->price(2);
$copy->clear_cost();
summarize();
is($value, 2, 'charge_on_zero = true, def item price = 4, primary = cost, secondary = price, price = 2, cost = undef, value = 2');

$copy->clear_price();
$copy->cost(0);
summarize();
is($value, 4, 'charge_on_zero = true, def item price = 4, primary = cost, secondary = price, price = undef, cost = 0, value = 4');

$copy->price(0);
$copy->cost(0);
summarize();
is($value, 4, 'charge_on_zero = true, def item price = 4, primary = cost, secondary = price, price = 0, cost = 0, value = 4');

$copy->price(2);
$copy->cost(0);
summarize();
is($value, 2, 'charge_on_zero = true, def item price = 4, primary = cost, secondary = price, price = 2, cost = 0, value = 2');

$copy->clear_price();
$copy->cost(3);
summarize();
is($value, 3, 'charge_on_zero = true, def item price = 4, primary = cost, secondary = price, price = undef, cost = 3, value = 3');

$copy->price(0);
$copy->cost(3);
summarize();
is($value, 3, 'charge_on_zero = true, def item price = 4, primary = cost, secondary = price, price = 0, cost = 3, value = 3');

$copy->price(2);
$copy->cost(3);
summarize();
is($value, 3, 'charge_on_zero = true, def item price = 4, primary = cost, secondary = price, price = 2, cost = 3, value = 3');


####################

sub delete_setting {
    my ($org, $setting) = (shift, shift);
    my $obj = $e->search_actor_org_unit_setting([{ org_unit => $org, name => $setting }, {} ])->[0];
    if (defined $obj) {
        $e->delete_actor_org_unit_setting($obj);
    }
}

sub adjust_setting {
    my ($org, $setting, $value) = (shift, shift, shift);
    my $obj = $e->search_actor_org_unit_setting([{ org_unit => $org, name => $setting }, {} ])->[0];
    my $update = defined $obj;
    $obj = Fieldmapper::actor::org_unit_setting->new unless $update;
    $obj->org_unit($org);
    $obj->name($setting);
    $obj->value($value);
    return $update ? $e->update_actor_org_unit_setting($obj) : $e->create_actor_org_unit_setting($obj);
}

sub fetchSettings {
    $def_price = $U->ou_ancestor_setting_value(1, OILS_SETTING_DEF_ITEM_PRICE, $e);
    $min_price = $U->ou_ancestor_setting_value(1, OILS_SETTING_MIN_ITEM_PRICE, $e);
    $max_price = $U->ou_ancestor_setting_value(1, OILS_SETTING_MAX_ITEM_PRICE, $e);
    $charge_on_0 = $U->ou_ancestor_setting_value(1, OILS_SETTING_CHARGE_LOST_ON_ZERO, $e);
    $primary_field = $U->ou_ancestor_setting_value(1, OILS_SETTING_PRIMARY_ITEM_VALUE_FIELD, $e);
    $backup_field = $U->ou_ancestor_setting_value(1, OILS_SETTING_SECONDARY_ITEM_VALUE_FIELD, $e);
    $def_price = defined $def_price ? $def_price : '';
    $min_price = defined $min_price ? $min_price : '';
    $max_price = defined $max_price ? $max_price : '';
    $charge_on_0 = defined $charge_on_0 ? $charge_on_0 : '';
    $primary_field = defined $primary_field ? $primary_field : '';
    $backup_field = defined $backup_field ? $backup_field : '';
    diag("def_price = $def_price charge_on_0 = $charge_on_0 primary_field = $primary_field backup_field = $backup_field");
}

sub summarize {
    $value = $U->get_copy_price($e, $copy, $copy->call_number);
    $value = length $value ? $value : '';
    $price = length $copy->price ? $copy->price : '';
    $cost = length $copy->cost ? $copy->cost : '';
    #diag("Using settings -> def_price: $def_price min_price: $min_price max_price: $max_price charge_on_0: $charge_on_0 primary: $primary_field backup: $backup_field");
    #diag("Using copy " . $copy->id . " -> price: $price cost: $cost value: $value");
}

sub setupLogin {

    my $workstation = $e->search_actor_workstation([ {name => WORKSTATION_NAME, owning_lib => WORKSTATION_LIB } ])->[0];

    if(!$workstation )
    {
        $script->authenticate({
            username => 'admin',
            password => 'demo123',
            type => 'staff'});
        my $ws = $script->register_workstation(WORKSTATION_NAME,WORKSTATION_LIB);
        $script->logout();
    }

    $script->authenticate({
        username => 'admin',
        password => 'demo123',
        type => 'staff',
        workstation => WORKSTATION_NAME});
}
