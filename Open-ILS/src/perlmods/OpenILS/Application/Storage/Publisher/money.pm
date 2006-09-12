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
                        $to += int($b->amount * 100);
                        $lb ||= $b->billing_ts;
                        if ($b->billing_ts ge $lb) {
                                $lb = $b->billing_ts;
                                $s->last_billing_note($b->note);
                                $s->last_billing_ts($b->billing_ts);
                                $s->last_billing_type($b->billing_type);
                        }
                }

                $s->total_owed( sprintf('%0.2f', int($to) / 100 ) );

                my $tp = 0;
                my $lp = undef;
                for my $p ($x->payments) {
			#$log->debug( "payment is ".$p->amount." voided = ".$p->voided, DEBUG );
                        next if ($p->voided eq 't');
                        $tp += int($p->amount * 100);
                        $lp ||= $p->payment_ts;
                        if ($p->payment_ts ge $lp) {
                                $lp = $p->payment_ts;
                                $s->last_payment_note($p->note);
                                $s->last_payment_ts($p->payment_ts);
                                $s->last_payment_type($p->payment_type);
                        }
                }
                $s->total_paid( sprintf('%0.2f', int($tp) / 100 ) );

                $s->balance_owed( sprintf('%0.2f', int(int($to) - int($tp)) / 100) );
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
		SELECT	lt.usr,
			MAX(bl.billing_ts) AS last_pertinent_billing,
			SUM(bl.amount) - COALESCE(SUM((SELECT SUM(amount) FROM money.payment WHERE xact = lt.id)),0) AS threshold_amount
		  FROM	( SELECT id,usr,billing_location AS location FROM money.grocery
		  		UNION ALL
			  SELECT id,usr,circ_lib AS location FROM action.circulation ) AS lt
			JOIN $descendants d ON (lt.location = d.id)
			JOIN money.billing bl ON (lt.id = bl.xact AND bl.voided IS FALSE)
		  WHERE	AGE(bl.billing_ts) > ?
		  GROUP BY lt.usr
		  HAVING  SUM(
		  		(SELECT	COUNT(*)
				  FROM	money.collections_tracker
				  WHERE	usr = lt.usr
				  	AND location in (
				  		(SELECT	id
						  FROM	$descendants )
					)
				) ) = 0
		  	AND (SUM(bl.amount) - COALESCE(SUM((SELECT SUM(amount) FROM money.payment WHERE xact = lt.id)),0)) > ? 
	SQL

	my @l_ids;
	for my $l (@loc) {
		my $sth = money::collections_tracker->db_Main->prepare($SQL);
		$sth->execute(uc($l), $age, uc($l), $amount );
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
	my $descendants = "actor.org_unit_descendants((select id from actor.org_unit where shortname = ?))";

	my $SQL = <<"	SQL";
		SELECT	lt.usr,
			MAX(bl.billing_ts) AS last_pertinent_billing,
			MAX(pm.payment_ts) AS last_pertinent_payment
		  FROM	( SELECT id,usr,billing_location AS location, 'g'::char AS x_type FROM money.grocery
		  		UNION ALL
			  SELECT id,usr,circ_lib AS location, 'c'::char AS x_type FROM action.circulation
		  		UNION ALL
			  SELECT id,usr,circ_lib AS location, 'i'::char AS x_type FROM action.circulation
			    WHERE checkin_time between ? and ? ) AS lt
			JOIN $descendants d ON (lt.location = d.id)
			JOIN money.collections_tracker cl ON (lt.usr = cl.usr)
			LEFT JOIN money.billing bl ON (lt.id = bl.xact)
			LEFT JOIN money.payment pm ON (lt.id = pm.xact)
		  WHERE	bl.billing_ts between ? and ?
			OR pm.payment_ts between ? and ?
			OR lt.x_type = 'i'::char
		  GROUP BY 1
	SQL

	my @l_ids;
	for my $l (@loc) {
		my $sth = money::collections_tracker->db_Main->prepare($SQL);
		$sth->execute( $startdate, $enddate, uc($l), $startdate, $enddate, $startdate, $enddate );
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

SELECT	*
  FROM	crosstab(\$\$
	 SELECT	ws.id,
		p.payment_type,
		SUM(COALESCE(p.amount,0.0))
	  FROM	money.desk_payment_view p
		JOIN actor.workstation ws ON (ws.id = p.cash_drawer)
	  WHERE	p.payment_ts >= '$startdate'
		AND p.payment_ts < '$enddate'::TIMESTAMPTZ + INTERVAL '1 day'
		AND p.voided IS FALSE
		AND ws.owning_lib = $lib
	 GROUP BY 1, 2
	 ORDER BY 1,2
	\$\$) AS X(
	  workstation int,
	  cash_payment numeric(10,2),
	  check_payment numeric(10,2),
	  credit_card_payment numeric(10,2) );

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

SELECT  *
  FROM  crosstab(\$\$
         SELECT au.id,
                p.payment_type,
                SUM(COALESCE(p.amount,0.0))
          FROM  money.bnm_payment_view p
                JOIN actor.usr au ON (au.id = p.accepting_usr)
          WHERE p.payment_ts >= '$startdate'
                AND p.payment_ts < '$enddate'::TIMESTAMPTZ + INTERVAL '1 day'
                AND p.voided IS FALSE
                AND au.home_ou = $lib
		AND p.payment_type IN ('credit_payment','forgive_payment','work_payment')
         GROUP BY 1, 2
         ORDER BY 1,2
        \$\$) AS X(
          usr int,
          forgive_payment numeric(10,2),
          work_payment numeric(10,2),
          credit_payment numeric(10,2) );

	SQL

	my $rows = money::payment->db_Main->selectall_arrayref( $sql );

	for my $r (@$rows) {
		my $x = new Fieldmapper::money::user_payment_summary;
		$x->usr( actor::user->retrieve($$r[0])->to_fieldmapper );
		$x->forgive_payment($$r[1]);
		$x->work_payment($$r[2]);
		$x->credit_payment($$r[3]);

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


1;
