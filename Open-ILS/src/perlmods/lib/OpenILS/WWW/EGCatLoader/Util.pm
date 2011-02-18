package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

my %cache = (
    map => {aou => {}}, # others added dynamically as needed
    list => {},
    org_settings => {}
);

sub init_ro_object_cache {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    # fetch-on-demand-and-cache subs for commonly used public data
    my @public_classes = qw/ccs aout cifm citm clm cmf crahp/;

    for my $hint (@public_classes) {

        my ($class) = grep {
            $Fieldmapper::fieldmap->{$_}->{hint} eq $hint
        } keys %{ $Fieldmapper::fieldmap };

        my $ident_field =  $Fieldmapper::fieldmap->{$class}->{identity};

	    $class =~ s/Fieldmapper:://o;
	    $class =~ s/::/_/g;

        # copy statuses
        my $list_key = $hint . '_list';
        my $find_key = "find_$hint";

        $ctx->{$list_key} = sub {
            my $method = "retrieve_all_$class";
            $cache{list}{$hint} = $e->$method() unless $cache{list}{$hint};
            return $cache{list}{$hint};
        };
    
        $cache{map}{$hint} = {} unless $cache{map}{$hint};

        $ctx->{$find_key} = sub {
            my $id = shift;
            return $cache{map}{$hint}{$id} if $cache{map}{$hint}{$id}; 
            ($cache{map}{$hint}{$id}) = grep { $_->$ident_field eq $id } @{$ctx->{$list_key}->()};
            return $cache{map}{$hint}{$id};
        };

    }

    $ctx->{aou_tree} = sub {

        # fetch the org unit tree
        unless($cache{aou_tree}) {
            my $tree = $e->search_actor_org_unit([
			    {   parent_ou => undef},
			    {   flesh            => -1,
				    flesh_fields    => {aou =>  ['children']},
				    order_by        => {aou => 'name'}
			    }
		    ])->[0];

            # flesh the org unit type for each org unit
            # and simultaneously set the id => aou map cache
            sub flesh_aout {
                my $node = shift;
                my $ctx = shift;
                $node->ou_type( $ctx->{find_aout}->($node->ou_type) );
                $cache{map}{aou}{$node->id} = $node;
                flesh_aout($_, $ctx) foreach @{$node->children};
            };
            flesh_aout($tree, $ctx);

            $cache{aou_tree} = $tree;
        }

        return $cache{aou_tree};
    };

    # Add a special handler for the tree-shaped org unit cache
    $ctx->{find_aou} = sub {
        my $org_id = shift;
        $ctx->{aou_tree}->(); # force the org tree to load
        return $cache{map}{aou}{$org_id};
    };

    # turns an ISO date into something TT can understand
    $ctx->{parse_datetime} = sub {
        my $date = shift;
        $date = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($date));
        return sprintf(
            "%0.2d:%0.2d:%0.2d %0.2d-%0.2d-%0.4d",
            $date->hour,
            $date->minute,
            $date->second,
            $date->day,
            $date->month,
            $date->year
        );
    };

    # retrieve and cache org unit setting values
    $ctx->{get_org_setting} = sub {
        my($org_id, $setting) = @_;

        $cache{org_settings}{$org_id} = {} 
            unless $cache{org_settings}{$org_id};

        $cache{org_settings}{$org_id}{$setting} = 
            $U->ou_ancestor_setting_value($org_id, $setting)
                unless exists $cache{org_settings}{$org_id}{$setting};

        return $cache{org_settings}{$org_id}{$setting};
    };
}

1;
