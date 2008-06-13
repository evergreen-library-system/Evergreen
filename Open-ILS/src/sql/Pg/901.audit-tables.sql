/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
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
 *
 */

BEGIN;

SELECT auditor.create_auditor ( 'actor', 'usr' );
SELECT auditor.create_auditor ( 'actor', 'usr_address' );
SELECT auditor.create_auditor ( 'actor', 'org_unit' );
SELECT auditor.create_auditor ( 'biblio', 'record_entry' );
SELECT auditor.create_auditor ( 'asset', 'call_number' );
SELECT auditor.create_auditor ( 'asset', 'copy' );

COMMIT;

