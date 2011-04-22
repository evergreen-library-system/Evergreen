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

INSERT INTO config.upgrade_log(version) VALUES ('1.6.1.5');

INSERT INTO permission.perm_list (code) VALUES ('VIEW_GROUP_PENALTY_THRESHOLD'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_CIRC_MATRIX_MATCHPOINT'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_HOLD_MATRIX_MATCHPOINT'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_GROUP_PENALTY_THRESHOLD'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_SURVEY'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_STANDING_PENALTY'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_BOOKING_RESERVATION_ATTR_MAP'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_ACQ_DISTRIB_FORMULA'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_ACQ_FISCAL_YEAR'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_ACQ_FUND_TAG'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_ACQ_FUND'); 
INSERT INTO permission.perm_list (code) VALUES ('VIEW_FUND'); 
INSERT INTO permission.perm_list (code) VALUES ('MANAGE_FUND'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_AGE_PROTECT_RULE'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_CIRC_MATRIX_MATCHPOINT'); 
INSERT INTO permission.perm_list (code) VALUES ('VIEW_CIRC_MATRIX_MATCHPOINT'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_CIRC_MOD'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_FIELD_DOC'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_FUNDING_SOURCE'); 
INSERT INTO permission.perm_list (code) VALUES ('MANAGE_FUNDING_SOURCE'); 
INSERT INTO permission.perm_list (code) VALUES ('VIEW_FUNDING_SOURCE'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_HOLD_CANCEL_CAUSE'); 
INSERT INTO permission.perm_list (code) VALUES ('VIEW_HOLD_MATRIX_MATCHPOINT'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_IDENT_TYPE'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_MARC_CODE'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_MAX_FINE_RULE'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_PROVIDER'); 
INSERT INTO permission.perm_list (code) VALUES ('MANAGE_PROVIDER'); 
INSERT INTO permission.perm_list (code) VALUES ('VIEW_PROVIDER'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_RECURING_FINE_RULE'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_STANDING_PENALTY'); 
INSERT INTO permission.perm_list (code) VALUES ('VIEW_STANDING_PENALTY'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_TRIGGER_EVENT_DEF'); 
INSERT INTO permission.perm_list (code) VALUES ('VIEW_TRIGGER_EVENT_DEF'); 
INSERT INTO permission.perm_list (code) VALUES ('ADMIN_Z3950_SOURCE'); 

