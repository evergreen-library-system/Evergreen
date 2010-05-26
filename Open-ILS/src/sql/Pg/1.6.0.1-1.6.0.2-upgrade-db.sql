/*
 * Copyright (C) 2010  Equinox Software, Inc.
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



INSERT INTO config.upgrade_log (version) VALUES ('1.6.0.1');

INSERT INTO config.billing_type (id, name, owner) VALUES
    ( 101, oils_i18n_gettext(101, 'Misc', 'cbt', 'name'), 1);
 
SELECT SETVAL('config.billing_type_id_seq'::TEXT, (SELECT MAX(id) FROM config.billing_type));

