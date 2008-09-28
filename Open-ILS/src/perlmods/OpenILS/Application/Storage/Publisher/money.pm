package OpenILS::Application::Storage::Publisher::money;
use base qw/OpenILS::Application::Storage/;
use OpenSRF::Utils::Logger qw/:level/;

my $log = 'OpenSRF::Utils::Logger';

sub _make_mbts {
        my @xacts = @_;

        my @mbts;
        for my $x (@xacts) {
                my $s = new Fieldmapper::money::billable_transaction_summary;
                $s->id( $x->id );
                $s->usr( $x->usr );
                $s->xact_start( $x->xact_start );
                $s->xact_finish( $x->xact_finish );

                my $to = 0;
                my $lb = undef;
                for my $b ($x->billings) {
                        next if ($b->voided);
			#$log->debug( "billing is ".$b->amount, DEBUG );
                        $to += ($b->amount * 100);
                        $lb ||= $b->billing_ts;
                        if ($b->billing_ts ge $lb) {
                                $lb = $b->billing_ts;
                                $s->last_billing_note($b->note);
                                $s->last_billing_ts($b->billing_ts);
                                $s->last_billing_type($b->billing_type);
                        }
                }

                $s->total_owed( sprintf('%0.2f', ($to) / 100 ) );

                my $tp = 0;
                my $lp = undef;
                for my $p ($x->payments) {
			#$log->debug( "payment is ".$p->amount." voided = ".$p->voided, DEBUG );
                        next if ($p->voided eq 't');
                        $tp += ($p->amount * 100);
                        $lp ||= $p->payment_ts;
                        if ($p->payment_ts ge $lp) {
                                $lp = $p->payment_ts;
                                $s->last_payment_note($p->note);
                                $s->last_payment_ts($p->payment_ts);
                                $s->last_payment_type($p->payment_type);
                        }
                }
                $s->total_paid( sprintf('%0.2f', ($tp) / 100 ) );

                $s->balance_owed( sprintf('%0.2f', (($to) - ($tp)) / 100) );
		#$log->debug( "balance of ".$x->id." == ".$s->balance_owed, DEBUG );

                $s->xact_type( 'grocery' ) if (money::grocery->retrieve($x->id));
                $s->xact_type( 'circulation' ) if (action::circulation->retrieve($x->id));

                push @mbts, $s;
        }

        return @mbts;
}

sub search_mbts {
	my $self = shift;
	my $client = shift;
	my $search = shift;

	my @xacts = money::billable_transaction->search_where( $search );
	$client->respond( $_ ) for (_make_mbts(@xacts));

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'search_mbts',
	api_name	=> 'open-ils.storage.money.billable_transaction.summary.search',
	stream		=> 1,
	argc		=> 1,
);

sub search_ous {
	my $self = shift;
	my $client = shift;
	my $usr = shift;

	my @xacts = $self->method_lookup( 'open-ils.storage.money.billable_transaction.summary.search' )->run( { usr => $usr, xact_finish => undef } );

	my ($total,$owed,$paid) = (0.0,0.0,0.0);
	for my $x (@xacts) {
		$total += $x->total_owed;
		$owed += $x->balance_owed;
		$paid += $x->total_paid;
	}

	my $ous = Fieldmapper::money::open_user_summary->new;
	$ous->usr( $usr );
	$ous->total_paid( sprintf('%0.2f', $paid) );
	$ous->total_owed( sprintf('%0.2f', $total) );
	$ous->balance_owed( sprintf('%0.2f', $owed) );

	return $ous;
}
__PACKAGE__->register_method(
	method		=> 'search_ous',
	api_name	=> 'open-ils.storage.money.open_user_summary.search',
	argc		=> 1,
);


sub new_collections {
	my $self = shift;
	my $client = shift;
	my $age = shift;
	my $amount = shift;
	my @loc = @_;

	my $mct = money::collections_tracker->table;
	my $mb = money::billing->table;
	my $circ = action::circulation->table;
	my $mg = money::grocery->table;
	my $descendants = "actor.org_unit_descendants((select id from actor.org_unit where shortname = ?))";

	my $SQL = <<"	SQL";

select
        usr,
        MAX(last_billing) as last_pertinent_billing,
        SUM(total_billing) - SUM(COALESCE(p.amount,0)) as threshold_amount
  from  (select
                x.id,
                x.usr,
                MAX(b.billing_ts) as last_billing,
                SUM(b.amount) AS total_billing
          from  action.circulation x
                left join money.collections_tracker c ON (c.usr = x.usr AND c.location = ?)
                join money.billing b on (b.xact = x.id)
          where x.xact_finish is null
                and c.id is null
                and x.circ_lib in (XX)
                and b.billing_ts < current_timestamp - ? * '1 day'::interval
                and not b.voided
          group by 1,2

                  union all

         select
                x.id,
                x.usr,
                MAX(b.billing_ts) as last_billing,
                SUM(b.amount) AS total_billing
          from  money.grocery x
                left join money.collections_tracker c ON (c.usr = x.usr AND c.location = ?)
                join money.billing b on (b.xact = x.id)
          where x.xact_finish is null
                and c.id is null
                and x.billing_location in (XX)
                and b.billing_ts < current_timestamp - ? * '1 day'::interval
                and not b.voided
          group by 1,2
        ) full_list
        left join money.payment p on (full_list.id = p.xact)
  group by 1
  having SUM(total_billing) - SUM(COALESCE(p.amount,0)) > ?
;
	SQL

	my @l_ids;
	for my $l (@loc) {
		my ($org) = actor::org_unit->search( shortname => uc($l) );
		next unless $org;

		my $o_list = actor::org_unit->db_Main->selectcol_arrayref( "SELECT id FROM actor.org_unit_descendants(?);", {}, $org->id );
		next unless (@$o_list);

		my $o_txt = join ',' => @$o_list;

		(my $real_sql = $SQL) =~ s/XX/$o_txt/gsm;

		my $sth = money::collections_tracker->db_Main->prepare($real_sql);
		$sth->execute( $org->id, $age, $org->id, $age, $amount );

		while (my $row = $sth->fetchrow_hashref) {
			#$row->{usr} = actor::user->retrieve($row->{usr})->to_fieldmapper;
			$client->respond( $row );
		}
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'new_collections',
	api_name	=> 'open-ils.storage.money.collections.users_of_interest',
	stream		=> 1,
	argc		=> 3,
);

sub users_owing_money {
	my $self = shift;
	my $client = shift;
	my $start = shift;
	my $end = shift;
	my $amount = shift;
	my @loc = @_;

	my $mct = money::collections_tracker->table;
	my $mb = money::billing->table;
	my $circ = action::circulation->table;
	my $mg = money::grocery->table;
	my $descendants = "actor.org_unit_descendants((select id from actor.org_unit where shortname = ?))";

	my $SQL = <<"	SQL";

select
        usr,
        SUM(total_billing) - SUM(COALESCE(p.amount,0)) as threshold_amount
  from  (select
                x.id,
                x.usr,
                SUM(b.amount) AS total_billing
          from  action.circulation x
                join money.billing b on (b.xact = x.id)
          where x.xact_finish is null
                and x.circ_lib in (XX)
                and b.billing_ts between ? and ?
                and not b.voided
          group by 1,2

                  union all

         select
                x.id,
                x.usr,
                SUM(b.amount) AS total_billing
          from  money.grocery x
                join money.billing b on (b.xact = x.id)
          where x.xact_finish is null
                and x.billing_location in (XX)
                and b.billing_ts between ? and ?
                and not b.voided
          group by 1,2
        ) full_list
        left join money.payment p on (full_list.id = p.xact)
  group by 1
  having SUM(total_billing) - SUM(COALESCE(p.amount,0)) > ?
;
	SQL

	my @l_ids;
	for my $l (@loc) {
		my ($org) = actor::org_unit->search( shortname => uc($l) );
		next unless $org;

		my $o_list = actor::org_unit->db_Main->selectcol_arrayref( "SELECT id FROM actor.org_unit_descendants(?);", {}, $org->id );
		next unless (@$o_list);

		my $o_txt = join ',' => @$o_list;

		(my $real_sql = $SQL) =~ s/XX/$o_txt/gsm;

		my $sth = money::collections_tracker->db_Main->prepare($real_sql);
		$sth->execute( $start, $end, $start, $end, $amount );

		while (my $row = $sth->fetchrow_hashref) {
			#$row->{usr} = actor::user->retrieve($row->{usr})->to_fieldmapper;
			$client->respond( $row );
		}
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'users_owing_money',
	api_name	=> 'open-ils.storage.money.collections.users_owing_money',
	stream		=> 1,
	argc		=> 4,
);

sub active_in_collections {
	my $self = shift;
	my $client = shift;
	my $startdate = shift;
	my $enddate = shift;
	my @loc = @_;

	my $mct = money::collections_tracker->table;
	my $mb = money::billing->table;
	my $circ = action::circulation->table;
	my $mg = money::grocery->table;

	my $SQL = <<"	SQL";
SELECT  usr,
        MAX(last_pertinent_billing) AS last_pertinent_billing,
        MAX(last_pertinent_payment) AS last_pertinent_payment
  FROM  (
                SELECT  lt.usr,
                        NULL::TIMESTAMPTZ AS last_pertinent_billing,
                        NULL::TIMESTAMPTZ AS last_pertinent_payment
                  FROM  money.grocery lt
                        JOIN money.collections_tracker cl ON (lt.usr = cl.usr)
                        JOIN money.billing bl ON (lt.id = bl.xact)
                  WHERE cl.location = ?
                        AND lt.billing_location IN (XX)
                        AND bl.void_time BETWEEN ? AND ?
                  GROUP BY 1

                                UNION ALL
                SELECT  lt.usr,
                        MAX(bl.billing_ts) AS last_pertinent_billing,
                        NULL::TIMESTAMPTZ AS last_pertinent_payment
                  FROM  money.grocery lt
                        JOIN money.collections_tracker cl ON (lt.usr = cl.usr)
                        JOIN money.billing bl ON (lt.id = bl.xact)
                  WHERE cl.location = ?
                        AND lt.billing_location IN (XX)
                        AND bl.billing_ts BETWEEN ? AND ?
                  GROUP BY 1

                                UNION ALL
                SELECT  lt.usr,
                        NULL::TIMESTAMPTZ AS last_pertinent_billing,
                        MAX(pm.payment_ts) AS last_pertinent_payment
                  FROM  money.grocery lt
                        JOIN money.collections_tracker cl ON (lt.usr = cl.usr)
                        JOIN money.payment pm ON (lt.id = pm.xact)
                  WHERE cl.location = ?
                        AND lt.billing_location IN (XX)
                        AND pm.payment_ts BETWEEN ? AND ?
                  GROUP BY 1

                                UNION ALL
                SELECT  lt.usr,
                        NULL::TIMESTAMPTZ AS last_pertinent_billing,
                        NULL::TIMESTAMPTZ AS last_pertinent_payment
                  FROM  action.circulation lt
                        JOIN money.collections_tracker cl ON (lt.usr = cl.usr)
                  WHERE cl.location = ?
                        AND lt.circ_lib IN (XX)
                        AND lt.checkin_time BETWEEN ? AND ?
                  GROUP BY 1

                                UNION ALL
                SELECT  lt.usr,
                        NULL::TIMESTAMPTZ AS last_pertinent_billing,
                        MAX(pm.payment_ts) AS last_pertinent_payment
                  FROM  action.circulation lt
                        JOIN money.collections_tracker cl ON (lt.usr = cl.usr)
                        JOIN money.payment pm ON (lt.id = pm.xact)
                  WHERE cl.location = ?
                        AND lt.circ_lib IN (XX)
                        AND pm.payment_ts BETWEEN ? AND ?
                  GROUP BY 1

                                UNION ALL
                SELECT  lt.usr,
                        NULL::TIMESTAMPTZ AS last_pertinent_billing,
                        NULL::TIMESTAMPTZ AS last_pertinent_payment
                  FROM  action.circulation lt
                        JOIN money.collections_tracker cl ON (lt.usr = cl.usr)
                        JOIN money.billing bl ON (lt.id = bl.xact)
                  WHERE cl.location = ?
                        AND lt.circ_lib IN (XX)
                        AND bl.void_time BETWEEN ? AND ?
                  GROUP BY 1

                                UNION ALL
                SELECT  lt.usr,
                        MAX(bl.billing_ts) AS last_pertinent_billing,
                        NULL::TIMESTAMPTZ AS last_pertinent_payment
                  FROM  action.circulation lt
                        JOIN money.collections_tracker cl ON (lt.usr = cl.usr)
                        JOIN money.billing bl ON (lt.id = bl.xact)
                  WHERE cl.location = ?
                        AND lt.circ_lib IN (XX)
                        AND bl.billing_ts BETWEEN ? AND ?
                  GROUP BY 1
        ) foo
  GROUP BY 1
;
	SQL

	my @l_ids;
	for my $l (@loc) {
		my ($org) = actor::org_unit->search( shortname => uc($l) );
		next unless $org;

		my $o_list = actor::org_unit->db_Main->selectcol_arrayref( "SELECT id FROM actor.org_unit_descendants(?);", {}, $org->id );
		next unless (@$o_list);

		my $o_txt = join ',' => @$o_list;

		(my $real_sql = $SQL) =~ s/XX/$o_txt/gsm;

		my $sth = money::collections_tracker->db_Main->prepare($real_sql);
		$sth->execute(
			$org->id, $startdate, $enddate,
			$org->id, $startdate, $enddate,
			$org->id, $startdate, $enddate,
			$org->id, $startdate, $enddate,
			$org->id, $startdate, $enddate,
			$org->id, $startdate, $enddate,
			$org->id, $startdate, $enddate
		);

		while (my $row = $sth->fetchrow_hashref) {
			$row->{usr} = actor::user->retrieve($row->{usr})->to_fieldmapper;
			$client->respond( $row );
		}
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'active_in_collections',
	api_name	=> 'open-ils.storage.money.collections.users_with_activity',
	stream		=> 1,
	argc		=> 3,
);

sub ou_desk_payments {
	my $self = shift;
	my $client = shift;
	my $lib = shift;
	my $startdate = shift;
	my $enddate = shift;

	return undef unless ($startdate =~ /^\d{4}-\d{2}-\d{2}$/o);
	return undef unless ($enddate =~ /^\d{4}-\d{2}-\d{2}$/o);
	return undef unless ($lib =~ /^\d+$/o);

	my $sql = <<"	SQL";

	SELECT	ws.id as workstation,
		SUM( CASE WHEN p.payment_type = 'cash_payment' THEN p.amount ELSE 0.0 END ) as cash_payment,
		SUM( CASE WHEN p.payment_type = 'check_payment' THEN p.amount ELSE 0.0 END ) as check_payment,
		SUM( CASE WHEN p.payment_type = 'credit_card_payment' THEN p.amount ELSE 0.0 END ) as credit_card_payment
	  FROM	money.desk_payment_view p
		JOIN actor.workstation ws ON (ws.id = p.cash_drawer)
	  WHERE	p.payment_ts >= '$startdate'
		AND p.payment_ts < '$enddate'::TIMESTAMPTZ + INTERVAL '1 day'
		AND p.voided IS FALSE
		AND ws.owning_lib = $lib
	 GROUP BY 1
	 ORDER BY 1;

	SQL

	my $rows = money::payment->db_Main->selectall_arrayref( $sql );

	for my $r (@$rows) {
		my $x = new Fieldmapper::money::workstation_payment_summary;
		$x->workstation( actor::workstation->retrieve($$r[0])->to_fieldmapper );
		$x->cash_payment($$r[1]);
		$x->check_payment($$r[2]);
		$x->credit_card_payment($$r[3]);

		$client->respond($x);
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'ou_desk_payments',
	api_name	=> 'open-ils.storage.money.org_unit.desk_payments',
	stream		=> 1,
	argc		=> 3,
);

sub ou_user_payments {
	my $self = shift;
	my $client = shift;
	my $lib = shift;
	my $startdate = shift;
	my $enddate = shift;

	return undef unless ($startdate =~ /^\d{4}-\d{2}-\d{2}$/o);
	return undef unless ($enddate =~ /^\d{4}-\d{2}-\d{2}$/o);
	return undef unless ($lib =~ /^\d+$/o);

	my $sql = <<"	SQL";

       	SELECT	au.id as usr,
		SUM( CASE WHEN p.payment_type = 'forgive_payment' THEN p.amount ELSE 0.0 END ) as forgive_payment,
		SUM( CASE WHEN p.payment_type = 'work_payment' THEN p.amount ELSE 0.0 END ) as work_payment,
		SUM( CASE WHEN p.payment_type = 'credit_payment' THEN p.amount ELSE 0.0 END ) as credit_payment,
		SUM( CASE WHEN p.payment_type = 'goods_payment' THEN p.amount ELSE 0.0 END ) as goods_payment
          FROM  money.bnm_payment_view p
                JOIN actor.usr au ON (au.id = p.accepting_usr)
          WHERE p.payment_ts >= '$startdate'
                AND p.payment_ts < '$enddate'::TIMESTAMPTZ + INTERVAL '1 day'
                AND p.voided IS FALSE
                AND au.home_ou = $lib
		AND p.payment_type IN ('credit_payment','forgive_payment','work_payment','goods_payment')
         GROUP BY 1
         ORDER BY 1;

	SQL

	my $rows = money::payment->db_Main->selectall_arrayref( $sql );

	for my $r (@$rows) {
		my $x = new Fieldmapper::money::user_payment_summary;
		$x->usr( actor::user->retrieve($$r[0])->to_fieldmapper );
		$x->forgive_payment($$r[1]);
		$x->work_payment($$r[2]);
		$x->credit_payment($$r[3]);
		$x->goods_payment($$r[4]);

		$client->respond($x);
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'ou_user_payments',
	api_name	=> 'open-ils.storage.money.org_unit.user_payments',
	stream		=> 1,
	argc		=> 3,
);

sub mark_unrecovered {
	my $self = shift;
	my $xact = shift;

    my $x = money::billable_xact->retrieve($xact);
    $x->unrecovered( 't' );
    return $x->update;
}
__PACKAGE__->register_method(
	method		=> 'mark_unrecovered',
	api_name	=> 'open-ils.storage.money.billable_xact.mark_unrecovered',
	argc		=> 1,
);


1;
