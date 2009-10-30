package OpenILS::Application::Trigger::Reactor;
use strict; use warnings;
use Template;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
my $U = 'OpenILS::Application::AppUtils';

sub fourty_two { return 42 }
sub NOOP_True { return 1 }
sub NOOP_False { return 0 }




# helper functions inserted into the TT environment
my $_TT_helpers = {

    # turns a date into something TT can understand
    format_date => sub {
        my $date = shift;
        $date = DateTime::Format::ISO8601->new->parse_datetime(clense_ISO8601($date));
        return sprintf(
            "%0.2d:%0.2d:%0.2d %0.2d-%0.2d-%0.4d",
            $date->hour,
            $date->minute,
            $date->second,
            $date->day,
            $date->month,
            $date->year
        );
    },

    # escapes a string for inclusion in an XML document.  escapes &, <, and > characters
    escape_xml => sub {
        my $str = shift;
        $str =~ s/&/&amp;/sog;
        $str =~ s/</&lt;/sog;
        $str =~ s/>/&gt;/sog;
        return $str;
    },

    # returns the calculated user locale
    get_user_locale => sub { 
        my $user_id = shift;
        return $U->get_user_locale($user_id);
    },

    # returns the calculated copy price
    get_copy_price => sub {
        my $copy_id = shift;
        return $U->get_copy_price(new_editor(), $copy_id);
    },

    # given a copy, returns the title and author in a hash
    get_copy_bib_basics => sub {
        my $copy_id = shift;
        my $copy = new_editor()->retrieve_asset_copy([
            $copy_id,
            {
                flesh => 2,
                flesh_fields => {
                    acp => ['call_number'],
                    acn => ['record']
                }
            }
        ]);
        if($copy->call_number->id == -1) {
            return {
                title => $copy->dummy_title,
                author => $copy->dummy_author,
            };
        } else {
            my $mvr = $U->record_to_mvr($copy->call_number->record);
            return {
                title => $mvr->title,
                author => $mvr->author
            };
        }
    },

    # returns the org unit setting value
    get_org_setting => sub {
        my($org_id, $setting) = @_;
        return $U->ou_ancestor_setting_value($org_id, $setting);
    },
};


# processes templates.  Returns template output on success, undef on error
sub run_TT {
    my $self = shift;
    my $env = shift;
    my $nostore = shift;
    return undef unless $env->{template};

    my $error;
    my $output = '';
    my $tt = Template->new;
    $env->{helpers} = $_TT_helpers;

    unless( $tt->process(\$env->{template}, $env, \$output) ) {
        $output = undef;
        ($error = $tt->error) =~ s/\n/ /og;
        $logger->error("Error processing Trigger template: $error");
    }

    if ( $error or (!$nostore && $output) ) {
        my $t_o = Fieldmapper::action_trigger::event_output->new;
        $t_o->data( ($error) ? $error : $output );
        $t_o->is_error( ($error) ? 't' : 'f' );

        $env->{EventProcessor}->editor->xact_begin;
        $t_o = $env->{EventProcessor}->editor->create_action_trigger_event_output( $t_o );

        my $state = (ref $$env{event} eq 'ARRAY') ? $$env{event}->[0]->state : $env->{event}->state;
        my $key = ($error) ? 'error_output' : 'template_output';
        $env->{EventProcessor}->update_state( $state, { $key => $t_o->id } );
    }
	
    return $output;
}


1;
