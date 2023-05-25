package OpenILS::Application::Trigger::Reactor;
use strict; use warnings;
use Encode qw/ encode /;
use Template;
use DateTime;
use DateTime::Format::ISO8601;
use Unicode::Normalize;
use XML::LibXML;
use OpenILS::Utils::DateTime qw/:datetime/;
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

    generate_internal_auth_session => sub {
        my $user_id = shift;
        my $type = shift || 'opac';
        my $ws_id = shift;

        my $args = {
            user_id    => $user_id,
            login_type => $type,
        };

        if ($ws_id) {
            $$args{workstation} = new_editor()->retrieve_actor_workstation($ws_id)->name;
        }

        return $U->simplereq(
            'open-ils.auth_internal',
            'open-ils.auth_internal.session.create',
            $args
        )->{payload}->{authtoken};
    },

    fetch_vbi_queue_summary => sub {
        my $vbi= shift;
        my $type = $vbi->import_type =~ /auth/ ? 'auth' : 'bib';
        my $auth = $_TT_helpers->{generate_internal_auth_session}->( $vbi->owner, 'staff', $vbi->workstation );

        my $method = "open-ils.vandelay.${type}_queue.summary.retrieve";
        return $U->simplereq( 'open-ils.vandelay', $method, $auth, $vbi->queue);
    },

    # turns a date into something TT can understand
    format_date => sub {
        my $date = shift;
        $date = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($date));
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

    jsonify => sub {
        return $_TT_helpers->{escape_json}->( OpenSRF::Utils::JSON->perl2JSON(shift) );
    },

    # encode email headers in UTF-8, per RFC2231
    # now a no-op as we automatically encode the headers in the SendEmail
    # reactor, but we need to leave this here to avoid breaking templates
    # that might have once used it
    escape_email_header => sub {
        my $str = shift;
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

    get_org_unit => sub {
        my $org_id = shift;
        return $org_id if ref $org_id;
        return new_editor()->retrieve_actor_org_unit($org_id);
    },

    get_org_unit_ancestor_at_depth => sub {
      my $org_id = shift;
      my $depth = shift;
      $org_id = $org_id->id if ref $org_id;
      return new_editor()->retrieve_actor_org_unit($U->org_unit_ancestor_at_depth($org_id, $depth));
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

    get_user_setting => sub {
        my ($user_id, $setting) = @_;
        my $val = new_editor()->search_actor_user_setting(
            {usr => $user_id, name => $setting})->[0];
        return undef unless $val; 
        return OpenSRF::Utils::JSON->JSON2perl($val->value);  
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

    get_li_order_ident => sub {
        my $attrs = shift;

        # preferred identifier
        my ($attr) =  grep { $U->is_true($_->order_ident) } @$attrs;
        return $attr if $attr;

        # note we're not using get_li_attr, since we need the 
        # attr object and not just the attr value

        # isbn-13
        ($attr) = grep { 
            $_->attr_name eq 'isbn' and 
            $_->attr_type eq 'lineitem_marc_attr_definition' and
            length($_->attr_value) == 13
        } @$attrs;
        return $attr if $attr;

        for my $name (qw/isbn issn upc/) {
            ($attr) = grep { 
                $_->attr_name eq $name and 
                $_->attr_type eq 'lineitem_marc_attr_definition'
            } @$attrs;
            return $attr if $attr;
        }

        # any 'identifier' attr
        return ( grep { $_->attr_name eq 'identifier' } @$attrs)[0];
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

        if (! defined $sms_notify || $sms_notify eq '' || ! defined $sms_carrier || $sms_carrier eq '') {
            return '';
        }

        my $query = {
            select => {'csc' => ['id','name','email_gateway']},
            from => 'csc',
            where => {id => $sms_carrier}
        };
        my $carriers = new_editor()->json_query($query);

        # If this looks like a pretty-formatted number drop the pretty-formatting
        # Otherwise assume it may be a literal alias instead of a real number
        if ($sms_notify =~ m/^[- ()0-9]*$/) {
            $sms_notify =~ s/[- ()]//g;
        }

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
                $unapi_args->{flesh_limit}, 
            ]
        };

        my $unapi = new_editor()->json_query($query);
        return undef unless @$unapi;
        return $_TT_helpers->{xml_doc}->($unapi->[0]->{'unapi.bre'});
    },

    # input: list of bib bucket items; output: sorted list of unapi_bre objects
    sort_bucket_unapi_bre => sub {
        my ($list, $unapi_args, $sortby, $sortdir) = @_;
        #$logger->info("sort_bucket_unapi_bre unapi_bre params: " . join(', ', map { "$_: $$unapi_args{$_}" } keys(%$unapi_args)));
        my @sorted_list;
        for my $i (@$list) {
            my $xml = $_TT_helpers->{unapi_bre}->($i->target_biblio_record_entry, $unapi_args);
            if ($xml) {
                my $bib = { xml => $xml, id => $i->target_biblio_record_entry };

                $$bib{title} = '';
                for my $part ($xml->findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]')) {
                    $$bib{title} = $$bib{title} . $part->textContent;
                }
                $$bib{titlesort} = lc(substr($$bib{title}, $xml->findnodes('//*[@tag="245"]')->get_node(1)->getAttribute('ind2')))
                    if ($$bib{title});

                $$bib{authorsort} = $$bib{author} = $xml->findnodes('//*[@tag="100"]/*[@code="a"]')->to_literal_delimited(' ');
                $$bib{authorsort} = lc($$bib{authorsort});
                $$bib{item_type} = $xml->findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]')->get_node(1)->getAttribute('coded-value');
                my $p = $xml->findnodes('//*[@tag="260" or @tag="264"]/*[@code="b"]')->get_node(1);
                $$bib{publisher} = $p ? $p->textContent : '';
                my $pd = $xml->findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="date1"]')->get_node(1);
                $$bib{pubdate} = $pd ? $pd->textContent : '';
                $$bib{pubdatesort} = lc($$bib{pubdate});
                $$bib{isbn} = $xml->findnodes('//*[@tag="020"]/*[@code="a"]')->to_literal_delimited(', ');
                $$bib{issn} = $xml->findnodes('//*[@tag="022"]/*[@code="a"]')->to_literal_delimited(', ');
                $$bib{upc} = $xml->findnodes('//*[@tag="024"]/*[@code="a"]')->to_literal_delimited(', ');

                $$bib{holdings} = [];

                for my $vol ($xml->findnodes('//*[local-name()="volume" and @deleted="false" and @opac_visible="true"]')) {
                    my $vol_data = {};
                    $$vol_data{prefix_sort} = $vol->findnodes('.//*[local-name()="call_number_prefix"]')->get_node(1)->getAttribute('label_sortkey');
                    $$vol_data{prefix} = $vol->findnodes('.//*[local-name()="call_number_prefix"]')->get_node(1)->getAttribute('label');
                    $$vol_data{callnumber} = $vol->getAttribute('label');
                    $$vol_data{callnumber_sort} = $vol->getAttribute('label_sortkey');
                    $$vol_data{suffix_sort} = $vol->findnodes('.//*[local-name()="call_number_suffix"]')->get_node(1)->getAttribute('label_sortkey');
                    $$vol_data{suffix} = $vol->findnodes('.//*[local-name()="call_number_suffix"]')->get_node(1)->getAttribute('label');
                    #$logger->info("sort_bucket_unapi_bre found volume: " . join(', ', map { "$_: $$vol_data{$_}" } keys(%$vol_data)));

                    my @copies;
                    for my $cp ($vol->findnodes('.//*[local-name()="copy" and @deleted="false"]')) {
                        my $cp_data = {%$vol_data};
                        my $l = $cp->findnodes('.//*[local-name()="location" and @opac_visible="true"]')->get_node(1);
                        next unless ($l);
                        $$cp_data{location} = $l->textContent;

                        my $s = $cp->findnodes('.//*[local-name()="status" and @opac_visible="true"]')->get_node(1);
                        next unless ($s);
                        $$cp_data{status_label} = $s->textContent;
                        $$cp_data{status_id} = $s->getAttribute('ident');

                        my $c = $cp->findnodes('.//*[local-name()="circ_lib" and @opac_visible="true"]')->get_node(1);
                        next unless ($c);
                        $$cp_data{circ_lib} = $c->getAttribute('name');

                        $$cp_data{barcode} = $cp->getAttribute('barcode');

                        $$cp_data{parts} = '';
                        for my $mp ($cp->findnodes('.//*[local-name()="monograph_part"]')) {
                            $$cp_data{parts} .= ', ' if $$cp_data{parts};
                            $$cp_data{parts} .= $mp->textContent;
                        }
                        push @copies, $cp_data;
                        #$logger->info("sort_bucket_unapi_bre found copy: " . join(', ', map { "$_: $$cp_data{$_}" } keys(%$cp_data)));
                    }
                    if (@copies) {
                        push @{$$bib{holdings}}, @copies;
                    }
                }

                # sort 'em!
                $$bib{holdings} = [ sort {
                    $$a{circ_lib}     cmp $$b{circ_lib} ||
                    $$a{location}     cmp $$b{location} ||
                    $$a{prefix_sort}  cmp $$b{prefix_sort} ||
                    $$a{callnumber_sort}   cmp $$b{callnumber_sort} ||
                    $$a{suffix_sort}  cmp $$b{suffix_sort} ||
                    ($$a{status_id} == 0 ? -1 : 0) ||
                    ($$a{status_id} == 7 ? -1 : 0) ||
                    $$a{status_label} cmp $$b{status_label};
                } @{$$bib{holdings}} ];

                push @sorted_list, $bib;
            }
        }

        if ($sortdir =~ /^d/) {
            return [ sort { $$b{$sortby.'sort'} cmp $$a{$sortby.'sort'} } @sorted_list ];
        }
        return [ sort { $$a{$sortby.'sort'} cmp $$b{$sortby.'sort'} } @sorted_list ];
    },

    # escapes quotes in csv string values
    escape_csv => sub {
        my $string = shift;
        $string =~ s/"/""/og;
        return $string;
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
        $t_o->locale($env->{tt_locale}); 
        $logger->info("trigger: writing " . length($t_o->data) . " bytes to template output");

        $env->{EventProcessor}->editor->xact_begin;
        $t_o = $env->{EventProcessor}->editor->create_action_trigger_event_output( $t_o );

        my $state = (ref $$env{event} eq 'ARRAY') ? $$env{event}->[0]->state : $env->{event}->state;
        my $key = ($error) ? 'error_output' : 'template_output';
        $env->{EventProcessor}->update_state( $state, { $key => $t_o->id } );
    }
    
    return $output;
}

# processes message templates.  Returns template output on success, undef on error
sub run_message_TT {
    my $self = shift;
    my $env = shift;
    return undef unless $env->{usr_message}{template};

    my $error;
    my $output = '';
    my $tt = Template->new;
    # my $tt = Template->new(ENCODING => 'utf8');   # ??
    $env->{helpers} = $_TT_helpers;

    unless( $tt->process(\$env->{usr_message}{template}, $env, \$output) ) {
        $output = undef;
        ($error = $tt->error) =~ s/\n/ /og;
        $logger->error("Error processing Trigger message template: $error");
    }
    
    return $output;
}


1;
