INSERT INTO config.upgrade_log (version) VALUES ('0052');

CREATE TABLE asset.copy_location_order
(
	id              SERIAL           PRIMARY KEY,
	location        INT              NOT NULL
	                                     REFERENCES asset.copy_location
	                                     ON DELETE CASCADE
	                                     DEFERRABLE INITIALLY DEFERRED,
	org             INT              NOT NULL
	                                     REFERENCES actor.org_unit
	                                     ON DELETE CASCADE
	                                     DEFERRABLE INITIALLY DEFERRED,
	position        INT              NOT NULL DEFAULT 0,
	CONSTRAINT acplo_once_per_org UNIQUE ( location, org )
);

INSERT INTO permission.perm_list VALUES
(350, 'ADMIN_COPY_LOCATION_ORDER', oils_i18n_gettext(350, 'Allow a user to create/view/update/delete a copy location order', 'ppl', 'description'));

COMMIT;
