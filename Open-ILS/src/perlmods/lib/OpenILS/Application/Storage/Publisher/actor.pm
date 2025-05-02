package OpenILS::Application::Storage::Publisher::actor;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::actor;
use OpenSRF::Utils::Logger qw/:level/;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::JSON;
use DateTime;           
use DateTime::Format::ISO8601;  
use DateTime::Set;
use DateTime::SpanSet;

my $U = "OpenILS::Application::AppUtils";
my $JSON = "OpenSRF::Utils::JSON";

my $_dt_parser = DateTime::Format::ISO8601->new;    

my $log = 'OpenSRF::Utils::Logger';

sub new_usergroup_id {
    return actor::user->db_Main->selectrow_array("select nextval('actor.usr_usrgroup_seq'::regclass)");
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.group_id.new',
    api_level   => 1,
    method      => 'new_usergroup_id',
);

sub juv_to_adult {
    my $self = shift;
    my $client = shift;
    my $adult_age = shift;

    my $sql = <<"    SQL";
        UPDATE actor.usr
            SET juvenile = FALSE
            WHERE juvenile IS TRUE
            AND deleted IS FALSE
            AND AGE(dob) > COALESCE( BTRIM( (
                    SELECT value FROM actor.org_unit_ancestor_setting(
                    'global.juvenile_age_threshold', home_ou)),'"' ), ?)::INTERVAL
    SQL

    my $sth = actor::user->db_Main->prepare_cached($sql);
    $sth->execute($adult_age);

    return $sth->rows;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.juvenile_to_adult',
    api_level   => 1,
    method      => 'juv_to_adult',
);

sub usr_total_owed {
    my $self = shift;
    my $client = shift;
    my $usr = shift;

    my $sql = <<"    SQL";
            SELECT  x.usr,
                    SUM(COALESCE((SELECT SUM(b.amount) FROM money.billing b WHERE b.voided IS FALSE AND b.xact = x.id),0.0)) -
                        SUM(COALESCE((SELECT SUM(p.amount) FROM money.payment p WHERE p.voided IS FALSE AND p.xact = x.id),0.0))
              FROM  money.billable_xact x
              WHERE x.usr = ? AND x.xact_finish IS NULL
              GROUP BY 1
    SQL

    my (undef,$val) = actor::user->db_Main->selectrow_array($sql, {}, $usr);

    return $val;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.total_owed',
    api_level   => 1,
    method      => 'usr_total_owed',
);

sub usr_breakdown_out {
    my $self = shift;
    my $client = shift;
    my $usr = shift;

    $self->method_lookup('open-ils.storage.transaction.begin')->run();

    my $out_sql = <<"    SQL";
            SELECT  id
              FROM  action.circulation
              WHERE usr = ?
                    AND checkin_time IS NULL
                    AND (  (fine_interval >= '1 day' AND due_date >= 'today')
                        OR (fine_interval < '1 day'  AND due_date > 'now'   ))
                    AND (stop_fines IS NULL
                        OR stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE'))
    SQL

    my $out = actor::user->db_Main->selectcol_arrayref($out_sql, {}, $usr);

    my $od_sql = <<"    SQL";
            SELECT  id
              FROM  action.circulation
              WHERE usr = ?
                    AND checkin_time IS NULL
                    AND (  (fine_interval >= '1 day' AND due_date < 'today')
                        OR (fine_interval < '1 day'  AND due_date < 'now'  ))
                    AND (stop_fines IS NULL
                        OR stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE'))
    SQL

    my $od = actor::user->db_Main->selectcol_arrayref($od_sql, {}, $usr);

    my $lost_sql = <<"    SQL";
            SELECT  id
              FROM  action.circulation
              WHERE usr = ? AND checkin_time IS NULL AND xact_finish IS NULL AND stop_fines = 'LOST'
    SQL

    my $lost = actor::user->db_Main->selectcol_arrayref($lost_sql, {}, $usr);

    my $cl_sql = <<"    SQL";
            SELECT  id
              FROM  action.circulation
              WHERE usr = ? AND checkin_time IS NULL AND stop_fines = 'CLAIMSRETURNED'
    SQL

    my $cl = actor::user->db_Main->selectcol_arrayref($cl_sql, {}, $usr);

    my $lo_sql = <<"    SQL";
            SELECT  id
              FROM  action.circulation
              WHERE usr = ? AND checkin_time IS NULL AND stop_fines = 'LONGOVERDUE'
    SQL

    my $lo = actor::user->db_Main->selectcol_arrayref($lo_sql, {}, $usr);

    $self->method_lookup('open-ils.storage.transaction.rollback')->run();

    if ($self->api_name =~/count$/o) {
        return {    total   => scalar(@$out) + scalar(@$od) + scalar(@$lost) + scalar(@$cl) + scalar(@$lo),
                    out     => scalar(@$out),
                    overdue => scalar(@$od),
                    lost    => scalar(@$lost),
                    claims_returned => scalar(@$cl),
                    long_overdue        => scalar(@$lo),
        };
    }

    return {    out     => $out,
                overdue => $od,
                lost    => $lost,
                claims_returned => $cl,
                long_overdue        => $lo,
    };
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.checked_out',
    api_level   => 1,
    method      => 'usr_breakdown_out',
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.checked_out.count',
    api_level   => 1,
    method      => 'usr_breakdown_out',
);

sub usr_total_out {
    my $self = shift;
    my $client = shift;
    my $usr = shift;

    my $sql = <<"    SQL";
            SELECT  count(*)
              FROM  action.circulation
              WHERE usr = ? AND checkin_time IS NULL
    SQL

    my ($val) = actor::user->db_Main->selectrow_array($sql, {}, $usr);

    return $val;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.total_out',
    api_level   => 1,
    method      => 'usr_total_out',
);

sub calc_proximity {
    my $self = shift;
    my $client = shift;

    local $OpenILS::Application::Storage::WRITE = 1;

    my $delete_sql = <<"    SQL";
        DELETE FROM actor.org_unit_proximity;
    SQL

    my $insert_sql = <<"    SQL";
        INSERT INTO actor.org_unit_proximity (from_org, to_org, prox)
            SELECT  l.id,
                r.id,
                actor.org_unit_proximity(l.id,r.id)
              FROM  actor.org_unit l,
                actor.org_unit r;
    SQL

    actor::org_unit_proximity->db_Main->do($delete_sql);
    actor::org_unit_proximity->db_Main->do($insert_sql);

    return 1;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.org_unit.refresh_proximity',
    api_level   => 1,
    method      => 'calc_proximity',
);

sub make_hoo_spanset {
    my $hoo = shift;
    return undef unless $hoo;

    my $today = shift || DateTime->now;

    my $tz = OpenSRF::AppSession->create('open-ils.actor')->request(
        'open-ils.actor.ou_setting.ancestor_default' => $hoo->id.'' => 'org_unit.timezone'
    )->gather(1) || DateTime::TimeZone->new( name => 'local' )->name;

    my $current_dow = $today->day_of_week_0;

    my $spanset = DateTime::SpanSet->empty_set;
    for my $d ( 0 .. 6 ) {

        my $omethod = 'dow_'.$d.'_open';
        my $cmethod = 'dow_'.$d.'_close';

        my $open = interval_to_seconds($hoo->$omethod());
        my $close = interval_to_seconds($hoo->$cmethod());

        next if ($open == $close && $open == 0);

        my $dow_offset = ($d - $current_dow) * $one_day;
        $close += $one_day if ($close <= $open);

        $spanset = $spanset->union(
            DateTime::Span->new(
                start => $today->clone->add( seconds => $dow_offset + $open  ),
                end   => $today->clone->add( seconds => $dow_offset + $close )
            )
        );
    }

    return $spanset->complement;
}

sub make_closure_spanset {
    my $closures = shift;
    return undef unless $closures;

    my $spanset = DateTime::SpanSet->empty_set;
    for my $k ( keys %$closures ) {
        my $c = $$closures{$k};

        $spanset = $spanset->union(
            DateTime::Span->new(
                start => $_dt_parser->parse_datetime(clean_ISO8601($c->{close_start})),
                end   => $_dt_parser->parse_datetime(clean_ISO8601($c->{close_end}))
            )
        );
    }

    return $spanset;
}

sub new_org_closed_overlap {
    my $self = shift;
    my $client = shift;
    my $ou = shift;
    my $date = shift;
    my $direction = shift || 0;
    my $no_hoo = shift || 0;

    return undef unless ($date && $ou);

    # we're given a date and a direction, find any closures that contain the date
    my $t = actor::org_unit::closed_date->table;
    my $sql = <<"    SQL";
        SELECT  *
          FROM  $t
          WHERE close_end > ?
            AND org_unit = ?
          ORDER BY close_start ASC, close_end DESC
          LIMIT 1
    SQL

    $date = clean_ISO8601($date);

    my $target_date = $_dt_parser->parse_datetime( $date );
    my ($begin, $end) = ($target_date, $target_date);

    # create a spanset from the closures that contain the $date
    my $closure_spanset = make_closure_spanset(
        actor::org_unit::closed_date->db_Main->selectall_hashref( $sql, 'id', {}, $date, $ou )
    );

    if ($closure_spanset && $closure_spanset->intersects( $target_date )) {
        my $closure_intersection = $closure_spanset->intersection( $target_date );
        $begin = $closure_intersection->min;
        $end = $closure_intersection->max;

        if ( $direction <= 0 ) {
            $begin->subtract( minutes => 1 );

            while ( my $_b = new_org_closed_overlap($self, $client, $ou, $begin->strftime('%FT%T%z'), -1, 1 ) ) {
                $begin = $_dt_parser->parse_datetime( clean_ISO8601($_b->{start}) );
            }
        }

        if ( $direction >= 0 ) {
            $end->add( minutes => 1 );

            while ( my $_a = new_org_closed_overlap($self, $client, $ou, $end->strftime('%FT%T%z'), 1, 1 ) ) {
                $end = $_dt_parser->parse_datetime( clean_ISO8601($_a->{end}) );
            }
        }
    }

    if ( !$no_hoo ) {

        my $begin_hoo = make_hoo_spanset(actor::org_unit::hours_of_operation->retrieve($ou), $begin);
        my $end_hoo   = make_hoo_spanset(actor::org_unit::hours_of_operation->retrieve($ou), $end  );


        if ( $begin_hoo && $direction <= 0 && $begin_hoo->intersects($begin) ) {
            my $hoo_intersection = $begin_hoo->intersection( $begin );
            $begin = $hoo_intersection->min;
            $begin->subtract( minutes => 1 );

            while ( my $_b = new_org_closed_overlap($self, $client, $ou, $begin->strftime('%FT%T%z'), -1 ) ) {
                $begin = $_dt_parser->parse_datetime( clean_ISO8601($_b->{start}) );
            }
        }
    
        if ( $end_hoo && $direction >= 0 && $end_hoo->intersects($end) ) {
            my $hoo_intersection = $end_hoo->intersection( $end );
            $end = $hoo_intersection->max;
            $end->add( minutes => 1 );


            while ( my $_b = new_org_closed_overlap($self, $client, $ou, $end->strftime('%FT%T%z'), -1 ) ) {
                $end = $_dt_parser->parse_datetime( clean_ISO8601($_b->{end}) );
            }
        }
    }

    my $start = $begin->strftime('%FT%T%z');
    my $stop = $end->strftime('%FT%T%z');

    return undef if ($start eq $stop);
    return { start => $start, end => $stop };
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.org_unit.closed_date.overlap',
    api_level   => 0,
    method      => 'new_org_closed_overlap',
);

# Check if a set of hours of operation are completely closed.
sub are_all_closed{
    my $hoo = shift;

    for (my $dow = 0; $dow < 7; $dow++)
    {
        
        my $dow_open_meth = "dow_".$dow."_open";
        my $dow_close_meth = "dow_".$dow."_close";
        if ($hoo->$dow_open_meth != "00:00:00" || $hoo->$dow_close_meth != "00:00:00")
            {return  0;}
    }

    return 1;
}

# Recursive method with two parts: first is checking the closures and second is checking the hours of operation
# Direction means whether to check forwards or backwards on the next call. Negative 1 is backwards, positive 1 is forwards - 0 means to check both, backwards then forwards
# Recursion terminates when returning undefined - this means stop changing the start and end times instead of meaning exit with an error.
sub org_closed_overlap {
    my $self = shift;
    my $client = shift;
    my $ou = shift;
    my $date = shift;
    my $direction = shift || 0;
    my $no_hoo = shift || 0;

    return undef unless ($date && $ou);


    my $t = actor::org_unit::closed_date->table;
    my $sql = <<"    SQL";
        SELECT  *
          FROM  $t
          WHERE ? between close_start and close_end
            AND org_unit = ?
          ORDER BY close_start ASC, close_end DESC
          LIMIT 1
    SQL

    $date = clean_ISO8601($date);
    my ($begin, $end) = ($date,$date);

    my $hoo = actor::org_unit::hours_of_operation->retrieve($ou);
    
    # This block checks only the closures - does not consider the hours of operation. That's the next block
    if (my $closure = actor::org_unit::closed_date->db_Main->selectrow_hashref( $sql, {}, $date, $ou )) {
        $begin = clean_ISO8601($closure->{close_start});
        $end = clean_ISO8601($closure->{close_end});

        if ( $direction <= 0 ) {
            $before = $_dt_parser->parse_datetime( $begin );
            $before->subtract( minutes => 1 );

            while ( my $_b = org_closed_overlap($self, $client, $ou, $before->strftime('%FT%T%z'), -1, 1 ) ) {
                $before = $_dt_parser->parse_datetime( clean_ISO8601($_b->{start}) );
            }
            $begin = clean_ISO8601($before->strftime('%FT%T%z'));
        }

        if ( $direction >= 0 ) {
            $after = $_dt_parser->parse_datetime( $end );
            $after->add( minutes => 1 );

            while ( my $_a = org_closed_overlap($self, $client, $ou, $after->strftime('%FT%T%z'), 1, 1 ) ) {
                $after = $_dt_parser->parse_datetime( clean_ISO8601($_a->{end}) );
            }
            $end = clean_ISO8601($after->strftime('%FT%T%z'));
        }
    }

    #This block checks if the org unit's hours are open or not at the given time. If they are, it checks closures.
    if ( !$no_hoo ) {
        #Making sure to ignore this and take the only closure hours from the first block if all hours are closed
        if ( $hoo && !are_all_closed($hoo)) {

            
            if ( $direction <= 0 ) {
                my $begin_dow = $_dt_parser->parse_datetime( $begin )->day_of_week_0;
                my $begin_open_meth = "dow_".$begin_dow."_open";
                my $begin_close_meth = "dow_".$begin_dow."_close";

                my $count = 1;
                while ($hoo->$begin_open_meth eq '00:00:00' and $hoo->$begin_close_meth eq '00:00:00') {
                    $begin = clean_ISO8601($_dt_parser->parse_datetime( $begin )->subtract( days => 1)->strftime('%FT%T%z'));
                    $begin_dow++;
                    $begin_dow %= 7;
                    $count++;
                    last if ($count > 6);
                    $begin_open_meth = "dow_".$begin_dow."_open";
                    $begin_close_meth = "dow_".$begin_dow."_close";
                }

                if (my $closure = actor::org_unit::closed_date->db_Main->selectrow_hashref( $sql, {}, $begin, $ou )) {
                    $before = $_dt_parser->parse_datetime( $begin );
                    $before->subtract( minutes => 1 );
                    while ( my $_b = org_closed_overlap($self, $client, $ou, $before->strftime('%FT%T%z'), -1 ) ) {
                        $before = $_dt_parser->parse_datetime( clean_ISO8601($_b->{start}) );
                    }
                }
            }
    
            if ( $direction >= 0 ) {
                my $end_dow = $_dt_parser->parse_datetime( $end )->day_of_week_0;
                my $end_open_meth = "dow_".$end_dow."_open";
                my $end_close_meth = "dow_".$end_dow."_close";
    
                $count = 1;
                while ($hoo->$end_open_meth eq '00:00:00' and $hoo->$end_close_meth eq '00:00:00') {
                    $end = clean_ISO8601($_dt_parser->parse_datetime( $end )->add( days => 1)->strftime('%FT%T%z'));
                    $end_dow++;
                    $end_dow %= 7;
                    $count++;
                    last if ($count > 6);
                    $end_open_meth = "dow_".$end_dow."_open";
                    $end_close_meth = "dow_".$end_dow."_close";
                }

                if (my $closure = actor::org_unit::closed_date->db_Main->selectrow_hashref( $sql, {}, $end, $ou )) {
                    $after = $_dt_parser->parse_datetime( $end );
                    $after->add( minutes => 1 );

                    while ( my $_a = org_closed_overlap($self, $client, $ou, $after->strftime('%FT%T%z'), 1 ) ) {
                        $after = $_dt_parser->parse_datetime( clean_ISO8601($_a->{end}) );
                    }
                    $end = clean_ISO8601($after->strftime('%FT%T%z'));
                }
            }

        }
    }

    # If there were no changes made to the given date that means no further action should be taken - you've arrived at an acceptable date
    if ($begin eq $date && $end eq $date) {
        return undef;
    }

    return { start => $begin, end => $end };
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.org_unit.closed_date.overlap',
    api_level   => 1,
    method      => 'org_closed_overlap',
);

sub user_by_barcode {
    my $self = shift;
    my $client = shift;
    my @barcodes = shift;

    return undef unless @barcodes;

    for my $card ( actor::card->search( { barcode => @barcodes } ) ) {
        next unless $card;
        if (@barcodes == 1) {
            return $card->usr->to_fieldmapper;
        }
        $client->respond( $card->usr->to_fieldmapper);
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.direct.actor.user.search.barcode',
    api_level   => 1,
    method      => 'user_by_barcode',
    stream      => 1,
    cachable    => 1,
);

sub lost_barcodes {
    my $self = shift;
    my $client = shift;

    my $c = actor::card->table;
    my $p = actor::user->table;

    my $sql = "SELECT c.barcode FROM $c c JOIN $p p ON (c.usr = p.id) WHERE p.card <> c.id";

    my $list = actor::user->db_Main->selectcol_arrayref($sql);
    for my $bc ( @$list ) {
        $client->respond($bc);
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.lost_barcodes',
    api_level   => 1,
    stream      => 1,
    method      => 'lost_barcodes',
    signature    => <<'    NOTE',
        Returns an array of barcodes that belong to lost cards.
        @return array of barcodes
    NOTE
);

sub expired_barcodes {
    my $self = shift;
    my $client = shift;

    my $c = actor::card->table;
    my $p = actor::user->table;

    my $sql = "SELECT c.barcode FROM $c c JOIN $p p ON (c.usr = p.id) WHERE p.expire_date < CURRENT_DATE";

    my $list = actor::user->db_Main->selectcol_arrayref($sql);
    for my $bc ( @$list ) {
        $client->respond($bc);
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.expired_barcodes',
    api_level   => 1,
    stream      => 1,
    method      => 'expired_barcodes',
    signature    => <<'    NOTE',
        Returns an array of barcodes that are currently expired.
        @return array of barcodes
    NOTE
);

sub barred_barcodes {
    my $self = shift;
    my $client = shift;

    my $c = actor::card->table;
    my $p = actor::user->table;

    my $sql = "SELECT c.barcode FROM $c c JOIN $p p ON (c.usr = p.id) WHERE p.barred IS TRUE";

    my $list = actor::user->db_Main->selectcol_arrayref($sql);
    for my $bc ( @$list ) {
        $client->respond($bc);
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.barred_barcodes',
    api_level   => 1,
    stream      => 1,
    method      => 'barred_barcodes',
    signature    => <<'    NOTE',
        Returns an array of barcodes that are currently barred.
        @return array of barcodes
    NOTE
);

sub penalized_barcodes {
    my $self = shift;
    my $client = shift;

    my $c = actor::card->table;
    my $p = actor::user_standing_penalty->table;

    my $sql = <<"    SQL";
        SELECT  DISTINCT c.barcode
          FROM  $c c
            JOIN $p p USING (usr)
            JOIN config.standing_penalty csp ON (csp.id = p.standing_penalty)
          WHERE csp.block_list IS NOT NULL
            AND p.set_date < CURRENT_DATE
            AND (p.stop_date IS NULL OR p.stop_date > CURRENT_DATE);
    SQL

    my $list = actor::user->db_Main->selectcol_arrayref($sql);
    for my $bc ( @$list ) {
        $client->respond($bc);
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.penalized_barcodes',
    api_level   => 1,
    stream      => 1,
    method      => 'penalized_barcodes',
    signature    => <<'    NOTE',
        Returns an array of barcodes that have blocking penalties.
        @return array of barcodes
    NOTE
);

sub _prepare_name_argument {
    # Get rid of extra spaces, accents, and regex characters
    my ($search) = _clean_regex_chars(@_);
    my $sth = actor::user->db_Main->prepare_cached("SELECT evergreen.unaccent_and_squash(?)");
    $sth->execute($search);
    my $r = $sth->fetch;
    return ($r && @$r) ? $r->[0] : $search;
};

sub _clean_regex_chars {
    my ($search) = @_;

    # Escape metacharacters for SIMILAR TO 
    # (http://www.postgresql.org/docs/8.4/interactive/functions-matching.html)
    $search =~ s/\_/\\_/g;
    $search =~ s/\%/\\%/g;
    $search =~ s/\|/\\|/g;
    $search =~ s/\*/\\*/g;
    $search =~ s/\+/\\+/g;
    $search =~ s/\[/\\[/g;
    $search =~ s/\]/\\]/g;
    $search =~ s/\(/\\(/g;
    $search =~ s/\)/\\)/g;

    return $search;
}

sub patron_search {
    my $self = shift;
    my $client = shift;
    my $search = shift;
    my $limit = shift || 1000;
    my $sort = shift;
    my $inactive = shift;
    my $ws_ou = shift;
    my $search_org = shift || $ws_ou;
    my $opt_boundary = shift || 0;
    my $offset = shift || 0;

    my $penalty_sort = 0;

    my $strict_opt_in = OpenSRF::Utils::SettingsClient->new->config_value( share => user => 'opt_in' );

    $sort = ['family_name','first_given_name'] unless ($$sort[0]);
    push @$sort,'id';

    if ($$sort[0] eq 'penalties') {
        shift @$sort;
        $penalty_sort = 1;
    }

    # group 0 = user
    # group 1 = address
    # group 2 = phone, ident
    # group 3 = barcode
    # group 4 = dob
    # group 5 = profile

    # Treatment of name fields depends on whether the org has 
    # diacritic_insensitivity turned on or off.

    my $diacritic_insensitive =  $U->ou_ancestor_setting_value($ws_ou, 'circ.patron_search.diacritic_insensitive');
    # Parse from JSON to Perl boolean (1|0):
    $diacritic_insensitive = ($diacritic_insensitive) ? $JSON->JSON2perl($diacritic_insensitive) : 0;
    my $usr;
    my @usrv;
    my $dob;
    my @dobv;

    # Compile the WHERE component of the actor.usr fields.
    # When a name field is encountered, search both the name field and
    # the alternate version of the name field.
    my @name_fields = qw/prefix first_given_name second_given_name family_name suffix/;
    my @usr_where_parts;

    my @usr_fields = grep { ''.$$search{$_}{group} eq '0' } keys %$search;
    for my $usr_field (@usr_fields) {

        # sprintf template
        my $where_func = $diacritic_insensitive ?
            "evergreen.unaccent_and_squash(CAST(%s AS text)) ~ ?" :
            "evergreen.lowercase(CAST(%s AS text)) ~ ?";

        my $val = $diacritic_insensitive ?
            "^" . _prepare_name_argument($$search{$usr_field}{value}) :
            "^" . _clean_regex_chars($$search{$usr_field}{value});

        if (grep {$_ eq $usr_field} @name_fields) {
            # When searching a name field include an OR search
            # on the alternate version of the same field.

            push(@usr_where_parts, sprintf(
                "($where_func OR $where_func)", $usr_field, "pref_$usr_field")
            );

            # search main field and alt name field with same value.
            push(@usrv, $val);
            push(@usrv, $val);

        } else {

            push(@usr_where_parts, sprintf($where_func, $usr_field));
            push(@usrv, $val);
        }
    }

    $usr = join ' AND ', @usr_where_parts;

    while (($key, $value) = each (%$search)) {
        if($$search{$key}{group} eq '4') {
            my $tval = $key;
            $tval =~ s/dob_//g;
            my $right = "RIGHT('0'|| ";
            my $end = ", 2)";
            $end = $right = '' if lc $tval eq 'year';
            $dob .= $right."CAST(DATE_PART('$tval', dob) AS text)$end ~ ? AND ";
        }
    }
    # Trim the last " AND "
    $dob = substr($dob,0,-4);
    @dobv = map { _clean_regex_chars($$search{$_}{value}) } grep { ''.$$search{$_}{group} eq '4' } keys %$search;
    $usr .= ' AND ' if ( $usr && $dob );
    $usr .= $dob if $dob; # $dob not in-line above in case $usr doesn't have any search vals (only searched for dob)
    push(@usrv, @dobv) if @dobv;

    my $addr = join ' AND ', map { "evergreen.lowercase(CAST($_ AS text)) ~ ?" } grep { ''.$$search{$_}{group} eq '1' } keys %$search;
    my @addrv = map { "^" . _clean_regex_chars($$search{$_}{value}) } grep { ''.$$search{$_}{group} eq '1' } keys %$search;

    # should only be 1 profile sent but this construction makes dealing with the lists simpler.
    my ($prof) = map { $$search{$_}{value} } grep {''.$$search{$_}{group} eq '5' } keys %$search;
    $prof = int($prof) if $prof; # int or out

    my $pv = _clean_regex_chars($$search{phone}{value});
    my $iv = _clean_regex_chars($$search{ident}{value});
    my $nv = _clean_regex_chars($$search{name}{value});
    my $cv = _clean_regex_chars($$search{card}{value});

    my $card = '';
    if ($cv) {
        $card = 'JOIN (SELECT DISTINCT usr FROM actor.card WHERE evergreen.lowercase(barcode) LIKE ?||\'%\') AS card ON (card.usr = users.id)';
        unshift(@usrv, $cv);
    }

    my $phone_cte = '';
    my $phone_join = '';
    my @phonev;

    if ($pv) {
        $phone_join = 'JOIN has_phone_number hpn ON hpn.id = users.id';

        my @ps;

        for my $p (qw/day_phone evening_phone other_phone/) {
            if ($pv =~ /^\d+$/) {
                push @ps, "evergreen.lowercase(REGEXP_REPLACE($p, '[^0-9]', '', 'g')) ~ ?";
            } else {
                push @ps, "evergreen.lowercase($p) ~ ?";
            }
            push @phonev, "^$pv";
        }

        my $main_where = join(' OR ', @ps);

        my $main_query = "SELECT id FROM actor.usr WHERE $main_where";

        my $normalize = ($pv =~ /^\d+$/) ?
            "evergreen.lowercase(REGEXP_REPLACE(value, '[^0-9]', '', 'g')) ~ ?" :
            "evergreen.lowercase(value) ~ ?";

        my $setting_query = <<"        SQL";
            SELECT usr AS id
            FROM actor.usr_setting
            WHERE 
                name IN ('opac.default_phone', 'opac.default_sms_notify')
                AND $normalize
        SQL

        # Prefix the search value with '"?' since user setting phone
        # values may be stored as JSON numbers or (more likely) strings.
        push(@phonev, "^\"?$pv");

        $phone_cte = "WITH has_phone_number AS ($main_query UNION $setting_query)"
    }

    my $ident = '';
    my @is;
    my @identv;
    if ($iv) {
        for my $i ( qw/ident_value ident_value2/ ) {
            push @is, "evergreen.lowercase($i) ~ ?";
            push @identv, "^$iv";
        }
        $ident = '(' . join(' OR ', @is) . ')';
    }

    # name keywords search
    my $name = '';
    my @ns;
    my @namev;
    if ($nv) {
        $name = "name_kw_tsvector @@ to_tsquery(?)";

        # Remove characters that to_tsquery might treat as operators.
        # Note using plainto_tsquery to ignore operators won't let us
        # also do prefix matching.
        $nv =~ s/[^\w\s\.\-']//g;

        my @parts = split(' ', $nv);

        # tsquery on multiple names joined w/ '&'
        # Adding :* gives us prefix matching
        push @namev, join(' & ', map { "$_:*" } @parts);
    }

    my $profile = '';
    my @profv = ();
    if ($prof) {
        $profile = '(profile IN (SELECT id FROM permission.grp_descendants(?)))';
        push @profv, $prof;
    }
    my $usr_where = join ' AND ', grep { $_ } ($usr,$ident,$name,$profile);
    my $addr_where = $addr;


    my $u_table = actor::user->table;
    my $a_table = actor::user_address->table;
    my $opt_in_table = actor::usr_org_unit_opt_in->table;
    my $ou_table = actor::org_unit->table;

    my $u_select = "SELECT id as id FROM $u_table u WHERE $usr_where";
    my $a_select = "SELECT u.id as id FROM $a_table a JOIN $u_table u ON (u.mailing_address = a.id OR u.billing_address = a.id) WHERE $addr_where";

    my $clone_select = '';

    #$clone_select = "JOIN (SELECT cu.id as id FROM $a_table ca ".
    #          "JOIN $u_table cu ON (cu.mailing_address = ca.id OR cu.billing_address = ca.id) ".
    #          "WHERE $addr_where) AS clone ON (clone.id = users.id)" if ($addr_where);

    my $select = '';
    if ($usr_where) {
        if ($addr_where) {
            $select = "$u_select INTERSECT $a_select";
        } else {
            $select = $u_select;
        }
    } elsif ($addr_where) {
        $select = "$a_select";
    }

    return undef if (!$select && !$card && !$phone_cte);

    my $order_by = join ', ', map { 'evergreen.lowercase(CAST(users.'. (split / /,$_)[0] . ' AS text)) ' . (split / /,$_)[1] } @$sort;
    my $distinct_list = join ', ', map { 'evergreen.lowercase(CAST(users.'. (split / /,$_)[0] . ' AS text))' } @$sort;
    my $group_list = $distinct_list;

    if ($inactive) {
        $inactive = '';
    } else {
        $inactive = 'AND users.active = TRUE';
    }

    if (!$ws_ou) {  # XXX This should be required!!
        $ws_ou = actor::org_unit->search( { parent_ou => undef } )->next->id;
    }

    my $descendants = "actor.org_unit_descendants($search_org)";

    my $opt_in_where = '';
    if (lc($strict_opt_in) eq 'true') {
        $opt_in_where = "AND (";
        $opt_in_where .= "EXISTS (select id FROM $opt_in_table ";
        $opt_in_where .= " WHERE org_unit in (select (actor.org_unit_ancestors($ws_ou)).id)";
        $opt_in_where .= " AND usr = users.id) ";
        $opt_in_where .= "OR";
        $opt_in_where .= " users.home_ou IN (select (actor.org_unit_descendants($ws_ou,$opt_boundary)).id))";
    }

    my $penalty_join = '';
    if ($penalty_sort) {
        $distinct_list = 'COUNT(penalties.id), ' . $distinct_list;
        $order_by = 'COUNT(penalties.id) DESC, ' . $order_by;
        unshift @$sort, 'COUNT(penalties.id)';
        $penalty_join = <<"        SQL";
            LEFT JOIN actor.usr_standing_penalty penalties
                ON (users.id = penalties.usr AND (penalties.stop_date IS NULL OR penalties.stop_date > NOW()))
        SQL
    }

    $select = "JOIN ($select) AS search ON (search.id = users.id)" if ($select);
    $select = <<"    SQL";
        $phone_cte
        SELECT  $distinct_list
          FROM  $u_table AS users $card
            JOIN $descendants d ON (d.id = users.home_ou)
            $phone_join
            $select
            $clone_select
            $penalty_join
          WHERE users.deleted = FALSE
            $inactive
            $opt_in_where
          GROUP BY $group_list
          ORDER BY $order_by
          LIMIT $limit
          OFFSET $offset
    SQL

    return actor::user->db_Main->selectcol_arrayref($select, {Columns=>[scalar(@$sort)]}, map {lc($_)} (@phonev,@usrv,@identv,@namev,@profv,@addrv));
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.user.crazy_search',
    api_level   => 1,
    method      => 'patron_search',
);

sub org_unit_list {
    my $self = shift;
    my $client = shift;

    my $select =<<"    SQL";
    SELECT  *
      FROM  actor.org_unit
      ORDER BY CASE WHEN parent_ou IS NULL THEN 0 ELSE 1 END, name;
    SQL

    my $sth = actor::org_unit->db_Main->prepare_cached($select);
    $sth->execute;

    $client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.direct.actor.org_unit.retrieve.all',
    api_level   => 1,
    stream      => 1,
    method      => 'org_unit_list',
);

sub org_unit_type_list {
    my $self = shift;
    my $client = shift;

    my $select =<<"    SQL";
    SELECT  *
      FROM  actor.org_unit_type
      ORDER BY depth, name;
    SQL

    my $sth = actor::org_unit_type->db_Main->prepare_cached($select);
    $sth->execute;

    $client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit_type->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.direct.actor.org_unit_type.retrieve.all',
    api_level   => 1,
    stream      => 1,
    method      => 'org_unit_type_list',
);

sub org_unit_full_path {
    my $self = shift;
    my $client = shift;
    my @binds = @_;

    return undef unless (@binds);

    my $func = 'actor.org_unit_full_path(?)';
    $func = 'actor.org_unit_full_path(?,?)' if (@binds > 1);

    my $sth = actor::org_unit->db_Main->prepare_cached("SELECT * FROM $func");
    $sth->execute(@binds);

    $client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.org_unit.full_path',
    api_level   => 1,
    stream      => 1,
    method      => 'org_unit_full_path',
);

sub org_unit_ancestors {
    my $self = shift;
    my $client = shift;
    my $id = shift;

    return undef unless ($id);

    my $func = 'actor.org_unit_ancestors(?)';

    my $sth = actor::org_unit->db_Main->prepare_cached(<<"    SQL");
        SELECT  f.*
          FROM  $func f
            JOIN actor.org_unit_type t ON (f.ou_type = t.id)
          ORDER BY t.depth, f.name;
    SQL
    $sth->execute(''.$id);

    $client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.org_unit.ancestors',
    api_level   => 1,
    stream      => 1,
    method      => 'org_unit_ancestors',
);

sub org_unit_descendants {
    my $self = shift;
    my $client = shift;
    my $id = shift;
    my $depth = shift;

    return undef unless ($id);

    my $func = 'actor.org_unit_descendants(?)';
    if (defined $depth) {
        $func = 'actor.org_unit_descendants(?,?)';
    }

    my $sth = actor::org_unit->db_Main->prepare_cached("SELECT * FROM $func");
    $sth->execute(''.$id, ''.$depth) if (defined $depth);
    $sth->execute(''.$id) unless (defined $depth);

    $client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.actor.org_unit.descendants',
    api_level   => 1,
    stream      => 1,
    method      => 'org_unit_descendants',
);

sub fleshed_actor_stat_cat {
        my $self = shift;
        my $client = shift;
        my @list = @_;
        
    @list = ($list[0]) unless ($self->api_name =~ /batch/o);

    for my $sc (@list) {
        my $cat = actor::stat_cat->retrieve($sc);
        next unless ($cat);

        my $sc_fm = $cat->to_fieldmapper;
        $sc_fm->entries( [ map { $_->to_fieldmapper } $cat->entries ] );
        $sc_fm->default_entries( [ map { $_->to_fieldmapper } $cat->default_entries ] );

        $client->respond( $sc_fm );

    }

    return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.fleshed.actor.stat_cat.retrieve',
        api_level       => 1,
    argc        => 1,
        method          => 'fleshed_actor_stat_cat',
);

__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.fleshed.actor.stat_cat.retrieve.batch',
        api_level       => 1,
    argc        => 1,
        stream          => 1,
        method          => 'fleshed_actor_stat_cat',
);

#XXX Fix stored proc calls
sub ranged_actor_stat_cat_all {
        my $self = shift;
        my $client = shift;
        my $ou = ''.shift();
        
        return undef unless ($ou);
        my $s_table = actor::stat_cat->table;

        my $select = <<"        SQL";
                SELECT  s.*
                  FROM  $s_table s
                        JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
          ORDER BY name
        SQL

    $fleshed = 0;
    $fleshed = 1 if ($self->api_name =~ /fleshed/o);

        my $sth = actor::stat_cat->db_Main->prepare_cached($select);
        $sth->execute($ou);

        for my $sc ( map { actor::stat_cat->construct($_) } $sth->fetchall_hash ) {
        my $sc_fm = $sc->to_fieldmapper;
        $sc_fm->entries(
            [ $self->method_lookup( 'open-ils.storage.ranged.actor.stat_cat_entry.search.stat_cat' )->run($ou,$sc->id) ]
        ) if ($fleshed);
        $sc_fm->default_entries(
            [ $self->method_lookup( 'open-ils.storage.actor.stat_cat_entry_default.ancestor.retrieve' )->run($ou,$sc->id) ]
        ) if ($fleshed);
        $client->respond( $sc_fm );
    }

        return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.ranged.fleshed.actor.stat_cat.all',
        api_level       => 1,
    argc        => 1,
        stream          => 1,
        method          => 'ranged_actor_stat_cat_all',
);

__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.ranged.actor.stat_cat.all',
        api_level       => 1,
    argc        => 1,
        stream          => 1,
        method          => 'ranged_actor_stat_cat_all',
);

#XXX Fix stored proc calls
sub ranged_actor_stat_cat_entry {
        my $self = shift;
        my $client = shift;
        my $ou = ''.shift();
        my $sc = ''.shift();
        
        return undef unless ($ou);
        my $s_table = actor::stat_cat_entry->table;

        my $select = <<"        SQL";
                SELECT  s.*
                  FROM  $s_table s
                        JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
          WHERE stat_cat = ?
          ORDER BY name
        SQL

        my $sth = actor::stat_cat->db_Main->prepare_cached($select);
        $sth->execute($ou,$sc);

        for my $sce ( map { actor::stat_cat_entry->construct($_) } $sth->fetchall_hash ) {
        my $sce_fm = $sce->to_fieldmapper;
        $client->respond( $sce_fm );
    }

        return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.ranged.actor.stat_cat_entry.search.stat_cat',
        api_level       => 1,
        stream          => 1,
        method          => 'ranged_actor_stat_cat_entry',
);

sub actor_stat_cat_entry_default {
    my $self = shift;
    my $client = shift;
    my $ou = ''.shift();
    my $sc = ''.shift();
        
    return undef unless ($ou);
    my $s_table = actor::stat_cat_entry_default->table;

    my $select = <<"    SQL";
         SELECT  s.*
         FROM  $s_table s
         WHERE owner = ? AND stat_cat = ?
    SQL

    my $sth = actor::stat_cat->db_Main->prepare_cached($select);
    $sth->execute($ou,$sc);

    for my $sced ( map { actor::stat_cat_entry_default->construct($_) } $sth->fetchall_hash ) {
        $client->respond( $sced->to_fieldmapper );
    }

    return undef;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.actor.stat_cat_entry_default.retrieve',
    api_level       => 1,
    stream          => 1,
    method          => 'actor_stat_cat_entry_default',
);

sub actor_stat_cat_entry_default_ancestor {
    my $self = shift;
    my $client = shift;
    my $ou = ''.shift();
    my $sc = ''.shift();
        
    return undef unless ($ou);
    my $s_table = actor::stat_cat_entry_default->table;

    my $select = <<"    SQL";
        SELECT  s.*
        FROM  $s_table s
        JOIN actor.org_unit_ancestors(?) p ON (p.id = s.owner)
        WHERE stat_cat = ?
    SQL

    my $sth = actor::stat_cat->db_Main->prepare_cached($select);
    $sth->execute($ou,$sc);

    my @sced =  map { actor::stat_cat_entry_default->construct($_) } $sth->fetchall_hash;

    my $ancestor_sced = pop @sced;

    $client->respond( $ancestor_sced->to_fieldmapper ) if $ancestor_sced;

    return undef;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.actor.stat_cat_entry_default.ancestor.retrieve',
    api_level       => 1,
    stream          => 1,
    method          => 'actor_stat_cat_entry_default_ancestor',
);

1;
