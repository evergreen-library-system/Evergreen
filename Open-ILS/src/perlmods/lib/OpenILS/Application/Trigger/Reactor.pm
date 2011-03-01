package OpenILS::Application::Trigger::Reactor;
use strict; use warnings;
use Encode qw/ encode /;
use Template;
use DateTime;
use DateTime::Format::ISO8601;
use Unicode::Normalize;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
my $U = 'OpenILS::Application::AppUtils';

sub fourty_two { return 42 }
sub NOOP_True  { return  1 }
sub NOOP_False { return  0 }



# helper functions inserted into the TT environment
my $_TT_helpers = {

    # turns a date into something TT can understand
    format_date => sub {
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
    },

    # escapes a string for inclusion in an XML document.  escapes &, <, and > characters
    escape_xml => sub {
        my $str = shift;
        $str =~ s/&/&amp;/sog;
        $str =~ s/</&lt;/sog;
        $str =~ s/>/&gt;/sog;
        return $str;
    },

    escape_json => sub {
        my $str = shift;
        $str =~ s/([\x{0080}-\x{fffd}])/sprintf('\u%0.4x',ord($1))/sgoe;
        return $str;
    },

    # encode email headers in UTF-8, per RFC2231
    escape_email_header => sub {
        my $str = shift;
        $str = encode("MIME-Header", $str);
        return $str;
    },

    # strip non-ASCII characters after splitting base characters and diacritics
    # least common denominator for EDIFACT messages using the UNOB character set
    force_jedi_unob => sub {
        my $str = shift;
        $str = NFD($str);
        $str =~ s/[\x{0080}-\x{fffd}]//g;
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
        return $U->get_copy_price(new_editor(xact=>1), $copy_id);
    },

    # given a copy, returns the title and author in a hash
    get_copy_bib_basics => sub {
        my $copy_id = shift;
        my $copy = new_editor(xact=>1)->retrieve_asset_copy([
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
                title  => $copy->dummy_title,
                author => $copy->dummy_author,
            };
        } else {
            my $mvr = $U->record_to_mvr($copy->call_number->record);
            return {
                title  => $mvr->title,
                author => $mvr->author
            };
        }
    },

    # returns the org unit setting value
    get_org_setting => sub {
        my($org_id, $setting) = @_;
        return $U->ou_ancestor_setting_value($org_id, $setting);
    },

    # This basically greps/maps out ths isbn string values, but also promotes the first isbn-13 to the
    # front of the line (so that the EDI translator takes it as primary) if there is one.
    get_li_isbns => sub {
        my $attrs = shift;
        my @isbns;
        my $primary;
        foreach (@$attrs) {
            $_->attr_name eq 'isbn' or next;
            my $val = $_->attr_value;
            if (! $primary and length($val) == 13) {
                $primary = $val;
            } else {
                push @isbns, $val;
            }
        }
        $primary and unshift @isbns, $primary;
        $logger->debug("get_li_isbns returning isbns: " . join(', ', @isbns));
        return @isbns;
    },

    # helpers.get_li_attr('isbn_13', li.attributes)
    # returns matching line item attribute, or undef
    get_li_attr => sub {
        my $name = shift or return;     # the first arg is always the name
        my ($type, $attr) = (scalar(@_) == 1) ? (undef, $_[0]) : @_;
        # if the next is the last, it's the attributes, otherwise type
        # use Data::Dumper; $logger->warn("get_li_attr: " . Dumper($attr));
        ($name and @$attr) or return;
        my $length;
        $name =~ s/^(\D+)_(\d+)$/$1/ and $length = $2;
        foreach (@$attr) {
            $_->attr_name eq $name or next;
            next if $length and $length != length($_->attr_value);
            return $_->attr_value if (! $type) or $type eq $_->attr_type;
        }
        return;
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
    # my $tt = Template->new(ENCODING => 'utf8');   # ??
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
        $logger->info("trigger: writing " . length($t_o->data) . " bytes to template output");

        $env->{EventProcessor}->editor->xact_begin;
        $t_o = $env->{EventProcessor}->editor->create_action_trigger_event_output( $t_o );

        my $state = (ref $$env{event} eq 'ARRAY') ? $$env{event}->[0]->state : $env->{event}->state;
        my $key = ($error) ? 'error_output' : 'template_output';
        $env->{EventProcessor}->update_state( $state, { $key => $t_o->id } );
    }
	
    return $output;
}


1;
