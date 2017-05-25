BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1041', :eg_version); -- stompro/csharp/gmcharlt

--delete all instances from permission.grp_perm_map first
DELETE FROM permission.grp_perm_map where perm in 
(select id from permission.perm_list where code='SET_CIRC_MISSING');

--delete all instances from permission.usr_perm_map too
DELETE FROM permission.usr_perm_map where perm in
(select id from permission.perm_list where code='SET_CIRC_MISSING');

--delete from permission.perm_list
DELETE FROM permission.perm_list where code='SET_CIRC_MISSING';

COMMIT;
