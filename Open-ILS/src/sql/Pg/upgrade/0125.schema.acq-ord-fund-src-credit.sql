BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0125'); -- Scott McKellar

CREATE VIEW acq.ordered_funding_source_credit AS
	SELECT
		CASE WHEN deadline_date IS NULL THEN
			2
		ELSE
			1
		END AS sort_priority,
		CASE WHEN deadline_date IS NULL THEN
			effective_date
		ELSE
			deadline_date
		END AS sort_date,
		id,
		funding_source,
		amount,
		note
	FROM
		acq.funding_source_credit;

COMMENT ON VIEW acq.ordered_funding_source_credit IS $$
/*
 * Copyright (C) 2009  Georgia Public Library Service
 * Scott McKellar <scott@gmail.com>
 *
 * The acq.ordered_funding_source_credit view is a prioritized
 * ordering of funding source credits.  When ordered by the first
 * three columns, this view defines the order in which the various
 * credits are to be tapped for spending, subject to the allocations
 * in the acq.fund_allocation table.
 *
 * The first column reflects the principle that we should spend
 * money with deadlines before spending money without deadlines.
 *
 * The second column reflects the principle that we should spend the
 * oldest money first.  For money with deadlines, that means that we
 * spend first from the credit with the earliest deadline.  For
 * money without deadlines, we spend first from the credit with the
 * earliest effective date.  
 *
 * The third column is a tie breaker to ensure a consistent
 * ordering.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

COMMIT;
