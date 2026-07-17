package OpenILS::Application::Storage::Publisher::action;
use parent qw/OpenILS::Application::Storage::Publisher/;
use strict;
use warnings;
use OpenSRF::Utils::Logger qw/:level :logger/;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenSRF::Utils::JSON;
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::PermitHold;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Utils::Penalty;
use OpenILS::Application::Circ::CircCommon;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

# Used in build_hold_sort_clause().  See the hash %order_by_sprintf_args in
# that sub to confirm what gets used to replace the formatters, and see
# nearest_hold() for the main body of the SQL query that these go into.
my %HOLD_SORT_ORDER_BY = (
    pprox => 'p.prox',
    hprox => 'actor.org_unit_proximity(%d, h.pickup_lib)',  # $cp->call_number->owning_lib
    owning_lib_to_home_lib_prox => 'actor.org_unit_proximity(%d, au.home_ou)',  # $cp->call_number->owning_lib
    aprox => 'COALESCE(hm.proximity, p.prox)',
    approx => 'action.hold_copy_calculated_proximity(h.id, %d, %d)', # $cp,$here
    priority => 'pgt.hold_priority',
    cut => 'CASE WHEN h.cut_in_line IS TRUE THEN 0 ELSE 1 END',
    depth => 'h.selection_depth DESC',
    rtime => 'h.request_time',
    htime => q!
        CASE WHEN
            last_event_on_copy.place <> %d AND
            copy_has_not_been_home.result
        THEN actor.org_unit_proximity(%d, h.pickup_lib)
        ELSE 999
        END
    !,  # $cp->call_number->owning_lib x 2
    shtime => q!
        CASE WHEN
            last_event_on_copy.place <> %d AND
            copy_has_not_been_home_even_to_idle.result
        THEN actor.org_unit_proximity(%d, h.pickup_lib)
        ELSE 999
        END
    !,  # $cp->call_number->owning_lib x 2
);


sub isTrue {
    my $v = shift || '0';
    return 1 if ($v == 1);
    return 1 if ($v =~ /^t/io);
    return 1 if ($v =~ /^y/io);
    return 0;
}

sub ou_ancestor_setting_value_or_cache {
    # cache should be specific to setting
    my ($e, $org_id, $setting, $cache) = @_;

    if (not exists $cache->{$org_id}) {
        my $r = $U->ou_ancestor_setting(
            $org_id, $setting, $e # undef $e is ok
        );

        if ($r) {
            $cache->{$org_id} = $r->{value};
        } else {
            $cache->{$org_id} = undef;
        }
    }
    return $cache->{$org_id};
}

my $parser = DateTime::Format::ISO8601->new;
my $log = 'OpenSRF::Utils::Logger';

sub open_noncat_circs {
    my $self = shift;
    my $client = shift;
    my $user = shift;

    my $a = action::non_cataloged_circulation->table;
    my $c = config::non_cataloged_type->table;

    my $sql = <<"    SQL";
        SELECT  a.id
          FROM  $a a
            JOIN $c c ON (a.item_type = c.id)
          WHERE a.circ_time + c.circ_duration > current_timestamp
            AND a.patron = ?
    SQL

    return action::non_cataloged_circulation->db_Main->selectcol_arrayref($sql, {}, $user);
}
__PACKAGE__->register_method(
    api_name  => 'open-ils.storage.action.open_non_cataloged_circulation.user',
    method    => 'open_noncat_circs',
    api_level => 1,
    argc      => 1,
);


sub ou_hold_requests {
    my $self = shift;
    my $client = shift;
    my $ou = shift;

    my $h_table = action::hold_request->table;
    my $c_table = asset::copy->table;
    my $o_table = actor::org_unit->table;

    my $SQL = <<"    SQL";
        SELECT  h.id
          FROM  $h_table h
            JOIN $c_table cp ON (cp.id = h.current_copy)
            JOIN $o_table ou ON (ou.id = cp.circ_lib)
          WHERE ou.id = ?
            AND h.capture_time IS NULL
            AND h.cancel_time IS NULL
            AND (h.expire_time IS NULL OR h.expire_time > NOW())
          ORDER BY h.request_time
    SQL

    my $sth = action::hold_request->db_Main->prepare_cached($SQL);
    $sth->execute($ou);

    $client->respond($_) for (
        map {
            $self
                ->method_lookup('open-ils.storage.direct.action.hold_request.retrieve')
                ->run($_)
        } map {
            $_->[0]
        } @{ $sth->fetchall_arrayref }
    );
    return undef;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.targeted_hold_request.org_unit',
    api_level       => 1,
    argc        => 1,
    stream      => 1,
    method          => 'ou_hold_requests',
);


# partition -- if set, an 'undef' will be inserted into the result list
# between the last circulation and the first reservation.  This is
# useful in conjunction with 'idlist' so the caller can tell what type 
# of transaction the ID refers to without having to query the DB.
# skip_no_fines - filter out transactions which will never be billed, 
# e.g. circs with a $0 max fine or $0 recurring fine.
sub overdue_circs {
    my $upper_interval = shift || '1 millennium';
    my $idlist = shift;
    my $partition = shift;
    my $skip_no_fines = shift;

    # Only retrieve ID's in the initial query if that's all the caller needs.
    my $contents = $idlist ? 'id' : '*';

    my $fines_filter = $skip_no_fines ? 
        'AND recurring_fine <> 0 AND max_fine <> 0' : '';

    my $c_t = action::circulation->table;

    my $sql = <<"    SQL";
        SELECT  $contents
          FROM  $c_t
          WHERE stop_fines IS NULL
            $fines_filter
            AND due_date < ( CURRENT_TIMESTAMP - grace_period )
            AND fine_interval < ?::INTERVAL
    SQL

    my $sth = action::circulation->db_Main->prepare_cached($sql);
    $sth->execute($upper_interval);

    my @circs = map { $idlist ? $_->{id} : action::circulation->construct($_) } $sth->fetchall_hash;

    push (@circs, undef) if $partition;

    $fines_filter = $skip_no_fines ? 
        'AND fine_amount <> 0 AND max_fine <> 0' : '';

    $c_t = booking::reservation->table;
    $sql = <<"    SQL";
        SELECT  $contents
          FROM  $c_t
          WHERE return_time IS NULL
            $fines_filter
            AND end_time < ( CURRENT_TIMESTAMP )
            AND fine_interval IS NOT NULL
            AND cancel_time IS NULL
    SQL

    $sth = action::circulation->db_Main->prepare_cached($sql);
    $sth->execute();

    push @circs, map { $idlist ? $_->{id} : booking::reservation->construct($_) } $sth->fetchall_hash;

    return @circs;
}

sub complete_reshelving {
    my $self = shift;
    my $client = shift;
    my $window = shift;

    local $OpenILS::Application::Storage::WRITE = 1;

    throw OpenSRF::EX::InvalidArg ("I need an interval of more than 0 seconds!")
        unless (interval_to_seconds( $window ));

    my $cp = asset::copy->table;

    my $sql = <<"    SQL";
        UPDATE  $cp
          SET   status = 0
          WHERE id IN (
            SELECT cp.id 
            FROM  $cp cp
            WHERE cp.status = 7
                AND cp.status_changed_time < NOW() - CAST( COALESCE( BTRIM( (SELECT value FROM actor.org_unit_ancestor_setting('circ.reshelving_complete.interval', cp.circ_lib)),'"' ), ? )  AS INTERVAL)
          )
          AND status = 7
    SQL
    my $sth = action::circulation->db_Main->prepare_cached($sql);
    $sth->execute($window);

    return $sth->rows;

}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.circulation.reshelving.complete',
    api_level       => 1,
    argc        => 1,
    method          => 'complete_reshelving',
);

sub mark_longoverdue {
    my $self = shift;
    my $client = shift;
    my $window = shift;

    local $OpenILS::Application::Storage::WRITE = 1;

    throw OpenSRF::EX::InvalidArg ("I need an interval of more than 0 seconds!")
        unless (interval_to_seconds( $window ));

    my $setting = actor::org_unit_setting->table;
    my $circ = action::circulation->table;

    my $sql = <<"    SQL";
        UPDATE  $circ
          SET   stop_fines = 'LONGOVERDUE',
            stop_fines_time = now()
          WHERE id IN (
            SELECT  circ.id
                      FROM  $circ circ
                            LEFT JOIN $setting setting
                                ON (circ.circ_lib = setting.org_unit AND setting.name = 'circ.long_overdue.interval')
                      WHERE circ.checkin_time IS NULL AND (stop_fines IS NULL OR stop_fines NOT IN ('LOST','LONGOVERDUE'))
                            AND AGE(circ.due_date) > CAST( COALESCE( BTRIM( setting.value,'"' ), ? )  AS INTERVAL)
                  )
    SQL

    my $sth = action::circulation->db_Main->prepare_cached($sql);
    $sth->execute($window);

    return $sth->rows;

}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.circulation.long_overdue',
    api_level       => 1,
    argc        => 1,
    method          => 'mark_longoverdue',
);

sub auto_thaw_frozen_holds {
    my $self = shift;
    my $client = shift;

    local $OpenILS::Application::Storage::WRITE = 1;

    my $holds = action::hold_request->table;

    my $sql = "UPDATE $holds SET frozen = FALSE WHERE frozen IS TRUE AND thaw_date < NOW();";

    my $sth = action::hold_request->db_Main->prepare_cached($sql);
    $sth->execute();

    return $sth->rows;

}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.hold_request.thaw_expired_frozen',
    api_level       => 1,
    stream      => 0,
    argc        => 0,
    method          => 'auto_thaw_frozen_holds',
);

sub grab_overdue {
    my $self = shift;
    my $client = shift;

    my $idlist = $self->api_name =~/id_list/o ? 1 : 0;
    
    $client->respond( $idlist ? $_ : $_->to_fieldmapper ) 
        for ( overdue_circs('', $idlist, undef, 1) );

    return undef;

}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.circulation.overdue',
    api_level       => 1,
    stream          => 1,
    method          => 'grab_overdue',
    signature       => q/
        Return list of overdue circulations and reservations to be used for fine generation.
        Despite the name, this is not a generic method for retrieving all overdue loans,
        as it excludes loans that have already hit the maximum fine limit
        and transactions which do not accrue fines.
/,
);
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.circulation.overdue.id_list',
    api_level       => 1,
    stream      => 1,
    method          => 'grab_overdue',
);

sub get_hold_sort_order {
    my ($ou) = @_;

    my $dbh = action::hold_request->db_Main;

    # The purpose of this function is to return column names in a DB-configured
    # order, so it won't do to add columns here or change column names unless
    # you also change the expectation of anything calling this function.

    my $row = $dbh->selectrow_hashref(
        q!
        SELECT
            cbho.pprox, cbho.hprox, cbho.owning_lib_to_home_lib_prox, cbho.aprox,
            cbho.approx, cbho.priority, cbho.cut, cbho.depth, cbho.htime,
            cbho.shtime, cbho.rtime
        FROM config.best_hold_order cbho
        WHERE id = (
            SELECT oils_json_to_text(value)::INT
            FROM actor.org_unit_ancestor_setting('circ.hold_capture_order', ?)
        )
        !, undef, $ou
    ) || {
        pprox => 1, hprox => 8, aprox => 2, priority => 3,
        cut => 4, depth => 5, htime => 7, rtime => 6
    };

    # Return only the keys of our hash, sorted by value,
    # keys for null values omitted.
    return [
        sort { $row->{$a} <=> $row->{$b} } (
          grep { defined $row->{$_} } keys %$row
        )
    ];
}

# Returns an ORDER BY clause
# *and* a string with a CTE expression to precede the nearest-hold SQL query
# *and* a string with extra JOIN statements needed
sub build_hold_sort_clause {
    my ($columns, $cp, $here) = @_;

    my %order_by_sprintf_args = (
        hprox => [$cp->call_number->owning_lib],
        owning_lib_to_home_lib_prox => [$cp->call_number->owning_lib],
        approx => [$cp->id, $here],
        htime => [$cp->call_number->owning_lib, $cp->call_number->owning_lib],
        shtime => [$cp->call_number->owning_lib, $cp->call_number->owning_lib]
    );

    my @clauses;
    my $ctes_needed = 0;
    foreach my $col (@$columns) {
        if ($col eq 'htime' and not $ctes_needed) {
            $ctes_needed = 1;
        } elsif ($col eq 'shtime') {
            $ctes_needed = 2;
        }

        my @args;
        @args = @{$order_by_sprintf_args{$col}} if
            exists $order_by_sprintf_args{$col};

        push @clauses, sprintf($HOLD_SORT_ORDER_BY{$col}, @args);

        last if $col eq 'rtime';    # rtime is effectively unique, no need for
                                    # more order-by clauses after that.
    }

    my ($ctes, $joins) = ("", "");
    if ($ctes_needed >= 1) {
        # Each CTE serves the next. The first is one version or another
        # of last_event_on_copy, which is described in holds-go-home.txt
        # TechRef, but it essentially returns place and time of the most
        # recent transit or circ to do with a copy, and failing that it
        # returns a synthetic event that means "here" and "now".

        if ($ctes_needed == 2) {
            $ctes .= sprintf(q!
, last_event_on_copy AS (    -- combined circ and transit version
    SELECT *
    FROM (
        (   SELECT
                TRUE AS concrete,
                dest AS place,
                COALESCE(dest_recv_time, source_send_time) AS moment
            FROM action.transit_copy
            WHERE target_copy = %d
            AND cancel_time IS NULL
            ORDER BY moment DESC LIMIT 1
        ) UNION (
            SELECT
                TRUE AS concrete,
                COALESCE(checkin_lib, circ_lib) AS place,
                COALESCE(checkin_time, xact_start) AS moment
            FROM action.circulation
            WHERE target_copy = %d
            ORDER BY moment DESC LIMIT 1
        ) UNION
            SELECT
                FALSE AS concrete,
                %d AS place,
                NOW() AS moment
    ) x ORDER BY concrete DESC, moment DESC LIMIT 1
) !, $cp->id, $cp->id, $cp->call_number->owning_lib);
        } else {
            $ctes .= sprintf(q!
, last_event_on_copy AS (   -- circ only version
    SELECT * FROM (
        ( SELECT
                TRUE AS concrete,
                COALESCE(checkin_lib, circ_lib) AS place,
                COALESCE(checkin_time, xact_start) AS moment
            FROM action.circulation
            WHERE target_copy = %d
            ORDER BY moment DESC LIMIT 1
        ) UNION SELECT
                FALSE AS concrete,
                %d AS place,
                NOW() AS moment
    ) x ORDER BY concrete DESC, moment DESC LIMIT 1
) !, $cp->id, $cp->call_number->owning_lib);
        }

        $joins .= q!
            JOIN last_event_on_copy ON (true)
        !;

        # For our next auxiliary query, the question we seek to answer is,
        # "has our copy been circulating away from home too long?"
        #
        # Have there been no checkouts at the copy's circ_lib since the
        # beginning of our go-home interval?

        # [We use sprintf because the outer function that's going to send one
        # big query through DBI is blind to our process of dynamically building
        # these CTEs, and it wouldn't know what bind parameters to pass unless
        # we did a lot more work here. This is injection-safe because we only
        # use the %d formatter.]
        $ctes .= sprintf(q!
, copy_has_not_been_home AS (
    SELECT (
        -- part 1
        SELECT MIN(circ.id) FROM action.circulation circ
        JOIN go_home_interval ON (true)
        WHERE
            circ.target_copy = %d AND
            circ.circ_lib = %d AND
            circ.xact_start >= NOW() - go_home_interval.value
    ) IS NULL AS result
) !, $cp->id, $cp->circ_lib);

        $joins .= q!
            JOIN copy_has_not_been_home ON (true)
        !;
    }

    if ($ctes_needed == 2) {
        # By this query, we mean to determine that the copy hasn't landed at
        # home by means of transit during the go-home interval (in addition
        # to not having circulated from home in the same time frame).
        #
        # There have been no homebound transits that arrived for this copy
        # since the beginning of the go-home interval.

        $ctes .= sprintf(q!
, copy_has_not_been_home_even_to_idle AS (
    SELECT result AND NOT (
        SELECT COUNT(*)::INT::BOOL
        FROM action.transit_copy atc
        WHERE
            atc.target_copy = %d AND
            (atc.dest = %d OR atc.source = %d) AND
            atc.dest_recv_time >= NOW() - (SELECT value FROM go_home_interval) AND
            atc.cancel_time IS NULL
    ) AS result FROM copy_has_not_been_home
) !, $cp->id, $cp->circ_lib, $cp->circ_lib);
        $joins .= " JOIN copy_has_not_been_home_even_to_idle ON (true) ";
    }

    return (
        join(", ", @clauses),
        $ctes,
        $joins
    );
}

sub nearest_hold {
    my $self = shift;
    my $client = shift;
    my $here = shift;   # just the ID
    my $cp = shift;     # now an object with call_number fleshed,
                        # formerly just copy ID
    my $limit = int(shift()) || 10;
    my $age = shift() || '0 seconds';
    my $fifo = shift();

    $log->info("deprecated 'fifo' param true, but ignored") if isTrue($fifo);

    # ScriptBuilder fleshes the circ_lib, which confuses things; ensure we
    # are working with a circ lib ID and not an object
    my $cp_circ_lib;
    if (ref $cp->circ_lib) {
        $cp_circ_lib = $cp->circ_lib->id;
    } else {
        $cp_circ_lib = $cp->circ_lib;
    }

    my $cp_owning_lib;
    if (ref $cp->call_number->owning_lib) {
        $cp_owning_lib = $cp->call_number->owning_lib->id;
    } else {
        $cp_owning_lib = $cp->call_number->owning_lib;
    }

    my ($holdsort, $addl_cte, $addl_join) =
        build_hold_sort_clause(get_hold_sort_order($cp_owning_lib), $cp, $here);

    local $OpenILS::Application::Storage::WRITE = 1;

    my $ids = action::hold_request->db_Main->selectcol_arrayref(<<"    SQL", {}, $cp_circ_lib, $here, $cp->id, $age);
        WITH go_home_interval AS (
            SELECT OILS_JSON_TO_TEXT(
                (SELECT value FROM actor.org_unit_ancestor_setting(
                    'circ.hold_go_home_interval', ?
                )
            ))::INTERVAL AS value
        )
        $addl_cte
        SELECT  h.id
          FROM  action.hold_request h
            JOIN actor.org_unit_proximity p ON (p.from_org = ? AND p.to_org = h.pickup_lib)
            JOIN action.hold_copy_map hm ON (hm.hold = h.id)
            JOIN actor.usr au ON (au.id = h.usr)
            JOIN permission.grp_tree pgt ON (au.profile = pgt.id)
            JOIN asset.copy acp ON (hm.target_copy = acp.id)
            LEFT JOIN config.rule_age_hold_protect cahp ON (acp.age_protect = cahp.id)
            LEFT JOIN actor.usr_standing_penalty ausp
                ON ( au.id = ausp.usr AND ( ausp.stop_date IS NULL OR ausp.stop_date > NOW() ) )
            LEFT JOIN config.standing_penalty csp
                ON ( csp.id = ausp.standing_penalty AND csp.block_list LIKE '%CAPTURE%' )
            LEFT JOIN LATERAL (
                SELECT OILS_JSON_TO_TEXT(value) AS age
                  FROM actor.org_unit_ancestor_setting('circ.pickup_hold_stalling.soft', h.pickup_lib)
            ) AS pickup_stall ON TRUE
            $addl_join
          WHERE hm.target_copy = ?

                /* not protected, or protection is expired or we're in range */
            AND (cahp.id IS NULL OR (AGE(NOW(),acp.active_date) >= cahp.age OR cahp.prox >= hm.proximity))

                /* the complicated hold stalling logic */
            AND CASE WHEN pickup_stall.age IS NOT NULL AND h.request_time + pickup_stall.age::INTERVAL > NOW()
                        THEN -- pickup lib oriented stalling is configured for this hold's pickup lib, and it's "too young"
                            CASE WHEN p.prox = 0
                                THEN TRUE -- Cheap test: allow it when scanning at pickup lib
                                ELSE action.hold_copy_calculated_proximity( -- have to call this because we don't know if pprox will be included
                                        h.id,
                                        acp.id,
                                        p.from_org -- equals scan lib, see first JOIN above
                                     ) <= 0 -- else more expensive test for scan-lib calc prox
                            END
                    ELSE ( h.request_time + CAST(? AS INTERVAL) < NOW()
                           OR hm.proximity <= 0
                           OR p.prox = 0
                         ) -- not "too young" OR copy-owner/pickup prox OR scan-lib/pickup prox
                END

                /* simple, quick tests */
            AND h.capture_time IS NULL
            AND h.cancel_time IS NULL
            AND (h.expire_time IS NULL OR h.expire_time > NOW())
            AND h.frozen IS FALSE
            AND csp.id IS NULL
        ORDER BY CASE WHEN h.hold_type IN ('R','F') THEN 0 ELSE 1 END, $holdsort
        LIMIT $limit
    SQL
    
    $client->respond( $_ ) for ( @$ids );
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.action.hold_request.nearest_hold',
    api_level   => 1,
    stream      => 1,
    method      => 'nearest_hold',
);

sub targetable_holds {
    my $self = shift;
    my $client = shift;
    my $check_expire = shift;

    $check_expire ||= '12h';

    local $OpenILS::Application::Storage::WRITE = 1;

    # json_query can *almost* represent this query, but can't
    # handle the CASE statement or the interval arithmetic
    my $query = <<"    SQL";
        SELECT ahr.id, mmsm.metarecord
        FROM action.hold_request ahr
        JOIN reporter.hold_request_record USING (id)
        JOIN metabib.metarecord_source_map mmsm ON (bib_record = source)
        WHERE capture_time IS NULL
        AND (prev_check_time IS NULL or prev_check_time < (NOW() - ?::interval))
        AND fulfillment_time IS NULL
        AND cancel_time IS NULL
        AND NOT frozen
        ORDER BY CASE WHEN ahr.hold_type = 'F' THEN 0 ELSE 1 END, selection_depth DESC, request_time;
    SQL
    my $sth = action::hold_request->db_Main->prepare_cached($query);
    $sth->execute($check_expire);
    $client->respond( $_ ) for @{ $sth->fetchall_arrayref };

    return undef;
}

__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.action.hold_request.targetable_holds.id_list',
    api_level   => 1,
    stream      => 1,
    method      => 'targetable_holds',
    signature   => q/
        Returns ordered list of hold request and metarecord IDs
        for all hold requests that are available for initial targeting
        or retargeting.
        @param check interval
        @return list of pairs of hold request and metarecord IDs
/,
);

sub next_resp_group_id {
    my $self = shift;
    my $client = shift;

    # XXX This is not replication safe!!!

    my ($id) = action::survey->db_Main->selectrow_array(<<"    SQL");
        SELECT NEXTVAL('action.survey_response_group_id_seq'::TEXT)
    SQL
    return $id;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.survey_response.next_group_id',
    api_level       => 1,
    method          => 'next_resp_group_id',
);

sub patron_circ_summary {
    my $self = shift;
    my $client = shift;
    my $id = ''.shift();

    return undef unless ($id);
    my $c_table = action::circulation->table;
    my $b_table = money::billing->table;

    $log->debug("Retrieving patron summary for id $id", DEBUG);

    my $select = <<"    SQL";
        SELECT  COUNT(DISTINCT c.id), SUM( COALESCE(b.amount,0) )
          FROM  $c_table c
            LEFT OUTER JOIN $b_table b ON (c.id = b.xact AND b.voided = FALSE)
          WHERE c.usr = ?
            AND c.xact_finish IS NULL
            AND (
                c.stop_fines NOT IN ('CLAIMSRETURNED','LOST')
                OR c.stop_fines IS NULL
            )
    SQL

    return action::survey->db_Main->selectrow_arrayref($select, {}, $id);
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.circulation.patron_summary',
    api_level       => 1,
    method          => 'patron_circ_summary',
);

#XXX Fix stored proc calls
sub find_local_surveys {
    my $self = shift;
    my $client = shift;
    my $ou = ''.shift();

    return undef unless ($ou);
    my $s_table = action::survey->table;

    my $select = <<"    SQL";
        SELECT  s.*
          FROM  $s_table s
            JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
          WHERE CURRENT_TIMESTAMP BETWEEN s.start_date AND s.end_date
    SQL

    my $sth = action::survey->db_Main->prepare_cached($select);
    $sth->execute($ou);

    $client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.survey.all',
    api_level       => 1,
    stream          => 1,
    method          => 'find_local_surveys',
);

#XXX Fix stored proc calls
sub find_opac_surveys {
    my $self = shift;
    my $client = shift;
    my $ou = ''.shift();

    return undef unless ($ou);
    my $s_table = action::survey->table;

    my $select = <<"    SQL";
        SELECT  s.*
          FROM  $s_table s
            JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
          WHERE CURRENT_TIMESTAMP BETWEEN s.start_date AND s.end_date
            AND s.opac IS TRUE;
    SQL

    my $sth = action::survey->db_Main->prepare_cached($select);
    $sth->execute($ou);

    $client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.survey.opac',
    api_level       => 1,
    stream          => 1,
    method          => 'find_opac_surveys',
);

sub hold_pull_list {
    my $self = shift;
    my $client = shift;
    my $ou = shift;
    my $limit = shift || 10;
    my $offset = shift || 0;

    return undef unless ($ou);
    my $h_table = action::hold_request->table;
    my $a_table = asset::copy->table;
    my $ord_table = asset::copy_location_order->table;

    my $idlist = 1 if ($self->api_name =~/id_list/o);
    my $count = 1 if ($self->api_name =~/count$/o);

    my $status_filter = '';
    $status_filter = 'AND a.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available)'
        if ($self->api_name =~/status_filtered/);

    my $select = <<"    SQL";
        SELECT  h.*
          FROM  $h_table h
            JOIN $a_table a ON (h.current_copy = a.id)
            LEFT JOIN $ord_table ord ON (a.location = ord.location AND a.circ_lib = ord.org)
          WHERE a.circ_lib = ?
            AND a.deleted IS FALSE
            AND h.capture_time IS NULL
            AND h.cancel_time IS NULL
            AND (h.expire_time IS NULL OR h.expire_time > NOW())
            AND NOT EXISTS (
                SELECT  1
                  FROM  actor.usr_standing_penalty ausp
                        JOIN config.standing_penalty csp ON (
                            csp.id = ausp.standing_penalty
                            AND csp.block_list LIKE '%CAPTURE%'
                        )
                  WHERE h.usr = ausp.usr
                        AND ( ausp.stop_date IS NULL OR ausp.stop_date > NOW() )
            )
            $status_filter
          ORDER BY CASE WHEN ord.position IS NOT NULL THEN ord.position ELSE 999 END, h.request_time
          LIMIT $limit
          OFFSET $offset
    SQL

    if ($count) {
        $select = <<"        SQL";
            SELECT    count(DISTINCT h.id)
              FROM    $h_table h
                  JOIN $a_table a ON (h.current_copy = a.id)
              WHERE    a.circ_lib = ?
                  AND a.deleted is FALSE
                  AND h.capture_time IS NULL
                  AND h.cancel_time IS NULL
                  AND (h.expire_time IS NULL OR h.expire_time > NOW())
                  AND NOT EXISTS (
                    SELECT  1
                      FROM  actor.usr_standing_penalty ausp
                            JOIN config.standing_penalty csp ON (
                                csp.id = ausp.standing_penalty
                                AND csp.block_list LIKE '%CAPTURE%'
                            )
                      WHERE h.usr = ausp.usr
                            AND ( ausp.stop_date IS NULL OR ausp.stop_date > NOW() )
                )
                $status_filter
        SQL
    }

    my $sth = action::survey->db_Main->prepare_cached($select);
    $sth->execute($ou);

    if ($count) {
        $client->respond( $sth->fetchall_arrayref()->[0][0] );
    } elsif ($idlist) {
        $client->respond( $_->{id} ) for ( $sth->fetchall_hash );
    } else {
        $client->respond( $_->to_fieldmapper ) for ( map { action::hold_request->construct($_) } $sth->fetchall_hash );
    }

    return undef;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.direct.action.hold_request.pull_list.current_copy_circ_lib.count',
    api_level       => 1,
    stream          => 1,
    signature   => [
        "Returns a count of holds for a specific library's pull list.",
        [ [org_unit => "The library's org id", "number"] ],
        ['A count of holds for the stated library to pull ', 'number']
    ],
    method          => 'hold_pull_list',
);
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.direct.action.hold_request.pull_list.current_copy_circ_lib.status_filtered.count',
    api_level       => 1,
    stream          => 1,
    signature   => [
        "Returns a status filtered count of holds for a specific library's pull list.",
        [ [org_unit => "The library's org id", "number"] ],
        ['A status filtered count of holds for the stated library to pull ', 'number']
    ],
    method          => 'hold_pull_list',
);
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.direct.action.hold_request.pull_list.id_list.current_copy_circ_lib',
    api_level       => 1,
    stream          => 1,
    signature   => [
        "Returns the hold ids for a specific library's pull list.",
        [ [org_unit => "The library's org id", "number"],
          [limit => 'An optional page size, defaults to 10', 'number'],
          [offset => 'Offset for paging, defaults to 0, 0 based', 'number'],
        ],
        ['A list of holds for the stated library to pull for', 'array']
    ],
    method          => 'hold_pull_list',
);
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.direct.action.hold_request.pull_list.search.current_copy_circ_lib',
    api_level       => 1,
    stream          => 1,
    signature   => [
        "Returns the holds for a specific library's pull list.",
        [ [org_unit => "The library's org id", "number"],
          [limit => 'An optional page size, defaults to 10', 'number'],
          [offset => 'Offset for paging, defaults to 0, 0 based', 'number'],
        ],
        ['A list of holds for the stated library to pull for', 'array']
    ],
    method          => 'hold_pull_list',
);
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.direct.action.hold_request.pull_list.id_list.current_copy_circ_lib.status_filtered',
    api_level       => 1,
    stream          => 1,
    signature   => [
        "Returns the hold ids for a specific library's pull list that are definitely in that library, based on status.",
        [ [org_unit => "The library's org id", "number"],
          [limit => 'An optional page size, defaults to 10', 'number'],
          [offset => 'Offset for paging, defaults to 0, 0 based', 'number'],
        ],
        ['A list of holds for the stated library to pull for', 'array']
    ],
    method          => 'hold_pull_list',
);
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.direct.action.hold_request.pull_list.search.current_copy_circ_lib.status_filtered',
    api_level       => 1,
    stream          => 1,
    signature   => [
        "Returns the holds for a specific library's pull list that are definitely in that library, based on status.",
        [ [org_unit => "The library's org id", "number"],
          [limit => 'An optional page size, defaults to 10', 'number'],
          [offset => 'Offset for paging, defaults to 0, 0 based', 'number'],
        ],
        ['A list of holds for the stated library to pull for', 'array']
    ],
    method          => 'hold_pull_list',
);

sub find_optional_surveys {
    my $self = shift;
    my $client = shift;
    my $ou = ''.shift();

    return undef unless ($ou);
    my $s_table = action::survey->table;

    my $select = <<"    SQL";
        SELECT  s.*
          FROM  $s_table s
            JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
          WHERE CURRENT_TIMESTAMP BETWEEN s.start_date AND s.end_date
            AND s.required IS FALSE;
    SQL

    my $sth = action::survey->db_Main->prepare_cached($select);
    $sth->execute($ou);

    $client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.survey.optional',
    api_level       => 1,
    stream          => 1,
    method          => 'find_optional_surveys',
);

sub find_required_surveys {
    my $self = shift;
    my $client = shift;
    my $ou = ''.shift();

    return undef unless ($ou);
    my $s_table = action::survey->table;

    my $select = <<"    SQL";
        SELECT  s.*
          FROM  $s_table s
            JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
          WHERE CURRENT_TIMESTAMP BETWEEN s.start_date AND s.end_date
            AND s.required IS TRUE;
    SQL

    my $sth = action::survey->db_Main->prepare_cached($select);
    $sth->execute($ou);

    $client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.survey.required',
    api_level       => 1,
    stream          => 1,
    method          => 'find_required_surveys',
);

sub find_usr_summary_surveys {
    my $self = shift;
    my $client = shift;
    my $ou = ''.shift();

    return undef unless ($ou);
    my $s_table = action::survey->table;

    my $select = <<"    SQL";
        SELECT  s.*
          FROM  $s_table s
            JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
          WHERE CURRENT_TIMESTAMP BETWEEN s.start_date AND s.end_date
            AND s.usr_summary IS TRUE;
    SQL

    my $sth = action::survey->db_Main->prepare_cached($select);
    $sth->execute($ou);

    $client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

    return undef;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.survey.usr_summary',
    api_level       => 1,
    stream          => 1,
    method          => 'find_usr_summary_surveys',
);

sub generate_fines {
    my $self = shift;
    my $client = shift;
    my $circ_id = shift;

    my $circs;
    my $editor = new_editor;
    if ($circ_id) {
        $circs = $editor->search_action_circulation( { id => $circ_id, stop_fines => undef } );
        unless (@$circs) {
            $circs = $editor->search_booking_reservation( { id => $circ_id, return_time => undef, cancel_time => undef } );
        }
    } else {
        $circs = [overdue_circs(undef, 1, 1, 1)];
    }

    return OpenILS::Application::Circ::CircCommon->generate_fines({circs => $circs, conn => $client})
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.circulation.overdue.generate_fines',
    api_level       => 1,
    stream      => 1,
    method          => 'generate_fines',
);


sub MR_records_matching_format {
    my $self = shift;
    my $client = shift;
    my $MR = shift;
    my $filter = shift;
    my $org = shift;
    # include all visible copies, regardless of holdability
    my $opac_visible = shift;

    # find filters for MR holds
    my $mr_filter;
    if (defined($filter)) {
        ($mr_filter) = @{action::hold_request->db_Main->selectcol_arrayref(
            'SELECT metabib.compile_composite_attr(?)',
            {},
            $filter
        )};
    }

    my $records = [metabib::metarecord->retrieve($MR)->source_records];

    my $vis_q = 'asset.record_has_holdable_copy(?,?)';
    if ($opac_visible) {
        $vis_q = <<'        SQL';
            EXISTS(
                SELECT  1
                  FROM  asset.patron_default_visibility_mask() mask,
                        asset.copy_vis_attr_cache v
                        JOIN asset.copy c ON (
                            c.id = v.target_copy
                            AND v.record = ?
                            AND c.circ_lib IN (
                                SELECT id FROM actor.org_unit_descendants(?)
                            )
                        )
                  WHERE v.vis_attr_vector @@ mask.c_attrs::query_int
            )
        SQL
    }

    my $q = "SELECT source FROM metabib.record_attr_vector_list WHERE source = ? AND vlist @@ ? AND $vis_q";
    my @args = ( $mr_filter, $org );
    if (!$mr_filter) {
        $q = "SELECT true WHERE $vis_q";
        @args = ( $org );
    }

    for my $r ( map { isTrue($_->deleted) ?  () : ($_->id) } @$records ) {
        # the map{} below is tricky. it puts the record ID in front of each param. see $q above
        $client->respond($r)
            if @{action::hold_request->db_Main->selectcol_arrayref( $q, {}, map { ( $r => $_ ) } @args )};
    }

    return; # discard final l-val
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.metarecord.filtered_records',
    api_level       => 1,
    stream          => 1,
    argc            => 2,
    method          => 'MR_records_matching_format',
);


sub new_hold_copy_targeter {
    my $self = shift;
    my $client = shift;
    my $check_expire = shift;
    my $one_hold = shift;
    my $find_copy = shift;

    local $OpenILS::Application::Storage::WRITE = 1;

    $self->{target_weight} = {};
    $self->{max_loops} = {};

    my $holds;

    try {
        if ($one_hold) {
            $self->method_lookup('open-ils.storage.transaction.begin')->run();
            $holds = [ action::hold_request->search_where( { id => $one_hold, fulfillment_time => undef, cancel_time => undef, frozen => 'f' } ) ];
        } elsif ( $check_expire ) {

            # what's the retarget time threashold?
            my $time = time;
            $check_expire ||= '12h';
            $check_expire = interval_to_seconds( $check_expire );

            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time() - $check_expire);
            $year += 1900;
            $mon += 1;
            my $expire_threshold = sprintf(
                '%s-%0.2d-%0.2dT%0.2d:%0.2d:%0.2d-00',
                $year, $mon, $mday, $hour, $min, $sec
            );

            # find all the holds holds needing retargeting
            $holds = [ action::hold_request->search_where(
                            { capture_time => undef,
                              fulfillment_time => undef,
                              cancel_time => undef,
                              frozen => 'f',
                              prev_check_time => { '<=' => $expire_threshold },
                            },
                            { order_by => 'selection_depth DESC, request_time,prev_check_time' } ) ];

            # find all the holds holds needing first time targeting
            push @$holds, action::hold_request->search(
                            capture_time => undef,
                            fulfillment_time => undef,
                            prev_check_time => undef,
                            frozen => 'f',
                            cancel_time => undef,
                            { order_by => 'selection_depth DESC, request_time' } );
        } else {

            # find all the holds holds needing first time targeting ONLY
            $holds = [ action::hold_request->search(
                            capture_time => undef,
                            fulfillment_time => undef,
                            prev_check_time => undef,
                            cancel_time => undef,
                            frozen => 'f',
                            { order_by => 'selection_depth DESC, request_time' } ) ];
        }
    } catch Error with {
        my $e = shift;
        die "Could not retrieve uncaptured hold requests:\n\n$e\n";
    };

    my @closed = actor::org_unit::closed_date->search_where(
        { close_start => { '<=', 'now' },
          close_end => { '>=', 'now' } }
    );

    if ($check_expire) {

        # $check_expire, if it exists, was already converted to seconds
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time() + $check_expire);
        $year += 1900;
        $mon += 1;

        my $next_check_time = sprintf(
            '%s-%0.2d-%0.2dT%0.2d:%0.2d:%0.2d-00',
            $year, $mon, $mday, $hour, $min, $sec
        );


        my @closed_at_next = actor::org_unit::closed_date->search_where(
            { close_start => { '<=', $next_check_time },
              close_end => { '>=', $next_check_time } }
        );

        my @new_closed;
        for my $c_at_n (@closed_at_next) {
            if (grep { ''.$_->org_unit eq ''.$c_at_n->org_unit } @closed) {
                push @new_closed, $c_at_n;
            }
        }
        @closed = @new_closed;
    }

    my @successes;
    my $actor = OpenSRF::AppSession->create('open-ils.actor');
    my $editor = new_editor;

    my $target_when_closed = {};
    my $target_when_closed_if_at_pickup_lib = {};

    for my $hold (@$holds) {
        try {
            #start a transaction if needed
            if ($self->method_lookup('open-ils.storage.transaction.current')->run) {
                $log->debug("Cleaning up after previous transaction\n");
                $self->method_lookup('open-ils.storage.transaction.rollback')->run;
            }
            $self->method_lookup('open-ils.storage.transaction.begin')->run();
            $log->info("Processing hold ".$hold->id."...\n");

            #first, re-fetch the hold, to make sure it's not captured already
            $hold->remove_from_object_index();
            $hold = action::hold_request->retrieve( $hold->id );

            die "OK\n" if (!$hold or $hold->capture_time or $hold->cancel_time);

            # remove old auto-targeting maps
            my @oldmaps = action::hold_copy_map->search( hold => $hold->id );
            $_->delete for (@oldmaps);

            if ($hold->expire_time) {
                my $ex_time = $parser->parse_datetime( clean_ISO8601( $hold->expire_time ) );
                if ( DateTime->compare($ex_time, DateTime->now) < 0 ) {

                    # cancel cause = un-targeted expiration
                    $hold->update( { cancel_time => 'now', cancel_cause => 1 } ); 

                    # refresh fields from the DB while still in the xact
                    my $fm_hold = $hold->to_fieldmapper; 

                    $self->method_lookup('open-ils.storage.transaction.commit')->run;

                    # tell A/T the hold was cancelled
                    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
                    $ses->request('open-ils.trigger.event.autocreate', 
                        'hold_request.cancel.expire_no_target', $fm_hold, $fm_hold->pickup_lib);

                    die "OK\n";
                }
            }

            my $all_copies = [];

            # find all the potential copies
            if ($hold->hold_type eq 'M') {
                for my $r_id (
                    $self->method_lookup(
                        'open-ils.storage.metarecord.filtered_records'
                    )->run( $hold->target, $hold->holdable_formats )
                ) {
                    my ($rtree) = $self
                        ->method_lookup( 'open-ils.storage.biblio.record_entry.ranged_tree')
                        ->run( $r_id, $hold->selection_ou, $hold->selection_depth );

                    for my $cn ( @{ $rtree->call_numbers } ) {
                        push @$all_copies,
                            asset::copy->search_where(
                                { id => [map {$_->id} @{ $cn->copies }],
                                  deleted => 'f' }
                            ) if ($cn && @{ $cn->copies });
                    }
                }
            } elsif ($hold->hold_type eq 'T') {
                my ($rtree) = $self
                    ->method_lookup( 'open-ils.storage.biblio.record_entry.ranged_tree')
                    ->run( $hold->target, $hold->selection_ou, $hold->selection_depth );

                unless ($rtree) {
                    push @successes, { hold => $hold->id, eligible_copies => 0, error => 'NO_RECORD' };
                    die "OK\n";
                }

                for my $cn ( @{ $rtree->call_numbers } ) {
                    push @$all_copies,
                        asset::copy->search_where(
                            { id => [map {$_->id} @{ $cn->copies }],
                              deleted => 'f' }
                        ) if ($cn && @{ $cn->copies });
                }
            } elsif ($hold->hold_type eq 'V') {
                my ($vtree) = $self
                    ->method_lookup( 'open-ils.storage.asset.call_number.ranged_tree')
                    ->run( $hold->target, $hold->selection_ou, $hold->selection_depth );

                push @$all_copies,
                    asset::copy->search_where(
                        { id => [map {$_->id} @{ $vtree->copies }],
                          deleted => 'f' }
                    ) if ($vtree && @{ $vtree->copies });

            } elsif ($hold->hold_type eq 'P') {
                my @part_maps = asset::copy_part_map->search_where( { part => $hold->target } );
                $all_copies = [
                    asset::copy->search_where(
                        { id => [map {$_->target_copy} @part_maps],
                          deleted => 'f' }
                    )
                ] if (@part_maps);
                    
            } elsif ($hold->hold_type eq 'I') {
                my ($itree) = $self
                    ->method_lookup( 'open-ils.storage.serial.issuance.ranged_tree')
                    ->run( $hold->target, $hold->selection_ou, $hold->selection_depth );

                push @$all_copies,
                    asset::copy->search_where(
                        { id => [map {$_->unit->id} @{ $itree->items }],
                          deleted => 'f' }
                    ) if ($itree && @{ $itree->items });
                    
            } elsif  ($hold->hold_type eq 'C' || $hold->hold_type eq 'R' || $hold->hold_type eq 'F') {
                my $_cp = asset::copy->retrieve($hold->target);
                push @$all_copies, $_cp if $_cp;
            }

            # Force and recall holds bypass pretty much everything
            if ($hold->hold_type ne 'R' && $hold->hold_type ne 'F') {
                # trim unholdables
                @$all_copies = grep {   isTrue($_->status->holdable) && 
                            isTrue($_->location->holdable) && 
                            isTrue($_->holdable) &&
                            !isTrue($_->deleted) &&
                            (isTrue($hold->mint_condition) ? isTrue($_->mint_condition) : 1) &&
                            ( ( $hold->hold_type ne 'C' && $hold->hold_type ne 'I' # Copy-level holds don't care about parts
                                && $hold->hold_type ne 'P' ) ? $_->part_maps->count == 0 : 1)
                        } @$all_copies;
            }

            # let 'em know we're still working
            $client->status( new OpenSRF::DomainObject::oilsContinueStatus );
            
            # if we have no copies ...
            if (!ref $all_copies || !@$all_copies) {
                $log->info("\tNo copies available for targeting at all!\n");
                push @successes, { hold => $hold->id, eligible_copies => 0, error => 'NO_COPIES' };

                $hold->update( { prev_check_time => 'today', current_copy => undef } );
                $self->method_lookup('open-ils.storage.transaction.commit')->run;
                die "OK\n";
            }

            my $copy_count = @$all_copies;
            my $found_copy = undef;
            $found_copy = 1 if($find_copy and grep $_ == $find_copy, @$all_copies);

            # map the potentials, so that we can pick up checkins
            my $hold_copy_map = {};
            $hold_copy_map->{$_->hold}->{$_->target_copy} = $_->proximity
                for (
                    map {
                        action::hold_copy_map->create( { hold => $hold->id, target_copy => $_->id } )
                    } @$all_copies
                );

            my $pu_lib = ''.$hold->pickup_lib;
            my $prox_list = create_prox_list( $self, $pu_lib, $all_copies, $hold, $hold_copy_map );
            $log->debug( "\tMapping ".scalar(@$all_copies)." potential copies for hold ".$hold->id);

            #$client->status( new OpenSRF::DomainObject::oilsContinueStatus );

            my @good_copies;
            for my $c (@$all_copies) {
                # current target
                next if ($hold->current_copy and $c->id eq $hold->current_copy);

                # skip on circ lib is closed IFF we care
                my $ignore_closing;

                if (''.$hold->pickup_lib eq ''.$c->circ_lib) {
                    $ignore_closing = ou_ancestor_setting_value_or_cache(
                        $editor,
                        ''.$c->circ_lib,
                        'circ.holds.target_when_closed_if_at_pickup_lib',
                        $target_when_closed_if_at_pickup_lib
                    ) || 0;
                }
                if (not $ignore_closing) {  # one more chance to find a reason
                                            # to ignore OU closedness.
                    $ignore_closing = ou_ancestor_setting_value_or_cache(
                        $editor,
                        ''.$c->circ_lib,
                        'circ.holds.target_when_closed',
                        $target_when_closed
                    ) || 0;
                }

#               $logger->info(
#                   "For hold " . $hold->id . " and copy with circ_lib " .
#                   $c->circ_lib . " we " .
#                   ($ignore_closing ? "ignore" : "respect")
#                   . " closed dates"
#               );

                next if (
                    (not $ignore_closing) and
                    (grep { ''.$_->org_unit eq ''.$c->circ_lib } @closed)
                );

                # target of another hold
                next if (action::hold_request
                        ->search_where(
                            { current_copy => $c->id,
                              fulfillment_time => undef,
                              cancel_time => undef,
                            }
                        )
                );

                # we passed all three, keep it
                push @good_copies, $c if ($c);
                #$client->status( new OpenSRF::DomainObject::oilsContinueStatus );
            }

            $log->debug("\t".scalar(@good_copies)." (non-current) copies available for targeting...");

            my $old_best = $hold->current_copy;
            my $old_best_still_valid = 0; # Assume no, but the next line says yes if it is still a potential.
            $old_best_still_valid = 1 if ( $old_best && grep { ''.$old_best->id eq ''.$_->id } @$all_copies );
            $hold->update({ current_copy => undef }) if ($old_best);
    
            if (!scalar(@good_copies)) {
                $log->info("\tNo (non-current) copies eligible to fill the hold.");
                if ( $old_best_still_valid ) {
                    # the old copy is still available
                    $log->debug("\tPushing current_copy back onto the targeting list");
                    push @good_copies, $old_best;
                } else {
                    # oops, old copy is not available
                    $log->debug("\tcurrent_copy is no longer available for targeting... NEXT HOLD, PLEASE!");
                    $hold->update( { prev_check_time => 'today' } );
                    $self->method_lookup('open-ils.storage.transaction.commit')->run;
                    push @successes, { hold => $hold->id, eligible_copies => 0, error => 'NO_TARGETS' };
                    die "OK\n";
                }
            }

            # reset prox list after trimming good copies
            $prox_list = create_prox_list(
                $self, $pu_lib,
                [ grep { $_->status == 0 || $_->status == 7 } @good_copies ],
                $hold, $hold_copy_map
            );

            $all_copies = [ grep { ''.$_->circ_lib ne $pu_lib && ( $_->status == 0 || $_->status == 7 ) } @good_copies ];

            my $min_prox = [ sort {$a<=>$b} keys %$prox_list ]->[0];
            my $best;
            if  ($hold->hold_type eq 'R' || $hold->hold_type eq 'F') { # Recall/Force holds bypass hold rules.
                $best = $good_copies[0] if(scalar @good_copies);
            } elsif (defined $min_prox) {
                $best = choose_nearest_copy($hold, { $min_prox => delete($$prox_list{$min_prox}) });
            }

            $client->status( new OpenSRF::DomainObject::oilsContinueStatus );

            if (!$best) {
                $log->debug("\tNothing at the pickup lib, looking elsewhere among ".scalar(@$all_copies)." copies");

                $self->{max_loops}{$pu_lib} = $U->ou_ancestor_setting(
                    $pu_lib, 'circ.holds.max_org_unit_target_loops', $editor
                );

                if (defined($self->{max_loops}{$pu_lib})) {
                    $self->{max_loops}{$pu_lib} = $self->{max_loops}{$pu_lib}{value};

                    my %circ_lib_map =  map { (''.$_->circ_lib => 1) } @$all_copies;
                    my $circ_lib_list = [keys %circ_lib_map];
    
                    my $cstore = OpenSRF::AppSession->create('open-ils.cstore');
    
                    # Grab the "biggest" loop for this hold so far
                    my $current_loop = $cstore->request(
                        'open-ils.cstore.json_query',
                        { distinct => 1,
                          select => { aufhmxl => ['max'] },
                          from => 'aufhmxl',
                          where => { hold => $hold->id}
                        }
                    )->gather(1);
    
                    $current_loop = $current_loop->{max} if ($current_loop);
                    $current_loop ||= 1;
    
                    my $exclude_list = $cstore->request(
                        'open-ils.cstore.json_query.atomic',
                        { distinct => 1,
                          select => { aufhol => ['circ_lib'] },
                          from => 'aufhol',
                          where => { hold => $hold->id}
                        }
                    )->gather(1);
    
                    my @keepers;
                    if ($exclude_list && @$exclude_list) {
                        $exclude_list = [map {$_->{circ_lib}} @$exclude_list];
                        # check to see if we've used up every library in the potentials list
                        for my $l ( @$circ_lib_list ) {
                            my $keep = 1;
                            for my $ex ( @$exclude_list ) {
                                if ($ex eq $l) {
                                    $keep = 0;
                                    last;
                                }
                            }
                            push(@keepers, $l) if ($keep);
                        }
                    } else {
                        @keepers = @$circ_lib_list;
                    }
    
                    $current_loop++ if (!@keepers);
    
                    if ($self->{max_loops}{$pu_lib} && $self->{max_loops}{$pu_lib} >= $current_loop) {
                        # We haven't exceeded max_loops yet
                        my @keeper_copies;
                        for my $cp ( @$all_copies ) {
                            push(@keeper_copies, $cp) if ( !@keepers || grep { $_ eq ''.$cp->circ_lib } @keepers );

                        }
                        $all_copies = [@keeper_copies];
                    } else {
                        # We have, and should remove potentials and cancel the hold
                        my @oldmaps = action::hold_copy_map->search( hold => $hold->id );
                        $_->delete for (@oldmaps);

                        # cancel cause = un-targeted expiration
                        $hold->update( { cancel_time => 'now', cancel_cause => 1 } ); 

                        # refresh fields from the DB while still in the xact
                        my $fm_hold = $hold->to_fieldmapper; 

                        $self->method_lookup('open-ils.storage.transaction.commit')->run;

                        # tell A/T the hold was cancelled
                        my $ses = OpenSRF::AppSession->create('open-ils.trigger');
                        $ses->request('open-ils.trigger.event.autocreate', 
                            'hold_request.cancel.expire_no_target', $fm_hold, $fm_hold->pickup_lib);

                        die "OK\n";
                    }

                    $prox_list = create_prox_list( $self, $pu_lib, $all_copies, $hold, $hold_copy_map );

                    $client->status( new OpenSRF::DomainObject::oilsContinueStatus );

                }

                $best = choose_nearest_copy($hold, $prox_list);
            }

            $client->status( new OpenSRF::DomainObject::oilsContinueStatus );
            if ($old_best) {
                # hold wasn't fulfilled, record the fact
            
                $log->info("\tHold was not (but should have been) fulfilled by ".$old_best->id);
                action::unfulfilled_hold_list->create(
                        { hold => ''.$hold->id,
                          current_copy => ''.$old_best->id,
                          circ_lib => ''.$old_best->circ_lib,
                        });
            }

            if ($best) {
                $hold->update( { current_copy => ''.$best->id, prev_check_time => 'now' } );
                $log->debug("\tUpdating hold [".$hold->id."] with new 'current_copy' [".$best->id."] for hold fulfillment.");
            } elsif (
                $old_best_still_valid &&
                !action::hold_request
                    ->search_where(
                        { current_copy => $old_best->id,
                          fulfillment_time => undef,
                          cancel_time => undef,
                        }       
                    ) &&
                ( OpenILS::Utils::PermitHold::permit_copy_hold(
                    { title => $old_best->call_number->record->to_fieldmapper,
                      patron => $hold->usr->to_fieldmapper,
                      copy => $old_best->to_fieldmapper,
                      requestor => $hold->requestor->to_fieldmapper,
                      request_lib => $hold->request_lib->to_fieldmapper,
                      pickup_lib => $hold->pickup_lib->id,
                      retarget => 1
                    }
                ))
            ) {     
                $hold->update( { prev_check_time => 'now', current_copy => ''.$old_best->id } );
                $log->debug( "\tRetargeting the previously targeted copy [".$old_best->id."]" );
            } else {
                $hold->update( { prev_check_time => 'now' } );
                $log->info( "\tThere were no targetable copies for the hold" );
                process_recall($actor, $log, $hold, \@good_copies);
            }

            $self->method_lookup('open-ils.storage.transaction.commit')->run;
            $log->info("\tProcessing of hold ".$hold->id." complete.");

            push @successes,
                { hold => $hold->id,
                  old_target => ($old_best ? $old_best->id : undef),
                  eligible_copies => $copy_count,
                  target => ($best ? $best->id : undef),
                  found_copy => $found_copy };

        } otherwise {
            my $e = shift;
            if ($e !~ /^OK/o) {
                $log->error("Processing of hold failed:  $e");
                $self->method_lookup('open-ils.storage.transaction.rollback')->run;
                throw $e if ($e =~ /IS NOT CONNECTED TO THE NETWORK/o);
            }
        };
    }

    return \@successes;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.action.hold_request.copy_targeter',
    api_level   => 1,
    method      => 'new_hold_copy_targeter',
);

sub process_recall {
    my ($actor, $log, $hold, $good_copies) = @_;

    # Bail early if we don't have required settings to avoid spurious requests
    my ($recall_threshold, $return_interval, $fine_rules);

    my $rv = $actor->request(
        'open-ils.actor.ou_setting.ancestor_default', ''.$hold->pickup_lib, 'circ.holds.recall_threshold'
    )->gather(1);

    if (!$rv) {
        $log->info("Recall threshold was not set; bailing out on hold ".$hold->id." processing.");
        return;
    }
    $recall_threshold = $rv->{value};

    $rv = $actor->request(
        'open-ils.actor.ou_setting.ancestor_default', ''.$hold->pickup_lib, 'circ.holds.recall_return_interval'
    )->gather(1);

    if (!$rv) {
        $log->info("Recall return interval was not set; bailing out on hold ".$hold->id." processing.");
        return;
    }
    $return_interval = $rv->{value};

    $rv = $actor->request(
        'open-ils.actor.ou_setting.ancestor_default', ''.$hold->pickup_lib, 'circ.holds.recall_fine_rules'
    )->gather(1);

    if ($rv) {
        $fine_rules = $rv->{value};
    }

    $log->info("Recall threshold: $recall_threshold; return interval: $return_interval");

    # We want checked out copies (status = 1) at the hold pickup lib
    my $all_copies = [grep { $_->status == 1 } grep {''.$_->circ_lib eq ''.$hold->pickup_lib } @$good_copies];

    my @copy_ids = map { $_->id } @$all_copies;

    $log->info("Found " . scalar(@$all_copies) . " eligible checked-out copies for recall");

    my $return_date = DateTime->now(time_zone => 'local')->add(seconds => interval_to_seconds($return_interval));

    # Iterate over the checked-out copies to find a copy with a
    # loan period longer than the recall threshold:
    my $circs = [ action::circulation->search_where(
        { target_copy => \@copy_ids, checkin_time => undef, duration => { '>' => $recall_threshold } },
        { order_by => 'due_date ASC' }
    )];

    # If we have a candidate copy, then:
    if (scalar(@$circs)) {
        my $circ = $circs->[0];
        $log->info("Recalling circ ID : " . $circ->id);

        my $old_due_date = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($circ->due_date));

        # Give the user a new due date of either a full recall threshold,
        # or the return interval, whichever is further in the future
        my $threshold_date = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($circ->xact_start))->add(seconds => interval_to_seconds($recall_threshold));
        if (DateTime->compare($threshold_date, $return_date) == 1) {
            # extend $return_date to threshold
            $return_date = $threshold_date;
        }
        # But don't go past the original due date
        # (the threshold should not be past the due date, but manual edits can cause it to be)
        if (DateTime->compare($return_date, $old_due_date) == 1) {
            # truncate $return_date to due date
            $return_date = $old_due_date;
        }

        my $update_fields = {
            due_date => $return_date->iso8601(),
            renewal_remaining => 0,
        };

        # If the OU hasn't defined new fine rules for recalls, keep them
        # as they were
        if ($fine_rules) {
            $log->info("Apply recall fine rules: $fine_rules");
            my $rules = OpenSRF::Utils::JSON->JSON2perl($fine_rules);
            $update_fields->{recurring_fine} = $rules->[0];
            $update_fields->{fine_interval} = $rules->[1];
            $update_fields->{max_fine} = $rules->[2];
        }

        # Adjust circ for current user
        $circ->update($update_fields);

        # Create trigger event for notifying current user
        my $ses = OpenSRF::AppSession->create('open-ils.trigger');
        $ses->request('open-ils.trigger.event.autocreate', 'circ.recall.target', $circ->to_fieldmapper(), $circ->circ_lib->id);
    }

    $log->info("Processing of hold ".$hold->id." for recall is now complete.");
}

sub reservation_targeter {
    my $self = shift;
    my $client = shift;
    my $one_reservation = shift;

    local $OpenILS::Application::Storage::WRITE = 1;

    my $reservations;

    try {
        if ($one_reservation) {
            $self->method_lookup('open-ils.storage.transaction.begin')->run();
            $reservations = [ booking::reservation->search_where( { id => $one_reservation, capture_time => undef, cancel_time => undef } ) ];
        } else {

            # find all the reservations needing targeting
            $reservations = [
                booking::reservation->search_where(
                    { current_resource => undef,
                      cancel_time => undef,
                      start_time => { '>' => 'now' }
                    },
                    { order_by => 'start_time' }
                )
            ];
        }
    } catch Error with {
        my $e = shift;
        die "Could not retrieve reservation requests:\n\n$e\n";
    };

    my @successes = ();
    for my $bresv (@$reservations) {
        try {
            #start a transaction if needed
            if ($self->method_lookup('open-ils.storage.transaction.current')->run) {
                $log->debug("Cleaning up after previous transaction\n");
                $self->method_lookup('open-ils.storage.transaction.rollback')->run;
            }
            $self->method_lookup('open-ils.storage.transaction.begin')->run();
            $log->info("Processing reservation ".$bresv->id."...\n");

            #first, re-fetch the hold, to make sure it's not captured already
            $bresv->remove_from_object_index();
            $bresv = booking::reservation->retrieve( $bresv->id );

            die "OK\n" if (!$bresv or $bresv->capture_time or $bresv->cancel_time);

            my $end_time = $parser->parse_datetime( clean_ISO8601( $bresv->end_time ) );
            if (DateTime->compare($end_time, DateTime->now) < 0) {

                # cancel cause = un-targeted expiration
                $bresv->update( { cancel_time => 'now' } ); 

                # refresh fields from the DB while still in the xact
                my $fm_bresv = $bresv->to_fieldmapper;

                $self->method_lookup('open-ils.storage.transaction.commit')->run;

                # tell A/T the reservation was cancelled
                my $ses = OpenSRF::AppSession->create('open-ils.trigger');
                $ses->request('open-ils.trigger.event.autocreate', 
                    'booking.reservation.cancel.expire_no_target', $fm_bresv, $fm_bresv->pickup_lib);

                die "OK\n";
            }

            my $possible_resources;

            # find all the potential resources
            if (!$bresv->target_resource) {
                my $filter = { type => $bresv->target_resource_type };
                my $attr_maps = [ booking::reservation_attr_value_map->search( reservation => $bresv->id) ];

                $filter->{attribute_values} = [ map { $_->attr_value } @$attr_maps ] if (@$attr_maps);

                $filter->{available} = [$bresv->start_time, $bresv->end_time];
                my $ses = OpenSRF::AppSession->create('open-ils.booking');
                $possible_resources = $ses->request('open-ils.booking.resources.filtered_id_list', undef, $filter)->gather(1);
            } else {
                $possible_resources = $bresv->target_resource;
            }

            my $all_resources = [ booking::resource->search( id => $possible_resources ) ];
            @$all_resources = grep { isTrue($_->type->transferable) || $_->owner.'' eq $bresv->pickup_lib.'' } @$all_resources;


            my @good_resources = ();
            my %conflicts = ();
            for my $res (@$all_resources) {
                unless (isTrue($res->type->catalog_item)) {
                    push @good_resources, $res;
                    next;
                }

                my $copy = [ asset::copy->search( deleted => 'f', barcode => $res->barcode )]->[0];

                unless ($copy) {
                    push @good_resources, $res;
                    next;
                }

                # At this point, if we're just targeting one specific
                # resource, just succeed. We don't care about its present
                # copy status.
                if ($bresv->target_resource) {
                    push @good_resources, $res;
                    next;
                }

                if ($copy->status->id == 0 || $copy->status->id == 7) {
                    push @good_resources, $res;
                    next;
                }

                if ($copy->status->id == 1) {
                    my $circs = [ action::circulation->search_where(
                        {target_copy => $copy->id, checkin_time => undef },
                        { order_by => 'id DESC' }
                    ) ];

                    if (@$circs) {
                        my $due_date = $circs->[0]->due_date;
                        $due_date = $parser->parse_datetime( clean_ISO8601( $due_date ) );
                        my $start_time = $parser->parse_datetime( clean_ISO8601( $bresv->start_time ) );
                        if (DateTime->compare($start_time, $due_date) < 0) {
                            $conflicts{$res->id} = $circs->[0]->to_fieldmapper;
                            next;
                        }

                        push @good_resources, $res;
                    }

                    next;
                }

                push @good_resources, $res if (isTrue($copy->status->holdable));
            }

            # let 'em know we're still working
            $client->status( new OpenSRF::DomainObject::oilsContinueStatus );
            
            # if we have no copies ...
            if (!@good_resources) {
                $log->info("\tNo resources available for targeting at all!\n");
                push @successes, { reservation => $bresv->id, eligible_copies => 0, error => 'NO_COPIES', conflicts => \%conflicts };


                $self->method_lookup('open-ils.storage.transaction.commit')->run;
                die "OK\n";
            }

            $log->debug("\t".scalar(@good_resources)." resources available for targeting...");

            # LFW: note that after the inclusion of hold proximity
            # adjustment, this prox_list is the only prox_list
            # array in this perl package.  Other occurences are
            # hashes.
            my $prox_list = [];
            $$prox_list[0] =
            [
                grep {
                    $_->owner == $bresv->pickup_lib
                } @good_resources
            ];

            $all_resources = [grep {$_->owner != $bresv->pickup_lib } @good_resources];
            # $all_copies is now a list of copies not at the pickup library

            my $best = shift @good_resources;
            $client->status( new OpenSRF::DomainObject::oilsContinueStatus );

            if (!$best) {
                $log->debug("\tNothing at the pickup lib, looking elsewhere among ".scalar(@$all_resources)." resources");

                $prox_list =
                    map  { $_->[1] }
                    sort { $a->[0] <=> $b->[0] }
                    map  {
                        [   actor::org_unit_proximity->search_where(
                                { from_org => $bresv->pickup_lib.'', to_org => $_->owner.'' }
                            )->[0]->prox,
                            $_
                        ]
                    } @$all_resources;

                $client->status( new OpenSRF::DomainObject::oilsContinueStatus );

                $best = shift @$prox_list
            }

            if ($best) {
                $bresv->update( { current_resource => ''.$best->id } );
                $log->debug("\tUpdating reservation [".$bresv->id."] with new 'current_resource' [".$best->id."] for reservation fulfillment.");
            }

            $self->method_lookup('open-ils.storage.transaction.commit')->run;
            $log->info("\tProcessing of bresv ".$bresv->id." complete.");

            push @successes,
                { reservation => $bresv->id,
                  current_resource => ($best ? $best->id : undef) };

        } otherwise {
            my $e = shift;
            if ($e !~ /^OK/o) {
                $log->error("Processing of bresv failed:  $e");
                $self->method_lookup('open-ils.storage.transaction.rollback')->run;
                throw $e if ($e =~ /IS NOT CONNECTED TO THE NETWORK/o);
            }
        };
    }

    return \@successes;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.booking.reservation.resource_targeter',
    api_level   => 1,
    method      => 'reservation_targeter',
);

my $locations;
my $statuses;
my %cache = (titles => {}, cns => {});

sub copy_hold_capture {
    my $self = shift;
    my $hold = shift;
    my $cps = shift;

    if (!defined($cps)) {
        try {
            $cps = [ asset::copy->search( id => $hold->target ) ];
        } catch Error with {
            my $e = shift;
            die "Could not retrieve initial volume list:\n\n$e\n";
        };
    }

    my @copies = grep { $_->holdable } @$cps;

    for (my $i = 0; $i < @$cps; $i++) {
        next unless $$cps[$i];
        
        my $cn = $cache{cns}{$copies[$i]->call_number};
        my $rec = $cache{titles}{$cn->record};
        $copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->status eq $_->id}@$statuses);
        $copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->location eq $_->id}@$locations);
        $copies[$i] = undef if (
            !$copies[$i] ||
            !$self->{user_filter}->request(
                'open-ils.circ.permit_hold',
                $hold->to_fieldmapper, do {
                    my $cp_fm = $copies[$i]->to_fieldmapper;
                    $cp_fm->circ_lib( $copies[$i]->circ_lib->to_fieldmapper );
                    $cp_fm->location( $copies[$i]->location->to_fieldmapper );
                    $cp_fm->status( $copies[$i]->status->to_fieldmapper );
                    $cp_fm;
                },
                { title => $rec->to_fieldmapper,
                  usr => actor::user->retrieve($hold->usr)->to_fieldmapper,
                  requestor => actor::user->retrieve($hold->requestor)->to_fieldmapper,
                })->gather(1)
        );
        $self->{client}->status( new OpenSRF::DomainObject::oilsContinueStatus );
    }

    @copies = grep { $_ } @copies;

    my $count = @copies;

    return unless ($count);
    
    action::hold_copy_map->search( hold => $hold->id )->delete_all;
    
    my @maps;
    $self->{client}->respond( "\tMapping ".scalar(@copies)." eligable copies for hold ".$hold->id."\n");
    for my $c (@copies) {
        push @maps, action::hold_copy_map->create( { hold => $hold->id, target_copy => $c->id } );
    }
    $self->{client}->respond( "\tA total of ".scalar(@maps)." mapping were created for hold ".$hold->id."\n");

    return \@copies;
}


sub choose_nearest_copy {
    my $hold = shift;
    my $prox_list = shift;

    for my $p ( sort {$a<=>$b} keys %$prox_list ) {
        next unless (ref $$prox_list{$p});

        my @capturable = @{ $$prox_list{$p} };
        next unless (@capturable);

        my $rand = int(rand(scalar(@capturable)));
        my %seen = ();
        while (my ($c) = splice(@capturable, $rand, 1)) {
            return $c if !exists($seen{$c->id}) && ( OpenILS::Utils::PermitHold::permit_copy_hold(
                { title => $c->call_number->record->to_fieldmapper,
                  patron => $hold->usr->to_fieldmapper,
                  copy => $c->to_fieldmapper,
                  requestor => $hold->requestor->to_fieldmapper,
                  request_lib => $hold->request_lib->to_fieldmapper,
                  pickup_lib => $hold->pickup_lib->id,
                  retarget => 1
                }
            ));
            $seen{$c->id}++;

            last unless(@capturable);
            $rand = int(rand(scalar(@capturable)));
        }
    }
}

sub create_prox_list {
    my $self = shift;
    my $lib = shift;
    my $copies = shift;
    my $hold = shift;
    my $hold_copy_map = shift || {};

    my %prox_list;
    my $editor = new_editor;
    for my $cp (@$copies) {
        my $prox = $hold_copy_map->{"$hold"}->{"$cp"}; # Allow CDBI stringification to get the pkey
        ($prox) = $self->method_lookup('open-ils.storage.asset.copy.proximity')->run( $cp, $lib, $hold ) unless (defined $prox);
        next unless (defined($prox));

        my $copy_circ_lib = ''.$cp->circ_lib;
        # Fetch the weighting value for hold targeting, defaulting to 1
        $self->{target_weight}{$copy_circ_lib} ||= $U->ou_ancestor_setting(
            $copy_circ_lib.'', 'circ.holds.org_unit_target_weight', $editor
        );
        $self->{target_weight}{$copy_circ_lib} = $self->{target_weight}{$copy_circ_lib}{value} if (ref $self->{target_weight}{$copy_circ_lib});
        $self->{target_weight}{$copy_circ_lib} ||= 1;

        $prox_list{$prox} = [] unless defined($prox_list{$prox});
        for my $w ( 1 .. $self->{target_weight}{$copy_circ_lib} ) {
            push @{$prox_list{$prox}}, $cp;
        }
    }
    return \%prox_list;
}

sub volume_hold_capture {
    my $self = shift;
    my $hold = shift;
    my $vols = shift;

    if (!defined($vols)) {
        try {
            $vols = [ asset::call_number->search( id => $hold->target ) ];
            $cache{cns}{$_->id} = $_ for (@$vols);
        } catch Error with {
            my $e = shift;
            die "Could not retrieve initial volume list:\n\n$e\n";
        };
    }

    my @v_ids = map { $_->id } @$vols;

    my $cp_list;
    try {
        $cp_list = [ asset::copy->search( call_number => \@v_ids ) ];
    
    } catch Error with {
        my $e = shift;
        warn "Could not retrieve copy list:\n\n$e\n";
    };

    $self->copy_hold_capture($hold,$cp_list) if (ref $cp_list and @$cp_list);
}

sub title_hold_capture {
    my $self = shift;
    my $hold = shift;
    my $titles = shift;

    if (!defined($titles)) {
        try {
            $titles = [ biblio::record_entry->search( id => $hold->target ) ];
            $cache{titles}{$_->id} = $_ for (@$titles);
        } catch Error with {
            my $e = shift;
            die "Could not retrieve initial title list:\n\n$e\n";
        };
    }

    my @t_ids = map { $_->id } @$titles;
    my $cn_list;
    try {
        ($cn_list) = $self->method_lookup('open-ils.storage.direct.asset.call_number.search.record.atomic')->run( \@t_ids );
    
    } catch Error with {
        my $e = shift;
        warn "Could not retrieve volume list:\n\n$e\n";
    };

    $cache{cns}{$_->id} = $_ for (@$cn_list);

    $self->volume_hold_capture($hold,$cn_list) if (ref $cn_list and @$cn_list);
}


sub wide_hold_data {
    my $self = shift;
    my $client = shift;
    my $restrictions = shift; # hashref of field restrictions {f1=>undef,f2=>[1,2,3],f3=>'foo',f4=>{not=>undef}}
    my $order_by = shift; # arrayref of hashrefs of ORDER BY clause, [{field =>{dir=>'desc',nulls=>'last'}}]
    my $limit = shift;
    my $offset = shift;

    $order_by = [$order_by] if (ref($order_by) !~ /ARRAY/);
    
    $log->info('Received '. keys(%$restrictions) .' restrictions');
    return 0 unless (ref $restrictions and keys %$restrictions);

    # force this to either 'true' or 'false'
    my $is_staff_request = delete($$restrictions{is_staff_request}) || 'false';
    $is_staff_request = 'false' if (!grep {$is_staff_request eq $_} qw/true false/);

    # option to filter for the latest captured hold for a given copy
    my $last_captured_hold = delete($$restrictions{last_captured_hold}) || 'false';
    $last_captured_hold = $last_captured_hold eq 'true' ? 1 : 0;

    # option to filter by the cancel time display age setting
    my $cancel_age = ref($$restrictions{cancel_time}) eq 'HASH'
        && $$restrictions{cancel_time}{'>='}
        && ${delete($$restrictions{cancel_time})}{'>='};

    # option to filter for hopeless holds by date range
    my $hopeless_holds = delete($$restrictions{hopeless_holds}) || 'false';

    my $initial_condition = 'TRUE';
    if ($last_captured_hold) {
        $initial_condition = <<"        SQL";
            (h.capture_time IS NULL OR (h.id = (
                SELECT  id
                  FROM  action.hold_request recheck
                  WHERE recheck.current_copy = cp.id
                        AND recheck.capture_time IS NOT NULL
                  ORDER BY capture_time DESC
                  LIMIT 1
            )))
        SQL
    }

    my @bind_values;

    if ($cancel_age) {
        my $cancel_time;
        eval {
            $cancel_time = DateTime::Format::ISO8601->parse_datetime($cancel_age);
            $cancel_time->set_time_zone('UTC');
        };
        if ($@) {
            $log->error("Restriction cancel_time is invalid: $@");
            return 0;
        }
        push(@bind_values, $cancel_time->iso8601() . 'Z');
        $initial_condition .= " AND h.cancel_time >= ?";
    }

    if (ref($hopeless_holds) =~ /HASH/ && $$hopeless_holds{start_date} && $$hopeless_holds{end_date}) {
        my $start_date = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($$hopeless_holds{start_date}));
        my $end_date = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($$hopeless_holds{end_date}));
        my $hopeless_condition = "(frozen IS FALSE AND h.hopeless_date >= '$start_date' AND h.hopeless_date <= '$end_date')";
        $initial_condition .= " AND $hopeless_condition";
    }

    my $select = <<"    SQL";
WITH
    t_field AS (SELECT field FROM config.display_field_map WHERE name = 'title'),
    a_field AS (SELECT field FROM config.display_field_map WHERE name = 'author'),
    s_field AS (SELECT field FROM config.display_field_map WHERE name = 'series_title'),
    y_field AS (SELECT field FROM config.display_field_map WHERE name = 'pubdate')
SELECT  h.id, h.request_time, h.capture_time, h.fulfillment_time, h.checkin_time,
        h.return_time, h.prev_check_time, h.expire_time, h.cancel_time, h.cancel_cause,
        h.cancel_note, h.target, h.current_copy, h.fulfillment_staff, h.fulfillment_lib,
        h.request_lib, h.requestor, h.usr, h.selection_ou, h.selection_depth, h.pickup_lib,
        h.hold_type, h.holdable_formats, h.phone_notify, h.email_notify, h.sms_notify,
        (SELECT name FROM config.sms_carrier WHERE id = h.sms_carrier) AS "sms_carrier",
        h.frozen, h.thaw_date, h.shelf_time, h.cut_in_line, h.mint_condition,
        h.shelf_expire_time, h.current_shelf_lib, h.behind_desk, h.hopeless_date,
        h.canceled_by, h.canceling_ws,

        CASE WHEN h.cancel_time IS NOT NULL THEN 6
             WHEN h.frozen AND h.capture_time IS NULL THEN 7
             WHEN h.current_shelf_lib IS NOT NULL AND h.current_shelf_lib <> h.pickup_lib THEN 8
             WHEN h.fulfillment_time IS NOT NULL THEN 9
             WHEN h.current_copy IS NULL THEN 1
             WHEN h.capture_time IS NULL THEN 2
             WHEN cp.status = 6 THEN 3
             WHEN EXTRACT(EPOCH FROM COALESCE(NULLIF(BTRIM(hold_wait_time.value,'"'),''),'0 seconds')::INTERVAL) = 0 THEN 4
             WHEN h.shelf_time + COALESCE(NULLIF(BTRIM(hold_wait_time.value,'"'),''),'0 seconds')::INTERVAL > NOW() THEN 5
             ELSE 4
        END AS hold_status,

        (h.shelf_expire_time < 'today'::timestamptz OR h.cancel_time IS NOT NULL OR (h.current_shelf_lib IS NOT NULL AND h.current_shelf_lib <> h.pickup_lib)) AS clear_me,

        (h.usr <> h.requestor) AS is_staff_hold,

        cc.id AS cc_id, cc.label AS cc_label,

        pl.id AS pl_id, pl.parent_ou AS pl_parent_ou, pl.ou_type AS pl_ou_type,
        pl.ill_address AS pl_ill_address, pl.holds_address AS pl_holds_address,
        pl.mailing_address AS pl_mailing_address, pl.billing_address AS pl_billing_address,
        pl.shortname AS pl_shortname, pl.name AS pl_name, pl.email AS pl_email,
        pl.phone AS pl_phone, pl.opac_visible AS pl_opac_visible, pl.fiscal_calendar AS pl_fiscal_calendar,

        ol.shortname AS ol_shortname,
        cl.shortname AS cl_shortname,
        rl.shortname AS rl_shortname,
        sl.shortname AS sl_shortname,
        tl.shortname AS tl_shortname,
        ul.shortname AS ul_shortname,

        tr.id AS tr_id, tr.source_send_time AS tr_source_send_time, tr.dest_recv_time AS tr_dest_recv_time,
        tr.target_copy AS tr_target_copy, tr.source AS tr_source, tr.dest AS tr_dest, tr.prev_hop AS tr_prev_hop,
        tr.copy_status AS tr_copy_status, tr.persistant_transfer AS tr_persistant_transfer,
        tr.prev_dest AS tr_prev_dest, tr.hold AS tr_hold, tr.cancel_time AS tr_cancel_time,

        notes.count AS note_count,

        u.id AS usr_id, u.card AS usr_card, u.profile AS usr_profile, u.usrname AS usr_usrname,
        u.email AS usr_email, u.standing AS usr_standing, u.ident_type AS usr_ident_type,
        u.ident_value AS usr_ident_value, u.ident_type2 AS usr_ident_type2,
        u.ident_value2 AS usr_ident_value2, u.net_access_level AS usr_net_access_level,
        u.photo_url AS usr_photo_url, u.prefix AS usr_prefix, u.first_given_name AS usr_first_given_name,
        u.second_given_name AS usr_second_given_name, u.family_name AS usr_family_name,
        u.suffix AS usr_suffix, u.alias AS usr_alias, u.day_phone AS usr_day_phone,
        u.evening_phone AS usr_evening_phone, u.other_phone AS usr_other_phone,
        u.mailing_address AS usr_mailing_address, u.billing_address AS usr_billing_address,
        u.home_ou AS usr_home_ou, u.dob AS usr_dob, u.active AS usr_active,
        u.master_account AS usr_master_account, u.super_user AS usr_super_user,
        u.barred AS usr_barred, u.deleted AS usr_deleted, u.juvenile AS usr_juvenile,
        u.usrgroup AS usr_usrgroup, u.claims_returned_count AS usr_claims_returned_count,
        u.credit_forward_balance AS usr_credit_forward_balance, u.last_xact_id AS usr_last_xact_id,
        u.create_date AS usr_create_date,
        u.expire_date AS usr_expire_date, u.claims_never_checked_out_count AS usr_claims_never_checked_out_count,
        u.last_update_time AS usr_last_update_time,

        pgt.name as pgt_name,

        CASE WHEN NULLIF(u.alias,'') IS NOT NULL THEN
            u.alias
        ELSE
            u.first_given_name
        END AS usr_alias_or_first_given_name,

        CASE WHEN NULLIF(u.alias,'') IS NOT NULL THEN
            u.alias
        ELSE
            REGEXP_REPLACE(ARRAY_TO_STRING(ARRAY[
                COALESCE(NULLIF(u.pref_family_name,''), u.family_name, ''),
                COALESCE(NULLIF(u.pref_suffix,''), u.suffix, ''),
                ', ',
                COALESCE(NULLIF(u.pref_prefix,''), u.prefix, ''),
                COALESCE(NULLIF(u.pref_first_given_name,''), u.first_given_name, ''),
                COALESCE(NULLIF(u.pref_second_given_name,''), u.second_given_name, '')
            ], ' '), E'\\s+,', ',')
        END AS usr_alias_or_display_name,

        REGEXP_REPLACE(ARRAY_TO_STRING(ARRAY[
            COALESCE(NULLIF(u.pref_family_name,''), u.family_name, ''),
            COALESCE(NULLIF(u.pref_suffix,''), u.suffix, ''),
            ', ',
            COALESCE(NULLIF(u.pref_prefix,''), u.prefix, ''),
            COALESCE(NULLIF(u.pref_first_given_name,''), u.first_given_name, ''),
            COALESCE(NULLIF(u.pref_second_given_name,''), u.second_given_name, '')
        ], ' '), E'\\s+,', ',') AS usr_display_name,

        uc.id AS ucard_id, uc.barcode AS ucard_barcode, uc.usr AS ucard_usr, uc.active AS ucard_active,

        ru.id AS rusr_id, ru.card AS rusr_card, ru.profile AS rusr_profile, ru.usrname AS rusr_usrname,
        ru.email AS rusr_email, ru.standing AS rusr_standing, ru.ident_type AS rusr_ident_type,
        ru.ident_value AS rusr_ident_value, ru.ident_type2 AS rusr_ident_type2,
        ru.ident_value2 AS rusr_ident_value2, ru.net_access_level AS rusr_net_access_level,
        ru.photo_url AS rusr_photo_url, ru.prefix AS rusr_prefix, ru.first_given_name AS rusr_first_given_name,
        ru.second_given_name AS rusr_second_given_name, ru.family_name AS rusr_family_name,
        ru.suffix AS rusr_suffix, ru.alias AS rusr_alias, ru.day_phone AS rusr_day_phone,
        ru.evening_phone AS rusr_evening_phone, ru.other_phone AS rusr_other_phone,
        ru.mailing_address AS rusr_mailing_address, ru.billing_address AS rusr_billing_address,
        ru.home_ou AS rusr_home_ou, ru.dob AS rusr_dob, ru.active AS rusr_active,
        ru.master_account AS rusr_master_account, ru.super_user AS rusr_super_user,
        ru.barred AS rusr_barred, ru.deleted AS rusr_deleted, ru.juvenile AS rusr_juvenile,
        ru.usrgroup AS rusr_usrgroup, ru.claims_returned_count AS rusr_claims_returned_count,
        ru.credit_forward_balance AS rusr_credit_forward_balance, ru.last_xact_id AS rusr_last_xact_id,
        ru.create_date AS rusr_create_date,
        ru.expire_date AS rusr_expire_date, ru.claims_never_checked_out_count AS rusr_claims_never_checked_out_count,
        ru.last_update_time AS rusr_last_update_time,

        ruc.id AS rucard_id, ruc.barcode AS rucard_barcode, ruc.usr AS rucard_usr, ruc.active AS rucard_active,
        cuc.barcode AS canceled_by_barcode, cu.usrname AS canceled_by_usrname,
        caw.name as canceling_ws_name,

        cp.id AS cp_id, cp.circ_lib AS cp_circ_lib, cp.creator AS cp_creator, cp.call_number AS cp_call_number,
        cp.editor AS cp_editor, cp.create_date AS cp_create_date, cp.edit_date AS cp_edit_date,
        cp.copy_number AS cp_copy_number, cp.status AS cp_status, cp.location AS cp_location,
        cp.loan_duration AS cp_loan_duration, cp.fine_level AS cp_fine_level, cp.age_protect AS cp_age_protect,
        cp.circulate AS cp_circulate, cp.deposit AS cp_deposit, cp.ref AS cp_ref, cp.holdable AS cp_holdable,
        cp.deposit_amount AS cp_deposit_amount, cp.price AS cp_price, cp.barcode AS cp_barcode,
        cp.circ_modifier AS cp_circ_modifier, cp.circ_as_type AS cp_circ_as_type, cp.dummy_title AS cp_dummy_title,
        cp.dummy_author AS cp_dummy_author, cp.alert_message AS cp_alert_message, cp.opac_visible AS cp_opac_visible,
        cp.deleted AS cp_deleted, cp.floating AS cp_floating, cp.dummy_isbn AS cp_dummy_isbn,
        cp.status_changed_time AS cp_status_change_time, cp.active_date AS cp_active_date,
        cp.mint_condition AS cp_mint_condition, cp.cost AS cp_cost,

        cs.id AS cs_id, cs.name AS cs_name, cs.holdable AS cs_holdable, cs.opac_visible AS cs_opac_visible,
        cs.copy_active AS cs_copy_active, cs.restrict_copy_delete AS cs_restrict_copy_delete,
        cs.is_available AS cs_is_available,

        siss.label AS issuance_label,

        cn.id AS cn_id, cn.creator AS cn_creator, cn.create_date AS cn_create_date, cn.editor AS cn_editor,
        cn.edit_date AS cn_edit_date, cn.record AS cn_record, cn.owning_lib AS cn_owning_lib, cn.label AS cn_label,
        cn.deleted AS cn_deleted, cn.prefix AS cn_prefix, cn.suffix AS cn_suffix, cn.label_class AS cn_label_class,
        cn.label_sortkey AS cn_label_sortkey,

        p.id AS p_id, p.record AS p_record, p.label AS p_label, p.label_sortkey AS p_label_sortkey, p.deleted AS p_deleted,

        acnp.label AS ancp_label, acns.label AS ancs_label,
        TRIM(acnp.label || ' ' || cn.label || ' ' || acns.label) AS cn_full_label,

        r.bib_record AS record_id,

        t.value AS title,
        a.value AS author,
        s.value AS series_title,
        y.value AS pubdate,

        acpl.id AS acpl_id, acpl.name AS acpl_name, acpl.owning_lib AS acpl_owning_lib, acpl.holdable AS acpl_holdable,
        acpl.hold_verify AS acpl_hold_verify, acpl.opac_visible AS acpl_opac_visible, acpl.circulate AS acpl_circulate,
        acpl.label_prefix AS acpl_label_prefix, acpl.label_suffix AS acpl_label_suffix,
        acpl.checkin_alert AS acpl_checkin_alert, acpl.deleted AS acpl_deleted, acpl.url AS acpl_url,

        COALESCE(acplo.position, acpl_ordered.fallback_position) AS copy_location_order_position,

        pos.global_queue_position, -- position among same-bib holds globally

        ROW_NUMBER() OVER (
            PARTITION BY r.bib_record
            ORDER BY pos.global_queue_position
        ) AS relative_queue_position, -- position among same-bib holds that are actually in the result set

        EXTRACT(EPOCH FROM COALESCE(
            NULLIF(BTRIM(default_estimated_wait_interval.value,'"'),''),
            '0 seconds'
        )::INTERVAL) AS default_estimated_wait,

        EXTRACT(EPOCH FROM COALESCE(
            NULLIF(BTRIM(min_estimated_wait_interval.value,'"'),''),
            '0 seconds'
        )::INTERVAL) AS min_estimated_wait,

        COALESCE(hold_wait.potenials,0) AS potentials,
        COALESCE(hold_wait.other_holds,0) AS other_holds,
        COALESCE(hold_wait.total_wait_time,0) AS total_wait_time,

        n.count AS notification_count,
        n.max AS last_notification_time

  FROM  action.hold_request h
        JOIN reporter.hold_request_record r ON (r.id = h.id)
        JOIN actor.usr u ON (u.id = h.usr)
        JOIN permission.grp_tree pgt ON (u.profile = pgt.id)
        JOIN actor.card uc ON (uc.id = u.card)
        JOIN actor.usr ru ON (ru.id = h.requestor)
        LEFT JOIN actor.card ruc ON (ruc.id = ru.card)
        JOIN actor.org_unit pl ON (h.pickup_lib = pl.id)
        JOIN actor.org_unit rl ON (h.request_lib = rl.id)
        JOIN actor.org_unit sl ON (h.selection_ou = sl.id)
        JOIN actor.org_unit ul ON (u.home_ou = ul.id)
        JOIN t_field ON TRUE
        JOIN a_field ON TRUE
        JOIN s_field ON TRUE
        JOIN y_field ON TRUE
        LEFT JOIN actor.usr cu ON (h.canceled_by = cu.id)
        LEFT JOIN actor.card cuc ON (cu.card = cuc.id)
        LEFT JOIN actor.workstation caw ON (h.canceling_ws = caw.id)
        LEFT JOIN action.hold_request_cancel_cause cc ON (h.cancel_cause = cc.id)
        LEFT JOIN biblio.monograph_part p ON (h.hold_type = 'P' AND p.id = h.target)
        LEFT JOIN serial.issuance siss ON (h.hold_type = 'I' AND siss.id = h.target)
        LEFT JOIN asset.copy cp ON (h.current_copy = cp.id OR (h.hold_type IN ('C','F','R') AND cp.id = h.target))
        LEFT JOIN actor.org_unit cl ON (cp.circ_lib = cl.id)
        LEFT JOIN config.copy_status cs ON (cp.status = cs.id)
        LEFT JOIN asset.copy_location acpl ON (cp.location = acpl.id)
        LEFT JOIN asset.copy_location_order acplo ON (cp.location = acplo.location AND cp.circ_lib = acplo.org)
        LEFT JOIN (
            SELECT *, (ROW_NUMBER() OVER (ORDER BY name) + 1000000) AS fallback_position
            FROM asset.copy_location
        ) acpl_ordered ON (acpl_ordered.id = cp.location)
        LEFT JOIN asset.call_number cn ON ((cn.id = cp.call_number AND h.hold_type != 'V' ) OR (h.hold_type = 'V' AND cn.id = h.target))
        LEFT JOIN asset.call_number_prefix acnp ON (cn.prefix = acnp.id)
        LEFT JOIN asset.call_number_suffix acns ON (cn.suffix = acns.id)
        LEFT JOIN actor.org_unit ol ON (cn.owning_lib = ol.id)
        LEFT JOIN LATERAL (SELECT * FROM action.hold_transit_copy WHERE h.id = hold ORDER BY id DESC LIMIT 1) tr ON TRUE
        LEFT JOIN actor.org_unit tl ON (tr.source = tl.id)
        LEFT JOIN LATERAL ( -- correlated subquery finding the aprox ordering of open peer holds per bib, but ONLY for holds we'll eventually return!
            SELECT  sr.id,
                    ROW_NUMBER() OVER (ORDER BY sh.cut_in_line DESC NULLS LAST, sh.request_time) AS global_queue_position
              FROM  action.hold_request sh
                    JOIN reporter.hold_request_record sr ON (sh.id = sr.id AND sh.cancel_time IS NULL AND sh.fulfillment_time IS NULL)
              WHERE sr.bib_record = r.bib_record
        ) pos ON (pos.id=h.id)
        LEFT JOIN LATERAL (SELECT COUNT(*) FROM action.hold_request_note WHERE h.id = hold AND (pub = TRUE OR staff = $is_staff_request)) notes ON TRUE
        LEFT JOIN LATERAL (SELECT COUNT(*), MAX(notify_time) FROM action.hold_notification WHERE h.id = hold) n ON TRUE
        LEFT JOIN LATERAL (SELECT FIRST(value) AS value FROM metabib.display_entry WHERE source = r.bib_record AND field = t_field.field) t ON TRUE
        LEFT JOIN LATERAL (SELECT FIRST(value) AS value FROM metabib.display_entry WHERE source = r.bib_record AND field = a_field.field) a ON TRUE
        LEFT JOIN LATERAL (SELECT FIRST(value) AS value FROM metabib.display_entry WHERE source = r.bib_record AND field = s_field.field) s ON TRUE
        LEFT JOIN LATERAL (SELECT FIRST(value) AS value FROM metabib.display_entry WHERE source = r.bib_record AND field = y_field.field) y ON TRUE
        LEFT JOIN LATERAL actor.org_unit_ancestor_setting('circ.holds.default_estimated_wait_interval',u.home_ou) AS default_estimated_wait_interval ON TRUE
        LEFT JOIN LATERAL actor.org_unit_ancestor_setting('circ.holds.min_estimated_wait_interval',u.home_ou) AS min_estimated_wait_interval ON TRUE
        LEFT JOIN LATERAL actor.org_unit_ancestor_setting('circ.hold_shelf_status_delay',h.pickup_lib) AS hold_wait_time ON TRUE,
        LATERAL (
            SELECT  COUNT(*) AS potenials,
                    COUNT(DISTINCT hold) AS other_holds,
                    SUM(
                        EXTRACT(EPOCH FROM
                            COALESCE(
                                cm.avg_wait_time,
                                COALESCE(NULLIF(BTRIM(default_estimated_wait_interval.value,'"'),''),'0 seconds')::INTERVAL
                            )
                        )
                    ) AS total_wait_time
              FROM  action.hold_copy_map m
                    JOIN asset.copy cp ON (cp.id = m.target_copy)
                    LEFT JOIN config.circ_modifier cm ON (cp.circ_modifier = cm.code)
              WHERE m.hold = h.id
        ) AS hold_wait
  WHERE $initial_condition
    SQL

    my %field_map = (
        record_id => 'r.bib_record',
        usr_id => 'u.id',
        usr_alias => 'u.alias',
        cs_id => 'cs.id',
        cp_id => 'cp.id',
        cp_deleted => 'cp.deleted',
        cancel_time => 'h.cancel_time',
        tr_cancel_time => 'tr.cancel_time',
    );

    my $restricted = 0;
    for my $r (keys %$restrictions) {
        my $real = $field_map{$r} || $r;
        next if ($r =~ /[^a-z_.]/); # skip obvious bad inputs

        my $not = '';
        if (ref($$restrictions{$r}) and ref($$restrictions{$r}) =~ /HASH/) {
            $not = 'NOT';
            $$restrictions{$r} = $$restrictions{$r}{not};
        }

        if (!defined($$restrictions{$r})) { 
            $select .= " AND $real IS $not NULL ";
        } elsif (ref($$restrictions{$r})) { 
            $select .= " AND $real $not IN (\$_$$\$" . join("\$_$$\$,\$_$$\$", @{$$restrictions{$r}}) . "\$_$$\$)";
        } else {
            $not = '!' if $not;
            $select .= " AND $real $not= \$_$$\$$$restrictions{$r}\$_$$\$";
        }

        $restricted++;
    }

    return 0 unless $restricted;

    my @ob;
    for my $o (@$order_by) {
        next unless $o;
        my ($r) = keys %$o;
        next if ($r =~ /[^a-z_.]/); # skip obvious bad inputs
        my $real = $field_map{$r} || $r;
        push(@ob, $real);
        $ob[-1] .= ' DESC' if ($$o{$r}->{dir} and $$o{$r}->{dir} =~ /^d/i);
        $ob[-1] .= ' NULLS LAST' if ($$o{$r}->{nulls} and $$o{$r}->{nulls} =~ /^l/i);
        $ob[-1] .= ' NULLS FIRST' if ($$o{$r}->{nulls} and $$o{$r}->{nulls} =~ /^f/i);
    }

    $select .= ' ORDER BY ' . join(', ', @ob) if (@ob);
    $select .= ' LIMIT ' . $limit if ($limit and $limit =~ /^\d+$/);
    $select .= ' OFFSET ' . $offset if ($offset and $offset =~ /^\d+$/);

    my $sth = action::hold_request->db_Main->prepare($select);
    $sth->execute(@bind_values);

    my @list = $sth->fetchall_hash;
    $client->respond(int(scalar(@list))); # send the row count first, for progress tracking
    $client->respond( $_ ) for (@list);

    $client->respond_complete;
}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.live_holds.wide_hash',
    api_level       => 1,
    stream          => 1,
    max_bundle_count=> 1,
    method          => 'wide_hold_data',
);


sub purge_hold_reset_entries {
    my $self = shift;
    my $client = shift;
    my $age = shift;

    local $OpenILS::Application::Storage::WRITE = 1;

    my $sql = <<"    SQL";
        DELETE FROM action.hold_request_reset_reason_entry r
            USING action.hold_request h, actor.usr u
            WHERE
                h.id = r.hold AND
                u.id = h.usr AND
                AGE(reset_time) > COALESCE( BTRIM( (
                    SELECT value FROM actor.org_unit_ancestor_setting(
                    'circ.hold_reset_reason_entry_age_threshold', u.home_ou)),'"' ), '$age')::INTERVAL
    SQL

    my $sth = action::hold_request->db_Main->prepare($sql);
    $sth->execute();

    return 1;

}
__PACKAGE__->register_method(
    api_name        => 'open-ils.storage.action.hold_request.purge_hold_reset_entries',
    api_level       => 1,
    stream      => 0,
    argc        => 0,
    method          => 'purge_hold_reset_entries',
);

1;

