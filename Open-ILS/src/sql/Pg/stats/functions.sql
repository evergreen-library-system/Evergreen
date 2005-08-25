CREATE OR REPLACE FUNCTION dim_row_hash () RETURNS TRIGGER AS $func$
	use Digest::MD5 qw/md5_hex/;

	$_TD->{new}{id} =
		md5_hex(
			join(	'' =>
				map {
					defined $_TD->{new}{$_} ?
						( $_TD->{new}{$_} ) :
						()
				} sort grep {
					$_ != 'id'
				} keys %{ $_TD->{new} }
			)
		);

	my $schema = spi_exec_query(<<"	SQL")->{rows}[0]{nspname};
	  SELECT	nspname
	    FROM	pg_class c
		  	JOIN pg_namespace n ON (c.relnamespace = n.oid);
	SQL

	return 'SKIP' if (spi_exec_query(<<"	SQL")->{processed});
	  SELECT	1
	    FROM	$schema.$$_TD{relname}
	    WHERE	id = '$$_TD{new}{id}';
	SQL

	return 'MODIFY';
$func$ LANGUAGE 'plperlu';
