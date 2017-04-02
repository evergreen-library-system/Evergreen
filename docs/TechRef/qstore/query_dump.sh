pg_dump -n query \
	--file=query_dump.sql \
	--data-only \
	--schema=query \
	--disable-triggers \
	--host=localhost \
	--username=evergreen \
	--password \
	evergreen
