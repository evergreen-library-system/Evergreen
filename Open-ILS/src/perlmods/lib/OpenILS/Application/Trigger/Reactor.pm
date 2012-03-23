package OpenILS::Application::Trigger::Reactor;
use strict; use warnings;
use Encode qw/ encode /;
use Template;
use DateTime;
use DateTime::Format::ISO8601;
use Unicode::Normalize;
use XML::LibXML;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::JSON;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
my $U = 'OpenILS::Application::AppUtils';

sub fourty_two { return 42 }
sub NOOP_True  { return  1 }
sub NOOP_False { return  0 }


# To be used in two places within $_TT_helpers.  Without putting the code out
# here, we can't really reuse it within that structure.
sub get_li_attr {
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
}

# helper functions inserted into the TT environment
my $_TT_helpers; # define first so one helper can use another
$_TT_helpers = {

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

    # given a call number, returns the copy location with the most copies
    get_most_populous_location => sub {
        my $acn_id = shift;

        # FIXME - there's probably a more efficient way to do this with json_query/SQL
        my $call_number = new_editor(xact=>1)->retrieve_asset_call_number([
            $acn_id,
            {
                flesh => 1,
                flesh_fields => {
                    acn => ['copies']
                }
            }
        ]);
        my %location_count = (); my $winning_location; my $winning_total;
        use Data::Dumper;
        foreach my $copy (@{$call_number->copies()}) {
            if (! defined $location_count{ $copy->location() }) {
                $location_count{ $copy->location() } = 1;
            } else {
                $location_count{ $copy->location() } += 1;
            }
            if ($location_count{ $copy->location() } > $winning_total) {
                $winning_total = $location_count{ $copy->location() };
                $winning_location = $copy->location();
            }
        }

        my $location = new_editor(xact=>1)->retrieve_asset_copy_location([
            $winning_location, {}
        ]);
        return $location;
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
    get_li_attr => \&get_li_attr,

    # get_li_attr_jedi() returns a JSON-encoded string without the enclosing
    # quotes.  The function also removes other characters from the string
    # that the EDI translator doesn't like.
    #
    # This *always* return a string, so don't use this in conditional
    # expressions in your templates unless you really mean to.
    get_li_attr_jedi => sub {
        # This helper has to mangle data in at least three interesting ways.
        #
        # 1) We'll be receiving data that may already have some \-escaped
        # characters.
        #
        # 2) We need our output to be valid JSON.
        #
        # 3) We need our output to yield valid and unproblematic EDI when
        # passed through edi4r by the edi_pusher.pl script.

        my $value = get_li_attr(@_);

        {
            no warnings 'uninitialized';
            $value .= "";   # force to string
        };

        # Here we can add any number of special case transformations to
        # avoid problems with the EDI translator (or bad JSON).

        # Typical vendors dealing with EDIFACT (or is the problem with
        # our EDI translator itself?) would seem not to want
        # any characters outside the ASCII range, so trash them.
        $value =~ s/[^[:ascii:]]//g;

        # Remove anything somehow already JSON-escaped as a Unicode
        # character. (even though for our part, we haven't JSON-escaped
        # anything yet).
        $value =~ s/\\u[0-9a-f]{4}//g;

        # What the heck, get rid of [ ] too (although I couldn't get them
        # to cause any problems for me, problems have been reported. See
        # LP #812593).
        $value =~ s/[\[\]]//g;

        $value = OpenSRF::Utils::JSON->perl2JSON($value);

        # Existing action/trigger templates expect an unquoted string.
        $value =~ s/^"//g;
        $value =~ s/"$//g;

        # The ? character, if in the final position of a string, breaks
        # the translator. + or ' or : could be problematic, too. And we must
        # avoid leaving a hanging \.
        while ($value =~ /[\\\?\+':]$/) {
            chop $value;
        }

        return $value;
    },

    get_queued_bib_attr => sub {
        my $name = shift or return;     # the first arg is always the name
        my ($attr) = @_;
        # use Data::Dumper; $logger->warn("get_queued_bib_attr: " . Dumper($attr));
        ($name and @$attr) or return;

        my $query = {
            select => {'vqbrad' => ['id']},
            from => 'vqbrad',
            where => {code => $name}
        };

        my $def_ids = new_editor()->json_query($query);
        @$def_ids or return;

        my $length;
        $name =~ s/^(\D+)_(\d+)$/$1/ and $length = $2;
        foreach (@$attr) {
            $_->field eq @{$def_ids}[0]->{id} or next;
            next if $length and $length != length($_->attr_value);
            return $_->attr_value;
        }
        return;
    },

    get_queued_auth_attr => sub {
        my $name = shift or return;     # the first arg is always the name
        my ($attr) = @_;
        # use Data::Dumper; $logger->warn("get_queued_auth_attr: " . Dumper($attr));
        ($name and @$attr) or return;

        my $query = {
            select => {'vqarad' => ['id']},
            from => 'vqarad',
            where => {code => $name}
        };

        my $def_ids = new_editor()->json_query($query);
        @$def_ids or return;

        my $length;
        $name =~ s/^(\D+)_(\d+)$/$1/ and $length = $2;
        foreach (@$attr) {
            $_->field eq @{$def_ids}[0]->{id} or next;
            next if $length and $length != length($_->attr_value);
            return $_->attr_value;
        }
        return;
    },

    csv_datum => sub {
        my ($str) = @_;

        if ($str =~ /\,/ || $str =~ /"/) {
            $str =~ s/"/""/g;
            $str = '"' . $str . '"';
        }

        return $str;
    },


    bre_open_hold_count => sub {
        my $bre_id = shift;
        return 0 unless $bre_id;
        return $U->simplereq(
            'open-ils.circ',
            'open-ils.circ.bre.holds.count', $bre_id);
    },

    xml_doc => sub {
        my ($str) = @_;
        return $str ? (new XML::LibXML)->parse_string($str) : undef;
    },

    # returns an email addresses derived from sms_carrier and sms_notify
    get_sms_gateway_email => sub {
        my $sms_carrier = shift;
        my $sms_notify = shift;

        if (! defined $sms_notify || $sms_notify eq '') {
            return '';
        }

        my $query = {
            select => {'csc' => ['id','name','email_gateway']},
            from => 'csc',
            where => {id => $sms_carrier}
        };
        my $carriers = new_editor()->json_query($query);

        my @addresses = ();
        foreach my $carrier ( @{ $carriers } ) {
            my $address = $carrier->{email_gateway};
            $address =~ s/\$number/$sms_notify/g;
            push @addresses, $address;
        }

        return join(',',@addresses);
    },

    unapi_bre => sub {
        my ($bre_id, $unapi_args) = @_;
        $unapi_args ||= {};
        $unapi_args->{flesh} ||= '{}',

        my $query = { 
            from => [
                'unapi.bre', $bre_id, 'marcxml','record', 
                $unapi_args->{flesh}, 
                $unapi_args->{site}, 
                $unapi_args->{depth}, 
                $unapi_args->{flesh_depth}, 
            ]
        };

        my $unapi = new_editor()->json_query($query);
        return undef unless @$unapi;
        return $_TT_helpers->{xml_doc}->($unapi->[0]->{'unapi.bre'});
    }
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
