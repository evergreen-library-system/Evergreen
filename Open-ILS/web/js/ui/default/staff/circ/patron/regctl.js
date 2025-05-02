
angular.module('egCoreMod')
// toss tihs onto egCoreMod since the page app may vary

.factory('patronRegSvc', ['$q', '$filter', 'egCore', 'egLovefield', function($q, $filter, egCore, egLovefield) {

    var service = {
        field_doc : {},            // config.idl_field_doc
        profiles : [],             // permission groups
        profile_entries : [],      // permission gorup display entries
        edit_profiles : [],        // perm groups we can modify
        edit_profile_entries : [], // perm group display entries we can modify
        sms_carriers : [],
        user_settings : {},        // applied user settings
        user_setting_types : {},   // config.usr_setting_type
        opt_in_setting_types : {}, // config.usr_setting_type for event-def opt-in
        surveys : [],
        survey_questions : {},
        survey_answers : {},
        survey_responses : {},     // survey.responses for loaded patron in progress
        stat_cats : [],
        stat_cat_entry_maps : {},   // cat.id to selected value
        virt_id : -1,               // virtual ID for new objects
        locales : [],
        init_done : false           // have we loaded our initialization data?
    };

    // Launch a series of parallel data retrieval calls.
    service.init = function(scope) {

        // These are fetched with every instance of the page.
        var page_data = [
            service.get_user_settings(),
            service.get_clone_user(),
            service.get_stage_user()
        ];

        var common_data = [];
        if (!service.init_done) {
            // These are fetched with every instance of the app.
            common_data = [
                service.get_field_doc(),
                service.get_perm_groups(),
                service.get_perm_group_entries(),
                service.get_ident_types(),
                service.get_locales(),
                service.get_org_settings(),
                service.get_stat_cats(),
                service.get_surveys(),
                service.get_net_access_levels()
            ];
            service.init_done = true;
        }
        return $q.all(common_data.concat(page_data));
    };

    service.get_clone_user = function() {
        if (!service.clone_id) return $q.when();
        // we could load egUser and use its get() function, but loading
        // user.js into the standalone register UI would mean creating a
        // new module, since egUser is not loaded into egCoreMod.  This
        // is a lot simpler.
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.fleshed.retrieve',
            egCore.auth.token(), service.clone_id, 
            ['billing_address', 'mailing_address'])
        .then(function(cuser) {
            if (e = egCore.evt.parse(cuser)) {
                alert(e);
            } else {
                service.clone_user = cuser;
            }
        });
    }

    // When editing a user with addresses linked to other users, fetch
    // the linked user(s) so we can display their names and edit links.
    service.get_linked_addr_users = function(addrs) {
        angular.forEach(addrs, function(addr) {
            if (addr.usr == service.existing_patron.id()) return;
            egCore.pcrud.retrieve('au', addr.usr)
            .then(function(usr) {
                addr._linked_owner_id = usr.id();
                addr._linked_owner = service.format_name(
                    usr.family_name(),
                    usr.first_given_name(),
                    usr.second_given_name()
                );
            })
        });
    }

    service.apply_secondary_groups = function(user_id, group_ids) {
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.set_groups',
            egCore.auth.token(), user_id, group_ids)
        .then(function(resp) {
            if (resp == 1) {
                return true;
            } else {
                // debugging -- should be no events
                alert('linked groups failure ' + egCore.evt.parse(resp));
            }
        });
    }

    service.get_stage_user = function() {
        if (!service.stage_username) return $q.when();

        // fetch the staged user object
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.stage.retrieve.by_username',
            egCore.auth.token(), 
            service.stage_username
        ).then(function(suser) {
            if (e = egCore.evt.parse(suser)) {
                alert(e);
            } else {
                service.stage_user = suser;
            }
        }).then(function() {

            if (!service.stage_user) return;
            var requestor = service.stage_user.user.requesting_usr();

            if (!requestor) return;

            // fetch the requesting user
            return egCore.net.request(
                'open-ils.actor', 
                'open-ils.actor.user.retrieve.parts',
                egCore.auth.token(),
                requestor, 
                ['family_name', 'first_given_name', 'second_given_name'] 
            ).then(function(parts) {
                service.stage_user_requestor = 
                    service.format_name(parts[0], parts[1], parts[2]);
            })
        });
    }

    // See note above about not loading egUser.
    // TODO: i18n
    service.format_name = function(last, first, middle) {
        return last + ', ' + first + (middle ? ' ' + middle : '');
    }

    service.check_dupe_username = function(usrname) {

        // empty usernames can't be dupes
        if (!usrname) return $q.when(false);

        // avoid dupe check if username matches the originally loaded usrname
        if (service.existing_patron) {
            if (usrname == service.existing_patron.usrname())
                return $q.when(false);
        }

        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.username.exists',
            egCore.auth.token(), usrname);
    }

    // compare string with email address of loaded user, return true if different
    service.check_email_different = function(email) {
        if (service.existing_patron) {
            if (email != service.existing_patron.email()) {
                return true;
            }
        }
    }

    //service.check_grp_app_perm = function(grp_id) {

    // determine which user groups our user is not allowed to modify
    service.set_edit_profiles = function() {
        var all_app_perms = [];
        var failed_perms = [];

        // extract the application permissions
        angular.forEach(service.profiles, function(grp) {
            if (grp.application_perm())
                all_app_perms.push(grp.application_perm());
        }); 

        // fill in service.edit_profiles by inspecting failed_perms
        function traverse_grp_tree(grp, failed) {
            failed = failed || 
                failed_perms.indexOf(grp.application_perm()) > -1;

            if (!failed) service.edit_profiles.push(grp);

            angular.forEach(
                service.profiles.filter( // children of grp
                    function(p) { return p.parent() == grp.id() }),
                function(child) {traverse_grp_tree(child, failed)}
            );
        }

        return egCore.perm.hasPermAt(all_app_perms, true).then(
            function(perm_orgs) {
                angular.forEach(all_app_perms, function(p) {
                    if (perm_orgs[p].length == 0)
                        failed_perms.push(p);
                });

                traverse_grp_tree(egCore.env.pgt.tree);
            }
        );
    }

    service.set_edit_profile_entries = function() {
        var all_app_perms = [];
        var failed_perms = [];

        // extract the application permissions
        angular.forEach(service.profile_entries, function(entry) {
            if (entry.grp().application_perm())
                all_app_perms.push(entry.grp().application_perm());
        });

        // fill in service.edit_profiles by inspecting failed_perms
        function traverse_grp_tree(entry, failed) {
            failed = failed ||
                failed_perms.indexOf(entry.grp().application_perm()) > -1;

            if (!failed) service.edit_profile_entries.push(entry);

            angular.forEach(
                service.profile_entries.filter( // children of grp
                    function(p) { return p.parent() == entry.id() }),
                function(child) {traverse_grp_tree(child, failed)}
            );
        }

        return egCore.perm.hasPermAt(all_app_perms, true).then(
            function(perm_orgs) {
                angular.forEach(all_app_perms, function(p) {
                    if (perm_orgs[p].length == 0)
                        failed_perms.push(p);
                });

                angular.forEach(egCore.env.pgtde.tree, function(tree) {
                    traverse_grp_tree(tree);
                });
            }
        );
    }

    // resolves to a hash of perm-name => boolean value indicating
    // wether the user has the permission at org_id.
    service.has_perms_for_org = function(org_id) {

        var perms_needed = [
            'EDIT_SELF_IN_CLIENT',
            'UPDATE_USER',
            'CREATE_USER',
            'CREATE_USER_GROUP_LINK', 
            'UPDATE_PATRON_COLLECTIONS_EXEMPT',
            'UPDATE_PATRON_CLAIM_RETURN_COUNT',
            'UPDATE_PATRON_CLAIM_NEVER_CHECKED_OUT_COUNT',
            'UPDATE_PATRON_ACTIVE_CARD',
            'UPDATE_PATRON_PRIMARY_CARD'
        ];

        return egCore.perm.hasPermAt(perms_needed, true)
        .then(function(perm_map) {

            angular.forEach(perms_needed, function(perm) {
                perm_map[perm] = 
                    Boolean(perm_map[perm].indexOf(org_id) > -1);
            });

            return perm_map;
        });
    }

    service.get_surveys = function() {
        var org_ids = egCore.org.fullPath(egCore.auth.user().ws_ou(), true);

        return egCore.pcrud.search('asv', {
                owner : org_ids,
                start_date : {'<=' : 'now'},
                end_date : {'>=' : 'now'}
            }, {   
                flesh : 2, 
                flesh_fields : {
                    asv : ['questions'], 
                    asvq : ['answers']
                }
            }, 
            {atomic : true}
        ).then(function(surveys) {
            surveys = surveys.sort(function(a,b) {
                return a.name() < b.name() ? -1 : 1 });
            service.surveys = surveys;
            angular.forEach(surveys, function(survey) {
                angular.forEach(survey.questions(), function(question) {
                    service.survey_questions[question.id()] = question;
                    angular.forEach(question.answers(), function(answer) {
                        service.survey_answers[answer.id()] = answer;
                    });
                });
            });

            egLovefield.setListInOfflineCache('asv', service.surveys)
            egLovefield.setListInOfflineCache('asvq', service.survey_questions)
            egLovefield.setListInOfflineCache('asva', service.survey_answers)

        });
    }

    service.get_stat_cats = function() {
        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.stat_cat.actor.retrieve.all',
            egCore.auth.token(), egCore.auth.user().ws_ou()
        ).then(function(cats) {
            cats = cats.sort(function(a, b) {
                return a.name() < b.name() ? -1 : 1});
            angular.forEach(cats, function(cat) {
                cat.entries(
                    cat.entries().sort(function(a,b) {
                        return a.value() < b.value() ? -1 : 1
                    })
                );
            });
            service.stat_cats = cats;
            return egLovefield.setStatCatsCache(cats);
        });
    };

    service.get_org_settings = function() {
        return egCore.org.settings([
            'global.password_regex',
            'global.juvenile_age_threshold',
            'patron.password.use_phone',
            'ui.patron.default_inet_access_level',
            'ui.patron.default_ident_type',
            'ui.patron.default_country',
            'ui.patron.registration.require_address',
            'circ.holds.behind_desk_pickup_supported',
            'circ.patron_edit.clone.copy_address',
            'circ.privacy_waiver',
            'ui.patron.edit.au.prefix.require',
            'ui.patron.edit.au.prefix.show',
            'ui.patron.edit.au.prefix.suggest',
            'ui.patron.edit.ac.barcode.regex',
            'ui.patron.edit.au.second_given_name.show',
            'ui.patron.edit.au.second_given_name.suggest',
            'ui.patron.edit.au.suffix.show',
            'ui.patron.edit.au.suffix.suggest',
            'ui.patron.edit.au.alias.show',
            'ui.patron.edit.au.alias.suggest',
            'ui.patron.edit.au.dob.require',
            'ui.patron.edit.au.dob.show',
            'ui.patron.edit.au.dob.suggest',
            'ui.patron.edit.au.dob.calendar',
            'ui.patron.edit.au.dob.example',
            'ui.patron.edit.au.juvenile.show',
            'ui.patron.edit.au.juvenile.suggest',
            'ui.patron.edit.au.ident_value.show',
            'ui.patron.edit.au.ident_value.require',
            'ui.patron.edit.au.ident_value.suggest',
            'ui.patron.edit.au.ident_value2.show',
            'ui.patron.edit.au.ident_value2.suggest',
            'ui.patron.edit.au.photo_url.require',
            'ui.patron.edit.au.photo_url.show',
            'ui.patron.edit.au.photo_url.suggest',
            'ui.patron.edit.au.email.require',
            'ui.patron.edit.au.email.show',
            'ui.patron.edit.au.email.suggest',
            'ui.patron.edit.au.email.regex',
            'ui.patron.edit.au.email.example',
            'ui.patron.edit.au.day_phone.require',
            'ui.patron.edit.au.day_phone.show',
            'ui.patron.edit.au.day_phone.suggest',
            'ui.patron.edit.au.day_phone.regex',
            'ui.patron.edit.au.day_phone.example',
            'ui.patron.edit.au.evening_phone.require',
            'ui.patron.edit.au.evening_phone.show',
            'ui.patron.edit.au.evening_phone.suggest',
            'ui.patron.edit.au.evening_phone.regex',
            'ui.patron.edit.au.evening_phone.example',
            'ui.patron.edit.au.other_phone.require',
            'ui.patron.edit.au.other_phone.show',
            'ui.patron.edit.au.other_phone.suggest',
            'ui.patron.edit.au.other_phone.regex',
            'ui.patron.edit.au.other_phone.example',
            'ui.patron.edit.aus.default_phone.regex',
            'ui.patron.edit.aus.default_phone.example',
            'ui.patron.edit.aus.default_sms_notify.regex',
            'ui.patron.edit.aus.default_sms_notify.example',
            'ui.patron.edit.phone.regex',
            'ui.patron.edit.phone.example',
            'ui.patron.edit.au.active.show',
            'ui.patron.edit.au.active.suggest',
            'ui.patron.edit.au.barred.show',
            'ui.patron.edit.au.barred.suggest',
            'ui.patron.edit.au.master_account.show',
            'ui.patron.edit.au.master_account.suggest',
            'ui.patron.edit.au.claims_returned_count.show',
            'ui.patron.edit.au.claims_returned_count.suggest',
            'ui.patron.edit.au.claims_never_checked_out_count.show',
            'ui.patron.edit.au.claims_never_checked_out_count.suggest',
            'ui.patron.edit.aua.post_code.regex',
            'ui.patron.edit.aua.post_code.example',
            'ui.patron.edit.aua.county.require',
            'ui.patron.edit.au.guardian.show',
            'ui.patron.edit.au.guardian.suggest',
            'ui.patron.edit.guardian_required_for_juv',
            'webstaff.format.dates',
            'ui.patron.edit.default_suggested',
            'opac.barcode_regex',
            'opac.username_regex',
            'sms.enable',
            'ui.patron.edit.aua.state.require',
            'ui.patron.edit.aua.state.suggest',
            'ui.patron.edit.aua.state.show',
            'ui.admin.work_log.max_entries',
            'ui.admin.patron_log.max_entries'
        ]).then(function(settings) {
            service.org_settings = settings;
            if (egCore && egCore.env && !egCore.env.aous) {
                egCore.env.aous = settings;
                console.log('setting egCore.env.aous');
            }
            return service.process_org_settings(settings);
        });
    };

    // some org settings require the retrieval of additional data
    service.process_org_settings = function(settings) {

        var promises = [egLovefield.setSettingsCache(settings)];

        if (settings['sms.enable']) {
            // fetch SMS carriers
            promises.push(
                egCore.pcrud.search('csc', 
                    {active: 'true'}, 
                    {'order_by':[
                        {'class':'csc', 'field':'name'},
                        {'class':'csc', 'field':'region'}
                    ]}, {atomic : true}
                ).then(function(carriers) {
                    service.sms_carriers = carriers;
                })
            );
        } else {
            // if other promises are added below, this is not necessary.
            promises.push($q.when());  
        }

        // other post-org-settings processing goes here,
        // adding to promises as needed.

        return $q.all(promises);
    };

    service.get_ident_types = function() {
        if (egCore.env.cit) {
            service.ident_types = egCore.env.cit.list;
            return $q.when();
        } else {
            return egCore.pcrud.retrieveAll('cit', {}, {atomic : true})
            .then(function(types) { 
                egCore.env.absorbList(types, 'cit')
                service.ident_types = types 
            });
        }
    };

    service.get_locales = function() {
        if (egCore.env.i18n_l) {
            service.locales = egCore.env.i18n_l.list;
            return $q.when();
        } else {
            return egCore.pcrud.retrieveAll('i18n_l', {}, {atomic : true})
            .then(function(locales) {
                egCore.env.absorbList(locales, 'i18n_l')
                service.locales = locales
	    });
        }
    };

    service.get_net_access_levels = function() {
        if (egCore.env.cnal) {
            service.net_access_levels = egCore.env.cnal.list;
            return $q.when();
        } else {
            return egCore.pcrud.retrieveAll('cnal', {}, {atomic : true})
            .then(function(levels) { 
                egCore.env.absorbList(levels, 'cnal')
                service.net_access_levels = levels 
            });
        }
    }

    service.get_perm_groups = function() {
        if (egCore.env.pgt) {
            service.profiles = egCore.env.pgt.list;
            return service.set_edit_profiles();
        } else {
            return egCore.pcrud.search('pgt', {parent : null}, 
                {flesh : -1, flesh_fields : {pgt : ['children']}}
            ).then(
                function(tree) {
                    egCore.env.absorbTree(tree, 'pgt')
                    service.profiles = egCore.env.pgt.list;
                    return service.set_edit_profiles();
                }
            );
        }
    }

    service.searchPermGroupEntries = function(org) {
        return egCore.pcrud.search('pgtde', {org: org, parent: null},
            {flesh: -1, flesh_fields: {pgtde: ['grp', 'children']}, 'order_by':{'pgtde':'position desc'}}, {atomic: true}
        ).then(function(treeArray) {
            if (!treeArray.length && egCore.org.get(org).parent_ou()) {
                return service.searchPermGroupEntries(egCore.org.get(org).parent_ou());
            }
            return treeArray;
        });
    }

    service.get_perm_group_entries = function() {
        if (egCore.env.pgtde) {
            service.profile_entries = egCore.env.pgtde.list;
            return service.set_edit_profile_entries();
        } else {
            return service.searchPermGroupEntries(egCore.auth.user().ws_ou()).then(function(treeArray) {
                function compare(a,b) {
                  if (a.position() > b.position())
                    return -1;
                  if (a.position() < b.position())
                    return 1;
                  return 0;
                }

                var list = [];
                function squash(node) {
                    node.children().sort(compare);
                    list.push(node);
                    angular.forEach(node.children(), squash);
                }

                angular.forEach(treeArray, squash);
                var blob = egCore.env.absorbList(list, 'pgtde');
                blob.tree = treeArray;

                service.profile_entries = egCore.env.pgtde.list;
                return service.set_edit_profile_entries();
            });
        }
    }

    service.get_field_doc = function() {
        var to_cache = [];
        return egCore.pcrud.search('fdoc', {
            fm_class: ['au', 'ac', 'aua', 'actsc', 'asv', 'asvq', 'asva']})
        .then(
            function () {
                return egLovefield.setListInOfflineCache('fdoc', to_cache)
            },
            null,
            function(doc) {
                if (!service.field_doc[doc.fm_class()]) {
                    service.field_doc[doc.fm_class()] = {};
                }
                service.field_doc[doc.fm_class()][doc.field()] = doc;
                to_cache.push(doc);
            }
        );

    };

    service.get_user_setting_types = function() {

        // No need to re-fetch the common setting types.
        if (Object.keys(service.user_setting_types).length) 
            return $q.when();

        var org_ids = egCore.org.ancestors(egCore.auth.user().ws_ou(), true);

        var static_types = [
            'circ.holds_behind_desk', 
            'circ.collections.exempt', 
            'opac.hold_notify', 
            'opac.default_phone', 
            'opac.default_pickup_location', 
            'opac.default_sms_carrier', 
            'opac.default_sms_notify'];

        return egCore.pcrud.search('cust', {
            '-or' : [
                {name : static_types}, // common user settings
                {name : { // opt-in notification user settings
                    'in': {
                        select : {atevdef : ['opt_in_setting']}, 
                        from : 'atevdef',
                        // we only care about opt-in settings for 
                        // event_defs our users encounter
                        where : {'+atevdef' : {owner : org_ids}}
                    }
                }}
            ]
        }, {}, {atomic : true}).then(function(setting_types) {

            egCore.env.absorbList(setting_types, 'cust'); // why not...

            angular.forEach(setting_types, function(stype) {
                service.user_setting_types[stype.name()] = stype;
                if (static_types.indexOf(stype.name()) == -1) {
                    service.opt_in_setting_types[stype.name()] = stype;
                }
            });
        });
    };

    service.get_user_settings = function() {

        return service.get_user_setting_types()
        .then(function() {

            var setting_types = Object.values(service.user_setting_types);

            if (service.patron_id) {
                // retrieve applied values for the current user 
                // for the setting types we care about.

                var setting_names = 
                    setting_types.map(function(obj) { return obj.name() });

                return egCore.net.request(
                    'open-ils.actor', 
                    'open-ils.actor.patron.settings.retrieve.authoritative',
                    egCore.auth.token(),
                    service.patron_id,
                    setting_names
                ).then(function(settings) {
                    service.user_settings = settings;
                });

            } else {

                // apply default user setting values
                angular.forEach(setting_types, function(stype, index) {
                    if (stype.reg_default() != undefined) {
                        var val = stype.reg_default();
                        if (stype.datatype() == 'bool') {
                            // A boolean user setting type whose default 
                            // value starts with t/T is considered 'true',
                            // false otherwise.
                            val = Boolean((val+'').match(/^t/i));
                        }
                        service.user_settings[stype.name()] = val;
                    }
                });
            }
        });
    }

    service.invalidate_field = function(patron, field) {
        console.log('Invalidating patron field ' + field);

        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.invalidate.' + field,
            egCore.auth.token(), patron.id, null, patron.home_ou.id()

        ).then(function(res) {
            // clear the invalid value from the form
            patron[field] = '';

            // update last_xact_id so future save operations
            // on this patron will be allowed
            patron.last_xact_id = res.payload.last_xact_id[patron.id];
        });
    }

    service.send_test_message = function(user_id, hook) {

        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.event.test_notification',
            egCore.auth.token(), {hook: hook, target: user_id}
        ).then(function(res) {
            return res;
        });
    }

    service.dupe_patron_search = function(patron, type, value) {
        var search;

        console.log('Dupe search called with "'+ type +'" and value '+ value);

        if (type.match(/phone/)) type = 'phone'; // day_phone, etc.

        switch (type) {

            case 'name':
                var fname = patron.first_given_name;   
                var lname = patron.family_name;   
                if (!(fname && lname)) return $q.when({count:0});
                search = {
                    first_given_name : {value : fname, group : 0},
                    family_name : {value : lname, group : 0}
                };
                break;

            case 'email':
                search = {email : {value : value, group : 0}};
                break;

            case 'ident':
                search = {ident : {value : value, group : 2}};
                break;

            case 'phone':
                search = {phone : {value : value, group : 2}};
                break;

            case 'address':
                search = {};
                angular.forEach(['street1', 'street2', 'city', 'post_code'],
                    function(field) {
                        if(value[field])
                            search[field] = {value : value[field], group: 1};
                    }
                );
                break;
        }

        return egCore.net.request( 
            'open-ils.actor', 
            'open-ils.actor.patron.search.advanced',
            egCore.auth.token(), search, null, null, 1
        ).then(function(res) {
            res = res.filter(function(id) {return id != patron.id});
            return {
                count : res.length,
                search : search
            };
        });
    }

    service.init_patron = function(current) {

        if (!current)
            return $q.when(service.init_new_patron());

        service.patron = current;
        return $q.when(service.init_existing_patron(current));
    }

    service.ingest_address = function(patron, addr) {
        addr.valid = addr.valid == 't';
        addr.within_city_limits = addr.within_city_limits == 't';
        addr._is_mailing = (patron.mailing_address && 
            addr.id == patron.mailing_address.id);
        addr._is_billing = (patron.billing_address && 
            addr.id == patron.billing_address.id);
        addr.pending = addr.pending === 't';
    }

    service.ingest_waiver_entry = function(patron, waiver_entry) {
        waiver_entry.place_holds = waiver_entry.place_holds == 't';
        waiver_entry.pickup_holds = waiver_entry.pickup_holds == 't';
        waiver_entry.view_history = waiver_entry.view_history == 't';
        waiver_entry.checkout_items = waiver_entry.checkout_items == 't';
    }

    /*
     * Existing patron objects reqire some data munging before insertion
     * into the scope.
     *
     * 1. Turn everything into a hash
     * 2. ... Except certain fields (selectors) whose widgets require objects
     * 3. Bools must be Boolean, not t/f.
     */
    service.init_existing_patron = function(current) {

        service.existing_patron = current;

        var patron = egCore.idl.toHash(current);
        patron.home_ou = egCore.org.get(patron.home_ou.id);
        patron.expire_date = new Date(Date.parse(patron.expire_date));
        patron.dob = service.parse_dob(patron.dob);
        patron.profile = current.profile(); // pre-hash version
        patron.net_access_level = current.net_access_level();
        patron.ident_type = current.ident_type();
        patron.ident_type2 = current.ident_type2();
        patron.locale = current.locale();
        patron.groups = current.groups(); // pre-hash

        angular.forEach(
            ['juvenile', 'barred', 'active', 'master_account'],
            function(field) { patron[field] = patron[field] == 't'; }
        );

        angular.forEach(patron.cards, function(card) {
            card.active = card.active == 't';
            if (card.id == patron.card.id) {
                patron.card = card;
                card._primary = true;
            }
        });

        angular.forEach(patron.addresses, 
            function(addr) { service.ingest_address(patron, addr) });

        // Link replaced address to its pending address.
        angular.forEach(patron.addresses, function(addr) {
            if (addr.replaces) {
                addr._replaces = patron.addresses.filter(
                    function(a) {return a.id == addr.replaces})[0];
            }
        });

        angular.forEach(patron.waiver_entries,
            function(waiver_entry) { service.ingest_waiver_entry(patron, waiver_entry) });

        service.get_linked_addr_users(patron.addresses);

        // Remove stat cat entries that link to out-of-scope stat
        // cats.  With this, we avoid unnecessarily updating (or worse,
        // modifying) stat cat values that are not ours to modify.
        patron.stat_cat_entries = patron.stat_cat_entries.filter(
            function(map) {
                return Boolean(
                    // service.stat_cats only contains in-scope stat cats.
                    service.stat_cats.filter(function(cat) { 
                        return (cat.id() == map.stat_cat.id) })[0]
                );
            }
        );

        // toss entries for existing stat cat maps into our living 
        // stat cat entry map, which is modified within the template.
        service.stat_cat_entry_maps = [];
        angular.forEach(patron.stat_cat_entries, function(map) {
            service.stat_cat_entry_maps[map.stat_cat.id] = map.stat_cat_entry;
        });

        // fetch survey responses for this user
        var org_ids = egCore.org.fullPath(egCore.auth.user().ws_ou(), true);
        var svr_responses = {};
        patron.surveys = [];

        egCore.pcrud.search('asvr',
            {usr : patron.id},
            {flesh : 2, flesh_fields : {asvr : ['survey','question','answer']}}
        ).then(
            function() {
                // All responses collected and deduplicated.
                // Create one collection of responses per survey.
                angular.forEach(svr_responses, function(questions, survey_id) {
                    var collection = {responses : []};
                    angular.forEach(questions, function(response) {
                        collection.survey = response.survey();
                        collection.responses.push(response);
                    });
                    patron.surveys.push(collection);
                });
            },
            null,
            function(response) {
                // Discard responses for out-of-scope surveys.
                if (org_ids.indexOf(response.survey().owner()) < 0)
                    return;

                // survey_id => question_id => response
                var svr_id = response.survey().id();
                var qst_id = response.question().id();

                if (!svr_responses[svr_id])
                    svr_responses[svr_id] = [];

                if (!svr_responses[svr_id][qst_id]) {
                    svr_responses[svr_id][qst_id] = response;
                } else {
                    // We may have multiple responses for the same question.
                    // For this UI we only care about the most recent response.
                    if (response.effective_date() >
                        svr_responses[svr_id][qst_id].effective_date())
                        svr_responses[svr_id][qst_id] = response;
                }
            }
        );

        service.patron = patron;
        return patron;
    }

    service.init_new_patron = function() {
        var addr = {
            id : service.virt_id--,
            isnew : true,
            valid : true,
            address_type : egCore.strings.REG_ADDR_TYPE,
            _is_mailing : true,
            _is_billing : true,
            within_city_limits : false,
            country : service.org_settings['ui.patron.default_country'],
        };

        var card = {
            id : service.virt_id--,
            isnew : true,
            active : true,
            _primary : true
        };

        var user = {
            isnew : true,
            active : true,
            card : card,
            cards : [card],
            home_ou : egCore.org.get(egCore.auth.user().ws_ou()),
            net_access_level : service.org_settings['ui.patron.default_inet_access_level'],
            stat_cat_entries : [],
            waiver_entries : [],
            groups : [],
            addresses : [addr]
        };

        if (service.clone_user)
            service.copy_clone_data(user);

        if (service.stage_user)
            service.copy_stage_data(user);

        return user;
    }

    // dob is always YYYY-MM-DD
    // Dates of birth do not contain timezone info, which can lead to
    // inconcistent timezone handling, potentially representing
    // different points in time, depending on the implementation.
    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/parse
    // See "Differences in assumed time zone"
    // TODO: move this into egDate ?
    service.parse_dob = function(dob) {
        if (!dob) return null;
        var parts = dob.split('-');
        return new Date(parts[0], parts[1] - 1, parts[2])
    }

    service.copy_stage_data = function(user) {
        var cuser = service.stage_user;

        // copy the data into our new user object

        for (var key in egCore.idl.classes.stgu.field_map) {
            if (egCore.idl.classes.au.field_map[key] &&
                !egCore.idl.classes.stgu.field_map[key].virtual) {
                if (cuser.user[key]() !== null)
                    user[key] = cuser.user[key]();
            }
        }

        if (user.home_ou) user.home_ou = egCore.org.get(user.home_ou);
        if (user.profile) user.profile = egCore.env.pgt.map[user.profile];
        if (user.ident_type) 
            user.ident_type = egCore.env.cit.map[user.ident_type];
        if (user.ident_type2)
            user.ident_type2 = egCore.env.cit.map[user.ident_type2];
	if (user.locale) 
	    user.locale = egCore.env.i18n_l.map[user.locale];
        user.dob = service.parse_dob(user.dob);

        // Clear the usrname if it looks like a UUID
        if (user.usrname.replace(/-/g,'').match(/[0-9a-f]{32}/)) 
            user.usrname = '';

        // Don't use stub address if we have one from the staged user.
        if (cuser.mailing_addresses.length || cuser.billing_addresses.length)
            user.addresses = [];

        // is_mailing=false implies is_billing
        function addr_from_stage(stage_addr) {
            if (!stage_addr) return;
            var cls = stage_addr.classname;

            var addr = {
                id : service.virt_id--,
                usr : user.id,
                isnew : true,
                valid : true,
                address_type : egCore.strings.REG_ADDR_TYPE,
                _is_mailing : cls == 'stgma',
                _is_billing : cls == 'stgba'
            };

            user.mailing_address = addr;
            user.addresses.push(addr);

            for (var key in egCore.idl.classes[cls].field_map) {
                if (egCore.idl.classes.aua.field_map[key] &&
                    !egCore.idl.classes[cls].field_map[key].virtual) {
                    if (stage_addr[key]() !== null)
                        addr[key] = stage_addr[key]();
                }
            }
        }

        addr_from_stage(cuser.mailing_addresses[0]);
        addr_from_stage(cuser.billing_addresses[0]);

        if (user.addresses.length == 1) {
            // If there is only one address, 
            // use it as both mailing and billing.
            var addr = user.addresses[0];
            addr._is_mailing = addr._is_billing = true;
            user.mailing_address = user.billing_address = addr;
        }

        if (cuser.cards.length) {
            user.card = {
                id : service.virt_id--,
                barcode : cuser.cards[0].barcode(),
                isnew : true,
                active : true,
                _primary : true
            };

            user.cards.push(user.card);
            if (user.usrname == '') 
                user.usrname = card.barcode;
        }

        angular.forEach(cuser.settings, function(setting) {
            service.user_settings[setting.setting()] = Boolean(setting.value());
        });
    }

    // copy select values from the cloned user to the new user.
    // user is a hash
    service.copy_clone_data = function(user) {
        var clone_user = service.clone_user;

        // flesh the home org locally
        user.home_ou = egCore.org.get(clone_user.home_ou());
        if (user.profile) user.profile = egCore.env.pgt.map[user.profile];

        if (!clone_user.billing_address() &&
            !clone_user.mailing_address())
            return; // no addresses to copy or link

        // if the cloned user has any addresses, we don't need 
        // the stub address created in init_new_patron.
        user.addresses = [];

        var copy_addresses = 
            service.org_settings['circ.patron_edit.clone.copy_address'];

        var clone_fields = [
            'day_phone',
            'evening_phone',
            'other_phone',
            'usrgroup'
        ]; 

        angular.forEach(clone_fields, function(field) {
            user[field] = clone_user[field]();
        });

        if (copy_addresses) {
            var bill_addr, mail_addr;

            // copy the billing and mailing addresses into new addresses
            function clone_addr(addr) {
                var new_addr = egCore.idl.toHash(addr);
                new_addr.id = service.virt_id--;
                new_addr.usr = user.id;
                new_addr.isnew = true;
                new_addr.valid = true;
                new_addr.pending = new_addr.pending === 't';
                new_addr.within_city_limits = new_addr.within_city_limits == 't';
                user.addresses.push(new_addr);
                return new_addr;
            }

            if (bill_addr = clone_user.billing_address()) {
                var addr = clone_addr(bill_addr);
                addr._is_billing = true;
                user.billing_address = addr;
            }

            if (mail_addr = clone_user.mailing_address()) {

                if (bill_addr && bill_addr.id() == mail_addr.id()) {
                    user.mailing_address = user.billing_address;
                    user.mailing_address._is_mailing = true;
                } else {
                    var addr = clone_addr(mail_addr);
                    addr._is_mailing = true;
                    user.mailing_address = addr;
                }

                if (!bill_addr) {
                    // if there is no billing addr, use the mailing addr
                    user.billing_address = user.mailing_address;
                    user.billing_address._is_billing = true;
                }
            }


        } else {

            // link the billing and mailing addresses
            var addr;
            if (addr = clone_user.billing_address()) {
                user.billing_address = egCore.idl.toHash(addr);
                user.billing_address._is_billing = true;
                user.addresses.push(user.billing_address);
                user.billing_address._linked_owner_id = clone_user.id();
                user.billing_address._linked_owner = service.format_name(
                    clone_user.family_name(),
                    clone_user.first_given_name(),
                    clone_user.second_given_name()
                );
            }

            if (addr = clone_user.mailing_address()) {
                if (user.billing_address && 
                    addr.id() == user.billing_address.id) {
                    // mailing matches billing
                    user.mailing_address = user.billing_address;
                    user.mailing_address._is_mailing = true;
                } else {
                    user.mailing_address = egCore.idl.toHash(addr);
                    user.mailing_address._is_mailing = true;
                    user.addresses.push(user.mailing_address);
                    user.mailing_address._linked_owner_id = clone_user.id();
                    user.mailing_address._linked_owner = service.format_name(
                        clone_user.family_name(),
                        clone_user.first_given_name(),
                        clone_user.second_given_name()
                    );
                }
            }
        }
    }

    // translate the patron back into IDL form
    service.save_user = function(phash) {

        var patron = egCore.idl.fromHash('au', phash);

        patron.home_ou(patron.home_ou().id());
        patron.expire_date(patron.expire_date().toISOString());
        patron.profile(patron.profile().id());
        if (patron.dob()) 
            patron.dob(moment(patron.dob()).format('YYYY-MM-DD'));
        if (patron.ident_type()) 
            patron.ident_type(patron.ident_type().id());
        if (patron.locale())
            patron.locale(patron.locale().code());
        if (patron.net_access_level())
            patron.net_access_level(patron.net_access_level().id());

        angular.forEach(
            ['juvenile', 'barred', 'active', 'master_account'],
            function(field) { patron[field](phash[field] ? 't' : 'f'); }
        );

        var card_hashes = patron.cards();
        patron.cards([]);
        angular.forEach(card_hashes, function(chash) {
            var card = egCore.idl.fromHash('ac', chash)
            card.usr(patron.id());
            card.active(chash.active ? 't' : 'f');
            patron.cards().push(card);
            if (chash._primary) {
                patron.card(card);
            }
        });

        var addr_hashes = patron.addresses();
        patron.addresses([]);
        angular.forEach(addr_hashes, function(addr_hash) {
            if (!addr_hash.isnew && !addr_hash.isdeleted) 
                addr_hash.ischanged = true;
            var addr = egCore.idl.fromHash('aua', addr_hash);
            patron.addresses().push(addr);
            addr.valid(addr.valid() ? 't' : 'f');
            addr.within_city_limits(addr.within_city_limits() ? 't' : 'f');
            addr.pending(addr.pending() ? 't' : 'f');
            if (addr_hash._is_mailing) patron.mailing_address(addr);
            if (addr_hash._is_billing) patron.billing_address(addr);
        });

        patron.survey_responses([]);
        angular.forEach(service.survey_responses, function(answer) {
            var question = service.survey_questions[answer.question()];
            var resp = new egCore.idl.asvr();
            resp.isnew(true);
            resp.survey(question.survey());
            resp.question(question.id());
            resp.answer(answer.id());
            resp.usr(patron.id());
            resp.answer_date('now');
            patron.survey_responses().push(resp);
        });
        
        // re-object-ify the patron stat cat entry maps
        var maps = [];
        angular.forEach(patron.stat_cat_entries(), function(entry) {
            var e = egCore.idl.fromHash('actscecm', entry);
            e.stat_cat(e.stat_cat().id);
            maps.push(e);
        });
        patron.stat_cat_entries(maps);

        // service.stat_cat_entry_maps maps stats to values
        // patron.stat_cat_entries is an array of stat_cat_entry_usr_map's
        angular.forEach(
            service.stat_cat_entry_maps, function(value, cat_id) {

            // see if we already have a mapping for this entry
            var existing = patron.stat_cat_entries().filter(
                function(e) { return e.stat_cat() == cat_id })[0];

            if (existing) { // we have a mapping
                // if the existing mapping matches the new one,
                // there' nothing left to do
                if (existing.stat_cat_entry() == value) return;

                // mappings differ.  delete the old one and create
                // a new one below.
                existing.isdeleted(true);
            }

            var newmap = new egCore.idl.actscecm();
            newmap.target_usr(patron.id());
            newmap.isnew(true);
            newmap.stat_cat(cat_id);
            newmap.stat_cat_entry(value);
            patron.stat_cat_entries().push(newmap);
        });

        var waiver_hashes = patron.waiver_entries();
        patron.waiver_entries([]);
        angular.forEach(waiver_hashes, function(waiver_hash) {
            if (!waiver_hash.isnew && !waiver_hash.isdeleted)
                waiver_hash.ischanged = true;
            var waiver_entry = egCore.idl.fromHash('aupw', waiver_hash);
            patron.waiver_entries().push(waiver_entry);
        });

        if (!patron.isnew()) patron.ischanged(true);

        // Make sure these are empty, we don't update them this way
        patron.notes([]);
        patron.usr_activity([]);
        patron.standing_penalties([]);

        return egCore.net.request(
            'open-ils.actor', 
            'open-ils.actor.patron.update',
            egCore.auth.token(), patron);
    }

    service.remove_staged_user = function() {
        if (!service.stage_user) return $q.when();
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.stage.delete',
            egCore.auth.token(),
            service.stage_user.user.row_id()
        );
    }

    service.save_user_settings = function(new_user, user_settings) {

        var settings = {};
        if (service.patron_id) {
            // Update all user editor setting values for existing 
            // users regardless of whether a value changed.
            settings = user_settings;

        } else {
            // Create settings for all non-null setting values for new patrons.
            angular.forEach(user_settings, function(val, key) {
                if (val !== null) settings[key] = val;
            });
        }

        if (Object.keys(settings).length == 0) return $q.when();

        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.settings.update',
            egCore.auth.token(), new_user.id(), settings
        ).then(function(resp) {
            return resp;
        });
    }

    // Applies field-specific validation regex's from org settings 
    // to form fields.  Be careful not remove any pattern data we
    // are not explicitly over-writing in the provided patterns obj.
    service.set_field_patterns = function(patterns) {
        if (service.org_settings['opac.username_regex']) {
            patterns.au.usrname = 
                new RegExp(service.org_settings['opac.username_regex']);
        }

        if (service.org_settings['ui.patron.edit.ac.barcode.regex']) {
            patterns.ac.barcode = 
                new RegExp(service.org_settings['ui.patron.edit.ac.barcode.regex']);
        }

        if (service.org_settings['global.password_regex']) {
            patterns.au.passwd = 
                new RegExp(service.org_settings['global.password_regex']);
        }

        var phone_reg = service.org_settings['ui.patron.edit.phone.regex'];
        if (phone_reg) {
            // apply generic phone regex first, replace below as needed.
            patterns.au.day_phone = new RegExp(phone_reg);
            patterns.au.evening_phone = new RegExp(phone_reg);
            patterns.au.other_phone = new RegExp(phone_reg);
        }

        // the remaining patterns fit a well-known key name pattern

        angular.forEach(service.org_settings, function(val, key) {
            if (!val) return;
            var parts = key.match(/ui.patron.edit\.(\w+)\.(\w+)\.regex/);
            if (!parts) return;
            var cls = parts[1];
            var name = parts[2];
            patterns[cls][name] = new RegExp(val);
        });
    }

    return service;
}])

.controller('PatronRegCtrl',
       ['$scope','$routeParams','$q','$uibModal','$window','egCore',
        'patronSvc','patronRegSvc','egUnloadPrompt','egAlertDialog',
        'egWorkLog', '$timeout', 'ngToast',
function($scope , $routeParams , $q , $uibModal , $window , egCore ,
         patronSvc , patronRegSvc , egUnloadPrompt, egAlertDialog ,
         egWorkLog, $timeout, ngToast) {

    $scope.page_data_loaded = false;
    $scope.hold_notify_type = { phone : null, email : null, sms : null };
    $scope.hold_notify_observer = {};
    $scope.hold_rel_contacts = {};
    $scope.clone_id = patronRegSvc.clone_id = $routeParams.clone_id;
    $scope.stage_username = 
        patronRegSvc.stage_username = $routeParams.stage_username;
    $scope.patron_id = 
        patronRegSvc.patron_id = $routeParams.edit_id || $routeParams.id;

    // for existing patrons, disable barcode input by default
    $scope.disable_bc = $scope.focus_usrname = Boolean($scope.patron_id);
    $scope.focus_bc = !Boolean($scope.patron_id);
    $scope.address_alerts = [];
    $scope.dupe_counts = {};

    // map of perm name to true/false for perms the logged in user
    // has at the currently selected patron home org unit.
    $scope.perms = {};

    $scope.name_tab = 'primary';

    if (!$scope.edit_passthru) {
        // in edit more, scope.edit_passthru is delivered to us by
        // the enclosing controller.  In register mode, there is 
        // no enclosing controller, so we create our own.
        $scope.edit_passthru = {};
    }

    // 0=all, 1=suggested, 2=all
    $scope.edit_passthru.vis_level = 0; 

    // Apply default values for new patrons during initial registration
    // prs is shorthand for patronSvc
    function set_new_patron_defaults(prs) {
        if (!$scope.patron.passwd) {
            // passsword may originate from staged user.
            if ($scope.patron.day_phone &&
                $scope.org_settings['patron.password.use_phone']) {
                $scope.patron.passwd = $scope.patron.day_phone.substr(-4);
            } else {
                $scope.generate_password();
            }
        }

        var notify = 'phone:email'; // hard-coded default when opac.hold_notify has no reg_default
        var notify_stype = $scope.user_setting_types['opac.hold_notify'];
        if (notify_stype && notify_stype.reg_default() !== undefined && notify_stype.reg_default() !== null) {
            console.log('using default opac.hold_notify');
            notify = notify_stype.reg_default();
        }
        $scope.hold_notify_type.phone = Boolean(notify.match(/phone/));
        $scope.hold_notify_type.email = Boolean(notify.match(/email/));
        $scope.hold_notify_type.sms = Boolean(notify.match(/sms/));

        // staged users may be loaded w/ a profile.
        $scope.set_expire_date();

        if (prs.org_settings['ui.patron.default_ident_type']) {
            // $scope.patron needs this field to be an object
            var id = prs.org_settings['ui.patron.default_ident_type'];
            var ident_type = $scope.ident_types.filter(
                function(type) { return type.id() == id })[0];
            $scope.patron.ident_type = ident_type;
        }
        if (prs.org_settings['ui.patron.default_inet_access_level']) {
            // $scope.patron needs this field to be an object
            var id = prs.org_settings['ui.patron.default_inet_access_level'];
            var level = $scope.net_access_levels.filter(
                function(lvl) { return lvl.id() == id })[0];
            $scope.patron.net_access_level = level;
        }
        if (prs.org_settings['ui.patron.default_country']) {
            $scope.patron.addresses[0].country = 
                prs.org_settings['ui.patron.default_country'];
        }
    }

    // A null or undefined pattern leads to exceptions.  Before the
    // patterns are loaded from the server, default all patterns
    // to an innocuous regex.  To avoid re-creating numerous
    // RegExp objects, cache the stub RegExp after initial creation.
    // note: angular docs say ng-pattern accepts a regexp or string,
    // but as of writing, it only works with a regexp object.
    // (Likely an angular 1.2 vs. 1.4 issue).
    var field_patterns = {au : {}, ac : {}, aua : {}, aus: {}};
    $scope.field_pattern = function(cls, field) { 
        if (!field_patterns[cls][field])
            field_patterns[cls][field] = new RegExp('.*');
        return field_patterns[cls][field];
    }

    // Main page load function.  Kicks off tab init and data loading.
    $q.all([

        $scope.initTab ? // initTab comes from patron app
            $scope.initTab('edit', $routeParams.id) : $q.when(),

        patronRegSvc.init(),

    ]).then(function(){ return patronRegSvc.init_patron(patronSvc ? patronSvc.current : patronRegSvc.patron ) })
      .then(function(patron) {
        // called after initTab and patronRegSvc.init have completed
        // in standalone mode, we have no patronSvc
        var prs = patronRegSvc;
        $scope.patron = patron;
        $scope.base_email = patron.email;
        $scope.base_default_sms = prs.user_settings['opac.default_sms_notify']
        $scope.field_doc = prs.field_doc;
        $scope.edit_profiles = prs.edit_profiles;
        $scope.edit_profile_entries = prs.edit_profile_entries;
        $scope.ident_types = prs.ident_types;
        $scope.locales = prs.locales;
        $scope.net_access_levels = prs.net_access_levels;
        $scope.user_setting_types = prs.user_setting_types;
        $scope.opt_in_setting_types = prs.opt_in_setting_types;
        $scope.org_settings = prs.org_settings;
        $scope.sms_carriers = prs.sms_carriers;
        $scope.stat_cats = prs.stat_cats;
        $scope.surveys = prs.surveys;
        $scope.survey_responses = prs.survey_responses;
        $scope.stat_cat_entry_maps = prs.stat_cat_entry_maps;
        $scope.stage_user = prs.stage_user;
        $scope.stage_user_requestor = prs.stage_user_requestor;

        $scope.user_settings = prs.user_settings;
        prs.user_settings = {};

        // If a default pickup lib is applied to the patron, apply it 
        // to the UI at page load time.  Otherwise, leave the value unset.
        if ($scope.user_settings['opac.default_pickup_location']) {
            $scope.patron._pickup_lib = egCore.org.get(
                $scope.user_settings['opac.default_pickup_location']);
        }

        extract_hold_notify();

        if ($scope.patron.isnew)
            set_new_patron_defaults(prs);

        $scope.handle_home_org_changed();

        if ($scope.org_settings['ui.patron.edit.default_suggested'])
            $scope.edit_passthru.vis_level = 1;

        // Stat cats are fetched from open-ils.storage, where 't'==1
        $scope.hasRequiredStatCat = prs.stat_cats.filter(
                function(cat) {return cat.required() == 1} ).length > 0;

        $scope.page_data_loaded = true;

        prs.set_field_patterns(field_patterns);
        apply_username_regex();

        add_date_watchers();

        if ($scope.org_settings['ui.patron.edit.guardian_required_for_juv']) {
            add_juv_watcher();
        }

        // Check for duplicate values in staged users.
        if (prs.stage_user) {
            if (patron.first_given_name) { $scope.dupe_value_changed('name', patron.first_given_name); }
            if (patron.family_name) { $scope.dupe_value_changed('name', patron.familiy_name); }
            if (patron.email) { $scope.dupe_value_changed('email', patron.email); }
            if (patron.day_phone) { $scope.dupe_value_changed('day_phone', patron.day_phone); }
            if (patron.evening_phone) { $scope.dupe_value_changed('evening_phone', patron.evening_phone); }

            patron.addresses.forEach(function (addr) {
                $scope.dupe_value_changed('address', addr);
                address_alert(addr);
            });
            if (patron.usrname) {
                prs.check_dupe_username(patron.usrname).then((result) => $scope.dupe_username = Boolean(result));
            }
        }
    });

    function add_date_watchers() {

        $scope.$watch('patron.dob', function(newVal, oldVal) {
            // Even though this runs after page data load, there
            // are still times when it fires unnecessarily.
            if (newVal === oldVal) return;

            console.debug('dob change: ' + newVal + ' : ' + oldVal);
            maintain_juvenile_flag();
        });

        // No need to watch expire_date
    }

    function add_juv_watcher() {
        $scope.$watch('patron.juvenile', function(newVal, oldVal) {
            if (newVal === oldVal) return;
            if (newVal) {
                field_visibility['au.guardian'] = 3; // required
            } else {
                // Value will be reassessed by show_field()
                delete field_visibility['au.guardian'];
            }
        });
    }
    
    // add watchers for hold notify method prefs
    $scope.$watch('hold_notify_type.phone', function(newVal, oldVal) {
        var notifyOpt = $scope.hold_notify_observer['phone'];
        if (newVal !== null) {
            notifyOpt.newval = newVal;
        }
    });

    $scope.$watch('hold_notify_type.sms', function(newVal, oldVal) {
        var notifyOpt = $scope.hold_notify_observer['sms'];
        if (newVal !== null) {
            notifyOpt.newval = newVal;
        }
    });
    
    $scope.$watch('hold_notify_type.email', function(newVal, oldVal) {
        var notifyOpt = $scope.hold_notify_observer['email'];
        if (newVal !== null) {
            notifyOpt.newval = newVal;
        }
    });

    // update the currently displayed field documentation
    $scope.set_selected_field_doc = function(cls, field) {
        $scope.selected_field_doc = $scope.field_doc[cls][field];
    }

    // returns the tree depth of the selected profile group tree node.
    $scope.pgt_depth = function(grp) {
        var d = 0;
        while (grp = egCore.env.pgt.map[grp.parent()]) d++;
        return d;
    }

    // returns the tree depth of the selected profile group tree node.
    $scope.pgtde_depth = function(entry) {
        var d = 0;
        while (entry = egCore.env.pgtde.map[entry.parent()]) d++;
        return d;
    }

    // IDL fields used for labels in the UI.
    $scope.idl_fields = {
        au  : egCore.idl.classes.au.field_map,
        ac  : egCore.idl.classes.ac.field_map,
        aua : egCore.idl.classes.aua.field_map
    };

    // field visibility cache.  Some fields are universally required.
    // 3 == value universally required
    // 2 == field is visible by default
    // 1 == field is suggested by default
    var field_visibility = {};
    var default_field_visibility = {
        'ac.barcode' : 3,
        'au.usrname' : 3,
        'au.passwd' :  3,
        'au.first_given_name' : 3,
        'au.family_name' : 3,
        'au.pref_first_given_name' : 2,
        'au.pref_family_name' : 2,
        'au.ident_type' : 3,
        'au.ident_type2' : 2,
        'au.photo_url' : 2,
        'au.locale' : 2,
        'au.home_ou' : 3,
        'au.profile' : 3,
        'au.expire_date' : 3,
        'au.net_access_level' : 3,
        'aua.address_type' : 3,
        'aua.post_code' : 3,
        'aua.street1' : 3,
        'aua.street2' : 2,
        'aua.city' : 3,
        'aua.county' : 2,
        'aua.state' : 2,
        'aua.country' : 3,
        'aua.valid' : 2,
        'aua.within_city_limits' : 2,
        'stat_cats' : 1,
        'surveys' : 1,
        'au.name_keywords': 1
    }; 

    // Returns true if the selected field should be visible
    // given the current required/suggested/all setting.
    // The visibility flag applied to each field as a result of calling
    // this function also sets (via the same flag) the requiredness state.
    $scope.show_field = function(field_key) {
        // org settings have not been received yet.
        if (!$scope.org_settings) return false;

        if (field_visibility[field_key] == undefined) {
            // compile and cache the visibility for the selected field

            // The preferred name fields use the primary name field settings
            var org_key = field_key;
            var alt_name = false;
            if (field_key.match(/^au.alt_/)) {
                alt_name = true;
                org_key = field_key.slice(7);
            }

            var req_set = 'ui.patron.edit.' + org_key + '.require';
            var sho_set = 'ui.patron.edit.' + org_key + '.show';
            var sug_set = 'ui.patron.edit.' + org_key + '.suggest';

            if ($scope.org_settings[req_set]) {
                if (alt_name) {
                    // Avoid requiring alt name fields when primary 
                    // name fields are required.
                    field_visibility[field_key] = 2;
                } else {
                    field_visibility[field_key] = 3;
                }

            } else if ($scope.org_settings[sho_set]) {
                field_visibility[field_key] = 2;

            } else if ($scope.org_settings[sug_set]) {
                field_visibility[field_key] = 1;

            } else if ($scope.org_settings[sho_set] === false){
                // hide the field if the 'show' setting is explicitly false (not undefined)
                if (default_field_visibility[field_key] === undefined
                    || default_field_visibility[field_key] < 3) {
                    // Only hide if not a database-required field
                    field_visibility[field_key] = -1;
                }
            }
        }

        if (field_visibility[field_key] == undefined) {
            // No org settings were applied above.  Use the default
            // settings if present or assume the field has no
            // visibility flags applied.
            field_visibility[field_key] = 
                default_field_visibility[field_key] || 0;
        }

        return field_visibility[field_key] >= $scope.edit_passthru.vis_level;
    }

    // See $scope.show_field().
    // A field with visbility level 3 means it's required.
    $scope.field_required = function(cls, field) {

        // Value in the password field is not required
        // for existing patrons.
        if (field == 'passwd' && $scope.patron && !$scope.patron.isnew) 
          return false;

        return (field_visibility[cls + '.' + field] == 3);
    }

    // generates a random 4-digit password
    $scope.generate_password = function() {
        $scope.patron.passwd = Math.floor(Math.random()*9000) + 1000;
    }

    $scope.send_password_reset_link = function() {
       if (!$scope.patron.email || $scope.patron.email == '') {
            egAlertDialog.open(egCore.strings.REG_PASSWORD_RESET_REQUEST_NO_EMAIL);
            return;
        } else if (patronRegSvc.check_email_different($scope.patron.email)) {
            egAlertDialog.open(egCore.strings.REG_PASSWORD_RESET_REQUEST_DIFFERENT_EMAIL);
            return;
        }
        // we have an email address, fire the reset request
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.password_reset.request',
            'barcode', $scope.patron.card.barcode, $scope.patron.email
        ).then(function(resp) {
            if (resp == '1') { // request okay
                ngToast.success(egCore.strings.REG_PASSWORD_RESET_REQUEST_SUCCESSFUL);
            } else {
                var evt = egCore.evt.parse(resp);
                egAlertDialog.open(evt.desc);
            }
        });
    }

    $scope.set_expire_date = function() {
        if (!$scope.patron.profile) return;
        var seconds = egCore.date.intervalToSeconds(
            $scope.patron.profile.perm_interval());
        var now_epoch = new Date().getTime();
        $scope.patron.expire_date = new Date(
            now_epoch + (seconds * 1000 /* milliseconds */))
        $scope.field_modified();
    }

    // grp is the pgt object
    $scope.set_profile = function(grp) {
        // If we can't save because of group perms or create/update perms
        if ($scope.edit_passthru.hide_save_actions()) return;
        $scope.patron.profile = grp;
        $scope.set_expire_date();
        $scope.field_modified();
    }

    $scope.invalid_profile = function() {
        return !(
            $scope.patron && 
            $scope.patron.profile && 
            $scope.patron.profile.usergroup() == 't'
        );
    }

    $scope.new_address = function() {
        var addr = egCore.idl.toHash(new egCore.idl.aua());
        patronRegSvc.ingest_address($scope.patron, addr);
        addr.id = patronRegSvc.virt_id--;
        addr.isnew = true;
        addr.valid = true;
        addr.within_city_limits = true;
        addr.country = $scope.org_settings['ui.patron.default_country'];
        $scope.patron.addresses.push(addr);
    }

    // keep deleted addresses out of the patron object so
    // they won't appear in the UI.  They'll be re-inserted
    // when the patron is updated.
    deleted_addresses = [];
    $scope.delete_address = function(id) {

        if ($scope.patron.isnew &&
            $scope.patron.addresses.length == 1 &&
            $scope.org_settings['ui.patron.registration.require_address']) {
            egAlertDialog.open(egCore.strings.REG_ADDR_REQUIRED);
            return;
        }

        var addresses = [];
        angular.forEach($scope.patron.addresses, function(addr) {
            if (addr.id == id) {
                if (id > 0) {
                    addr.isdeleted = true;
                    deleted_addresses.push(addr);
                }
            } else {
                addresses.push(addr);
            }
        });
        $scope.patron.addresses = addresses;
    } 

    $scope.approve_pending_address = function(addr) {

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.pending_address.approve',
            egCore.auth.token(), addr.id
        ).then(function(replaced_id) {
            var evt = egCore.evt.parse(replaced_id);
            if (evt) { alert(evt); return; }

            // Remove the pending address and the replaced address
            // from the local list of patron addresses.
            var addresses = [];
            angular.forEach($scope.patron.addresses, function(a) {
                if (a.id != addr.id && a.id != replaced_id) {
                    addresses.push(a);
                }
            });
            $scope.patron.addresses = addresses;

            // Fetch a fresh copy of the modified address from the server.
            // and add it back to the list.
            egCore.pcrud.retrieve('aua', replaced_id, {}, {authoritative: true})
            .then(null, null, function(new_addr) {
                new_addr = egCore.idl.toHash(new_addr);
                patronRegSvc.ingest_address($scope.patron, new_addr);
                $scope.patron.addresses.push(new_addr);
            });
        });
    }

    $scope.post_code_changed = function(addr) { 
        egCore.net.request(
            'open-ils.search', 'open-ils.search.zip', addr.post_code)
        .then(function(resp) {
            if (!resp) return;
            if (resp.city) addr.city = resp.city;
            if (resp.state) addr.state = resp.state;
            if (resp.county) addr.county = resp.county;
            if (resp.alert) alert(resp.alert);
        });
    }

    $scope.new_waiver_entry = function() {
        var waiver = egCore.idl.toHash(new egCore.idl.aupw());
        patronRegSvc.ingest_waiver_entry($scope.patron, waiver);
        waiver.id = patronRegSvc.virt_id--;
        waiver.isnew = true;
        $scope.patron.waiver_entries.push(waiver);
    }

    deleted_waiver_entries = [];
    $scope.delete_waiver_entry = function(waiver_entry) {
        if (waiver_entry.id > 0) {
            waiver_entry.isdeleted = true;
            deleted_waiver_entries.push(waiver_entry);
        }
        var index = $scope.patron.waiver_entries.indexOf(waiver_entry);
        $scope.patron.waiver_entries.splice(index, 1);
    }

    $scope.replace_card = function() {
        $scope.patron.card.active = false;
        $scope.patron.card.ischanged = true;
        $scope.disable_bc = false;

        var new_card = egCore.idl.toHash(new egCore.idl.ac());
        new_card.id = patronRegSvc.virt_id--;
        new_card.isnew = true;
        new_card.active = true;
        new_card._primary = 'on';
        $scope.patron.card = new_card;

        // Remove any previous attempts to replace the card, since they
        // may be incomplete or created by accident.
        $scope.patron.cards =
            $scope.patron.cards.filter(function(c) {return !c.isnew})
        $scope.patron.cards.push(new_card);
    }

    $scope.day_phone_changed = function(phone) {
        if (phone && $scope.patron.isnew && 
            $scope.org_settings['patron.password.use_phone']) {
            $scope.patron.passwd = phone.substr(-4);
        }
    }

    $scope.barcode_changed = function(bc) {
        if (!bc) return;
        $scope.dupe_barcode = false;
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.barcode.exists',
            egCore.auth.token(), bc
        ).then(function(resp) {
            if (resp == '1') { // duplicate card
                $scope.dupe_barcode = true;
                console.log('duplicate barcode detected: ' + bc);
            } else {
                if (!$scope.patron.usrname)
                    $scope.patron.usrname = bc;
                // No dupe -- A-OK
            }
        });
    }

    $scope.cards_dialog = function() {
        $uibModal.open({
            templateUrl: './circ/patron/t_patron_cards_dialog',
            backdrop: 'static',
            controller: 
                   ['$scope','$uibModalInstance','cards','perms','patron',
            function($scope , $uibModalInstance , cards , perms , patron) {
                // scope here is the modal-level scope
                $scope.args = {cards : cards, primary_barcode : null};
                angular.forEach(cards, function(card) {
                    if (card.id == patron.card.id) {
                        $scope.args.primary_barcode = card.id;
                    }
                });
                $scope.perms = perms;
                $scope.ok = function() { $uibModalInstance.close($scope.args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }],
            resolve : {
                cards : function() {
                    // scope here is the controller-level scope
                    return $scope.patron.cards;
                },
                perms : function() {
                    return $scope.perms;
                },
                patron : function() {
                    return $scope.patron;
                }
            }
        }).result.then(
            function(args) {
                angular.forEach(args.cards, function(card) {
                    card.ischanged = true; // assume cards need updating, OK?
                    if (card.id == args.primary_barcode) {
                        $scope.patron.card = card;
                        card._primary = true;
                    } else {
                        card._primary = false;
                    }
                });
            }
        );
    }

    $scope.set_addr_type = function(addr, type) {
        var addrs = $scope.patron.addresses;
        if (addr['_is_'+type]) {
            angular.forEach(addrs, function(a) {
                if (a.id != addr.id) a['_is_'+type] = false;
            });
        } else {
            // unchecking mailing/billing means we have to randomly
            // select another address to fill that role.  Select the
            // first address in the list (that does not match the
            // modifed address)
            for (var i = 0; i < addrs.length; i++) {
                if (addrs[i].id != addr.id) {
                    addrs[i]['_is_' + type] = true;
                    break;
                }
            }
        }
    }


    // Translate hold notify preferences from the form/scope back into a 
    // single user setting value for opac.hold_notify.
    function compress_hold_notify() {
        var hold_notify_methods = [];
        if ($scope.hold_notify_type.phone) {
            hold_notify_methods.push('phone');
        }
        if ($scope.hold_notify_type.email) {
            hold_notify_methods.push('email');
        }
        if ($scope.hold_notify_type.sms) {
            hold_notify_methods.push('sms');
        }

        $scope.user_settings['opac.hold_notify'] = hold_notify_methods.join(':');
    }

    // dialog for selecting additional permission groups
    $scope.secondary_groups_dialog = function() {
        $uibModal.open({
            templateUrl: './circ/patron/t_patron_groups_dialog',
            backdrop: 'static',
            controller: 
                   ['$scope','$uibModalInstance','linked_groups','pgt_depth',
            function($scope , $uibModalInstance , linked_groups , pgt_depth) {

                $scope.pgt_depth = pgt_depth;
                $scope.args = {
                    linked_groups : linked_groups,
                    edit_profiles : patronRegSvc.edit_profiles,
                    new_profile   : patronRegSvc.edit_profiles[0]
                };

                // add a new group to the linked groups list
                $scope.link_group = function($event, grp) {
                    var found = false; // avoid duplicates
                    angular.forEach($scope.args.linked_groups, 
                        function(g) {if (g.id() == grp.id()) found = true});
                    if (!found) $scope.args.linked_groups.push(grp);
                    $event.preventDefault(); // avoid close
                }

                // remove a group from the linked groups list
                $scope.unlink_group = function($event, grp) {
                    $scope.args.linked_groups = 
                        $scope.args.linked_groups.filter(function(g) {
                        return g.id() != grp.id()
                    });
                    $event.preventDefault(); // avoid close
                }

                $scope.ok = function() { $uibModalInstance.close($scope.args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }],
            resolve : {
                linked_groups : function() { return $scope.patron.groups },
                pgt_depth : function() { return $scope.pgt_depth }
            }
        }).result.then(
            function(args) {

                if ($scope.patron.isnew) {
                    // groups must be linked for new patrons after the
                    // patron is created.
                    $scope.patron.groups = args.linked_groups;
                    return;
                }

                // update links groups for existing users in real time.
                var ids = args.linked_groups.map(function(g) {return g.id()});
                patronRegSvc.apply_secondary_groups($scope.patron.id, ids)
                .then(function(success) {
                    if (success)
                        $scope.patron.groups = args.linked_groups;
                });
            }
        );
    }

    function extract_hold_notify() {
        var p = $scope.patron;

        // get the user's opac.hold_notify setting
        var notify = $scope.user_settings['opac.hold_notify'];

        // if it's not set, use the default opac.hold_notify value
        if (!notify && !(notify === '')) {
            var notify_stype = $scope.user_setting_types['opac.hold_notify'];
            if (notify_stype && notify_stype.reg_default() !== undefined && notify_stype.reg_default() !== null) {
                notify = notify_stype.reg_default();
            } else {
                // no setting and no default: set phone and email to true
                notify = 'phone:email';
            }
        }

        $scope.hold_notify_type.phone = Boolean(notify.match(/phone/));
        $scope.hold_notify_type.email = Boolean(notify.match(/email/));
        $scope.hold_notify_type.sms = Boolean(notify.match(/sms/));

        // stores original loaded values for comparison later
        for (var k in $scope.hold_notify_type){
            var val = $scope.hold_notify_type[k];

            if ($scope.hold_notify_type.hasOwnProperty(k)){
                $scope.hold_notify_observer[k] = {old : val, newval: null};
            }
        }

        // actual value from user
        $scope.hold_rel_contacts.day_phone = { old: p.day_phone, newval : null };
        $scope.hold_rel_contacts.other_phone = { old: p.other_phone, newval : null };
        $scope.hold_rel_contacts.evening_phone = { old: p.evening_phone, newval : null };
        // from user_settings
        $scope.hold_rel_contacts.default_phone = { old: $scope.user_settings['opac.default_phone'], newval : null };
        $scope.hold_rel_contacts.default_sms = { old: $scope.user_settings['opac.default_sms_notify'], newval : null };
        $scope.hold_rel_contacts.default_sms_carrier_id = { old: $scope.user_settings['opac.default_sms_carrier'], newval : null };

    }

    function normalizePhone(number){
        // normalize phone # for comparison, only digits
        if (number == null || number == undefined) return '';
        
        var regex = /[^\d]/g;
        return number.replace(regex, '');
    }

    $scope.invalidate_field = function(field) {
        patronRegSvc.invalidate_field($scope.patron, field).then(function() {
            $scope.handle_field_changed($scope.patron, field);
        });
    }

    $scope.send_test_email = function() {
        patronRegSvc.send_test_message($scope.patron.id, 'au.email.test').then(function(res) {
            if (res && res.template_output() && res.template_output().is_error() == 'f') {
                 ngToast.success(egCore.strings.TEST_NOTIFY_SUCCESS);
            } else {
                ngToast.warning(egCore.strings.TEST_NOTIFY_FAIL);
                if (res) console.log(res);
            }
        });
    }

    $scope.send_test_sms = function() {
        patronRegSvc.send_test_message($scope.patron.id, 'au.sms_text.test').then(function(res) {
            if (res && res.template_output() && res.template_output().is_error() == 'f') {
                 ngToast.success(egCore.strings.TEST_NOTIFY_SUCCESS);
            } else {
                ngToast.warning(egCore.strings.TEST_NOTIFY_FAIL);
                if (res) console.log(res);
            }
        });
    }

    address_alert = function(addr) {
        var args = {
            street1: addr.street1,
            street2: addr.street2,
            city: addr.city,
            state: addr.state,
            county: addr.county,
            country: addr.country,
            post_code: addr.post_code,
            mailing_address: addr._is_mailing,
            billing_address: addr._is_billing
        }

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.address_alert.test',
            egCore.auth.token(), egCore.auth.user().ws_ou(), args
            ).then(function(res) {
                $scope.address_alerts = res;
        });
    }

    $scope.dupe_value_changed = function(type, value) {
        if (!$scope.dupe_search_encoded)
            $scope.dupe_search_encoded = {};

        $scope.dupe_counts[type] = 0;

        patronRegSvc.dupe_patron_search($scope.patron, type, value)
        .then(function(res) {
            $scope.dupe_counts[type] = res.count;
            if (res.count) {
                $scope.dupe_search_encoded[type] = 
                    encodeURIComponent(js2JSON(res.search));
            } else {
                $scope.dupe_search_encoded[type] = '';
            }
        });
    }

    $scope.handle_home_org_changed = function() {
        org_id = $scope.patron.home_ou.id();
        patronRegSvc.has_perms_for_org(org_id).then(function(map) {
            angular.forEach(map, function(v, k) { $scope.perms[k] = v });
        });
    }

    $scope.clear_pulib = function() {
        if (!$scope.user_settings) return; // still rendering
        $scope.patron._pickup_lib = null;
        $scope.user_settings['opac.default_pickup_location'] = null;
    }

    $scope.handle_pulib_changed = function(org) {
        if (!$scope.user_settings) return; // still rendering
        $scope.user_settings['opac.default_pickup_location'] = org.id();
    }

    // This is called with every character typed in a form field,
    // since that's the only way to gaurantee something has changed.
    // See handle_field_changed for ng-change vs. ng-blur.
    $scope.field_modified = function() {
        // Call attach with every field change, regardless of whether
        // it's been called before.  This will allow for re-attach after
        // the user clicks through the unload warning. egUnloadPrompt
        // will ensure we only attach once.
        egUnloadPrompt.attach($scope);
    }

    // also monitor when form is changed *by the user*, as using
    // an ng-change handler doesn't work with eg-date-input
    $scope.$watch('reg_form.$pristine', function(newVal, oldVal) {
        if (!newVal) egUnloadPrompt.attach($scope);
    });

    // username regex (if present) must be removed any time
    // the username matches the barcode to avoid firing the
    // invalid field handlers.
    function apply_username_regex() {
        var regex = $scope.org_settings['opac.username_regex'];
        if (regex) {
            if ($scope.patron.card.barcode) {
                // username must match the regex or the barcode
                field_patterns.au.usrname = 
                    new RegExp(
                        regex + '|^' + $scope.patron.card.barcode + '$');
            } else {
                // username must match the regex
                field_patterns.au.usrname = new RegExp(regex);
            }
        } else {
            // username can be any format.
            field_patterns.au.usrname = new RegExp('.*');
        }
    }

    // obj could be the patron, an address, etc.
    // This is called any time a form field achieves then loses focus.
    // It does not necessarily mean the field has changed.
    // The alternative is ng-change, but it's called with each character
    // typed, which would be overkill for many of the actions called here.
    $scope.handle_field_changed = function(obj, field_name) {
        var cls = obj.classname; // set by egIdl
        var value = obj[field_name];

        console.debug('changing field ' + field_name + ' to ' + value);

        switch (field_name) {
            case 'day_phone' :
                if (normalizePhone(value) !== normalizePhone($scope.hold_rel_contacts.day_phone.old)){
                    $scope.hold_rel_contacts.day_phone.newval = value;
                }
                if ($scope.patron.day_phone && 
                    $scope.patron.isnew && 
                    $scope.org_settings['patron.password.use_phone']) {
                    $scope.patron.passwd = $scope.patron.day_phone.substr(-4);
                }
                $scope.dupe_value_changed(field_name, value);
                break;
            case 'evening_phone' :
                if (normalizePhone(value) !== normalizePhone($scope.hold_rel_contacts.evening_phone.old)){
                    $scope.hold_rel_contacts.evening_phone.newval = value;
                }
                $scope.dupe_value_changed(field_name, value);
                break;
            case 'other_phone' : 
                if (normalizePhone(value) !== normalizePhone($scope.hold_rel_contacts.other_phone.old)){
                    $scope.hold_rel_contacts.other_phone.newval = value;
                }
                $scope.dupe_value_changed(field_name, value);
                break;
            case 'ident_value':
            case 'ident_value2':
                $scope.dupe_value_changed('ident', value);
                break;

            case 'first_given_name':
            case 'family_name':
                $scope.dupe_value_changed('name', value);
                break;

            case 'email':
                $scope.dupe_value_changed('email', value);
                break;

            case 'street1':
            case 'street2':
            case 'city':
                // dupe search on address wants the address object as the value.
                $scope.dupe_value_changed('address', obj);
                address_alert(obj);
                break;

            case 'post_code':
                $scope.post_code_changed(obj);
                break;

            case 'usrname':
                patronRegSvc.check_dupe_username(value)
                .then(function(yes) {$scope.dupe_username = Boolean(yes)});
                break;

            case 'barcode':
                // TODO: finish barcode_changed handler.
                $scope.barcode_changed(value);
                apply_username_regex();
                break;
            case 'opac.default_phone':
                if (normalizePhone(value) !== normalizePhone($scope.hold_rel_contacts.default_phone.old)){
                    $scope.hold_rel_contacts.default_phone.newval = value;
                }
                break;
            case 'opac.default_sms_notify':
                if (normalizePhone(value) !== normalizePhone($scope.hold_rel_contacts.default_sms.old)){
                    $scope.hold_rel_contacts.default_sms.newval = value;
                }
                break;
            case 'opac.default_sms_carrier':
                if (value !== $scope.hold_rel_contacts.default_sms_carrier_id.old){
                    $scope.hold_rel_contacts.default_sms_carrier_id.newval = value;
                }
                break;
        }
    }

    // patron.juvenile is set to true if the user was born after
    function maintain_juvenile_flag() {
        if ( !($scope.patron && $scope.patron.dob) ) return;

        var juv_interval = 
            $scope.org_settings['global.juvenile_age_threshold'] 
            || '18 years';

        var base = new Date();

        base.setTime(base.getTime() - 
            Number(egCore.date.intervalToSeconds(juv_interval) + '000'));

        $scope.patron.juvenile = ($scope.patron.dob > base);
    }

    // returns true (disable) for orgs that cannot have users.
    $scope.disable_home_org = function(org_id) {
        if (!org_id) return;
        var org = egCore.org.get(org_id);
        return (
            org &&
            org.ou_type() &&
            org.ou_type().can_have_users() == 'f'
        );
    }

    // returns true (disable) for orgs that cannot have vols (for holds pickup)
    $scope.disable_pulib = function(org_id) {
        if (!org_id) return;
        return !egCore.org.CanHaveVolumes(org_id);
    }

    // Returns true if attempting to edit self, but perms don't allow
    $scope.edit_passthru.self_edit_disallowed = function() {
        if ($scope.patron.id
            && $scope.patron.id == egCore.auth.user().id()
            && !$scope.perms.EDIT_SELF_IN_CLIENT
        ) return true;
        return false;
    }

    // Returns true if attempting to edit a user without appropriate group application perms
    $scope.edit_passthru.group_edit_disallowed = function() {
        if ( $scope.patron.profile
             && patronRegSvc
                .edit_profiles
                .filter(function(p) {
                    return $scope.patron.profile.id() == p.id();
                }).length == 0
        ) return true;
        return false;
    }

    // Returns true if the Save and Save & Clone buttons should be disabled.
    $scope.edit_passthru.hide_save_actions = function() {
        if ($scope.edit_passthru.self_edit_disallowed()) return true;
        if ($scope.edit_passthru.group_edit_disallowed()) return true;

        return $scope.patron.isnew ?
            !$scope.perms.CREATE_USER : 
            !$scope.perms.UPDATE_USER;
    }

    // Returns true if any input elements are tagged as invalid
    // via Angular patterns or required attributes.
    function form_has_invalid_fields() {
        return $('#patron-reg-container .ng-invalid').length > 0;
    }

    function form_is_incomplete() {
        return (
            $scope.dupe_username ||
            $scope.dupe_barcode ||
            form_has_invalid_fields()
        );

    }

    $scope.edit_passthru.save = function(save_args) {
        if (!save_args) save_args = {};

        if (form_is_incomplete()) {
            // User has not provided valid values for all required fields.
            return egAlertDialog.open(egCore.strings.REG_INVALID_FIELDS);
        }

        // remove page unload warning prompt
        egUnloadPrompt.clear();

        // toss the deleted addresses back into the patron's list of
        // addresses so it's included in the update
        $scope.patron.addresses = 
            $scope.patron.addresses.concat(deleted_addresses);
        
        // ditto for waiver entries
        $scope.patron.waiver_entries = 
            $scope.patron.waiver_entries.concat(deleted_waiver_entries);

        compress_hold_notify();

        var updated_user;

        patronRegSvc.save_user($scope.patron)
        .then(function(new_user) { 
            if (new_user && new_user.classname) {
                updated_user = new_user;
                return patronRegSvc.save_user_settings(
                    new_user, $scope.user_settings); 
            } else {
                var evt = egCore.evt.parse(new_user);

                if (evt && evt.textcode == 'XACT_COLLISION') {
                    return egAlertDialog.open(
                        egCore.strings.PATRON_EDIT_COLLISION).result;
                }

                // debug only -- should not get here.
                alert('Patron update failed. \n\n' + js2JSON(new_user));
            }

        }).then(function() {

            // only remove the staged user if the update succeeded.
            if (updated_user) 
                return patronRegSvc.remove_staged_user();

            return $q.when();

        }).then(function() {

            // linked groups for new users must be created after the new
            // user is created.
            if ($scope.patron.isnew && 
                $scope.patron.groups && $scope.patron.groups.length) {
                var ids = $scope.patron.groups.map(function(g) {return g.id()});
                return patronRegSvc.apply_secondary_groups(updated_user.id(), ids)
            }
            return $q.when();

        }).then(findChangedFieldsAffectedHolds)
        .then(function(changed_fields_plus_holds) {
            var needModal = changed_fields_plus_holds[0] && changed_fields_plus_holds[0].length > 0;
            return needModal
                ? $scope.update_holds_notify_modal(changed_fields_plus_holds[0])
                : $q.when(); // nothing changed, continue
        }).then(function() {
            if (updated_user) {
                egWorkLog.record(
                    $scope.patron.isnew
                    ? egCore.strings.EG_WORK_LOG_REGISTERED_PATRON
                    : egCore.strings.EG_WORK_LOG_EDITED_PATRON, {
                        'action' : $scope.patron.isnew ? 'registered_patron' : 'edited_patron',
                        'patron_id' : updated_user.id()
                    }
                );
            }

            // reloading the page means potentially losing some information
            // (e.g. last patron search), but is the only way to ensure all
            // components are properly updated to reflect the modified patron.
            if (updated_user && save_args.clone) {
                // open a separate tab for registering a new 
                // patron from our cloned data.
                var url = 'https://' 
                    + $window.location.hostname 
                    + egCore.env.basePath 
                    + '/circ/patron/register/clone/' 
                    + updated_user.id();
                $window.open(url, '_blank').focus();

            } else if ($window.location.href.indexOf('stage') > -1 ){
                // we're here after deleting a self-reg staged user.
                // Just close tab, since refresh won't find staged user
                $timeout(function(){
                    if (typeof BroadcastChannel != 'undefined') {
                        var bChannel = new BroadcastChannel("eg.pending_usr.update");
                        bChannel.postMessage({
                            usr: egCore.idl.toHash(updated_user)
                        });
                    }

                    $window.close();
                });
            } else {
                // reload the current page
                $window.location.href = location.href;
            }
        });
    }
    
    var phone_inputs = ["day_phone", "evening_phone","other_phone", "default_phone"];
    var sms_inputs = ["default_sms", "default_sms_carrier_id"];
    var method_prefs = ["sms_notify", "phone_notify", "email_notify"];
    var groupBy = function(xs, key){
        return xs.reduce(function(rv, x){
            (rv[x[key]] = rv[x[key]] || []).push(x);
            return rv;
        }, {});
    };

    function findChangedFieldsAffectedHolds(){
    
        var changed_hold_fields = [];

        var default_phone_changed = false;
        var default_sms_carrier_changed = false;
        var default_sms_changed = false;
        for (var c in $scope.hold_rel_contacts){
            var newinput = $scope.hold_rel_contacts[c].newval;
            if ($scope.hold_rel_contacts.hasOwnProperty(c)
                && newinput !== null // null means user has not provided a value in this session
                && newinput != $scope.hold_rel_contacts[c].old){
                var changed = $scope.hold_rel_contacts[c];
                changed.name = c;
                changed.isChecked = false;
                changed_hold_fields.push(changed);
                if (c === 'default_phone') default_phone_changed = true;
                if (c === 'default_sms_carrier_id') default_sms_carrier_changed = true;
                if (c === 'default_sms') default_sms_changed = true;
            }
        }

        for (var c in $scope.hold_notify_observer){
            var newinput = $scope.hold_notify_observer[c].newval;
            if ($scope.hold_notify_observer.hasOwnProperty(c)
                && newinput !== null // null means user has not provided a value in this session
                && newinput != $scope.hold_notify_observer[c].old){
                var changed = $scope.hold_notify_observer[c];
                changed.name = c + "_notify";
                changed.isChecked = false;
                changed_hold_fields.push(changed);

                // if we're turning on phone notifications, offer to update to the
                // current default number
                if (c === 'phone' && $scope.user_settings['opac.default_phone'] && newinput && !default_phone_changed) {
                    changed_hold_fields.push({
                        name: 'default_phone',
                        old: 'nosuch',
                        newval: $scope.user_settings['opac.default_phone'],
                        isChecked: false
                    });
                }
                // and similarly for SMS
                if (c === 'sms' && $scope.user_settings['opac.default_sms_carrier'] && newinput && !default_sms_carrier_changed) {
                    changed_hold_fields.push({
                        name: 'default_sms_carrier_id',
                        old: -1,
                        newval: $scope.user_settings['opac.default_sms_carrier'],
                        isChecked: false
                    });
                }
                if (c === 'sms' && $scope.user_settings['opac.default_sms_notify'] && newinput && !default_sms_changed) {
                    changed_hold_fields.push({
                        name: 'default_sms',
                        old: 'nosuch',
                        newval: $scope.user_settings['opac.default_sms_notify'],
                        isChecked: false
                    });
                }
            }
        }

        var promises = [];
        angular.forEach(changed_hold_fields, function(c){
            promises.push(egCore.net.request('open-ils.circ',
            'open-ils.circ.holds.retrieve_by_notify_staff',
            egCore.auth.token(),
            $scope.patron.id,
            c.name.includes('notify') || c.name.includes('carrier') ? c.old : c.newval,
            c.name)
                .then(function(affected_holds){
                    if(!affected_holds || affected_holds.length < 1){
                        // no holds affected - remove change from list
                        var p = changed_hold_fields.indexOf(c);
                        changed_hold_fields.splice(p, 1);
                    } else {
                        c.affects = affected_holds;
                        //c.groups = {};
                        //angular.forEach(c.affects, function(h){
                        //    c.groups[]
                        //});
                        if (!c.name.includes("notify")){
                            if (c.name === "default_sms_carrier_id") {
                                c.groups = groupBy(c.affects,'sms_carrier');
                            } else {
                                c.groups = groupBy(c.affects, c.name.includes('_phone') ? 'phone_notify':'sms_notify');
                            }
                        }
                    }
                    return $q.when(changed_hold_fields);
                })
            );
        });

        return $q.all(promises);
    }

    $scope.update_holds_notify_modal = function(changed_hold_fields){
        // open modal after-save, pre-reload modal to deal with updated hold notification stuff
        if ($scope.patron.isnew || changed_hold_fields.length < 1){
            return $q.when();
        }

        return $uibModal.open({
            templateUrl: './circ/patron/t_hold_notify_update',
            backdrop: 'static',
            controller:
                       ['$scope','$uibModalInstance','changed_fields','patron','carriers','def_carrier_id','default_phone','default_sms',
                function($scope , $uibModalInstance , changed_fields , patron,  carriers,  def_carrier_id , default_phone , default_sms) {
                // local modal scope
                $scope.ch_fields = changed_fields;
                $scope.focusMe = true;
                $scope.ok = function(msg) {

                    // Need to do this so the page will reload automatically
                    if (msg == 'no-update') return $uibModalInstance.close();

                    //var selectedChanges = $scope.changed_fields.filter(function(c) {
                    //    return c.isChecked;
                    //});
                    var selectedChanges = [];
                    angular.forEach($scope.ch_fields, function(f){
                        if (f.name == 'phone_notify' && f.newval && f.isChecked) {
                            // convert to default_phone change
                            f.sel_hids = f.affects.map(function(h){ return h.id});
                            f.newval = default_phone;
                            f.name = 'default_phone';
                            selectedChanges.push(f);
                        } else if (f.name == 'sms_notify' && f.newval && f.isChecked) {
                            // convert to default_sms change
                            f.sel_hids = f.affects.map(function(h){ return h.id});
                            f.newval = default_sms;
                            f.name = 'default_sms';
                            selectedChanges.push(f);
                        } else if (f.name.includes('notify') || f.name.includes('carrier')){
                            if (f.isChecked){
                                f.sel_hids = f.affects.map(function(h){ return h.id});
                                selectedChanges.push(f);
                            }
                        } else {
                            // this is the sms or phone, so look in the groups obj
                            f.sel_hids = [];
                            for (var k in f.groups){
                                if (f.groups.hasOwnProperty(k)){
                                    var sel_holds = f.groups[k].filter(function(h){
                                        return h.isChecked;
                                    });
                                    
                                    var hids = sel_holds.map(function(h){ return h.id});
                                    f.sel_hids.push.apply(f.sel_hids, hids);
                                }
                            }

                            if (f.sel_hids.length > 0) selectedChanges.push(f);
                        }
                    });


                    // call method to update holds for each change
                    var chain = $q.when();
                    angular.forEach(selectedChanges, function(c){
                        var carrierId = c.name.includes('default_sms') ? Number(def_carrier_id) : null;
                        chain = chain.then(function() {
                            return egCore.net.request('open-ils.circ',
                                    'open-ils.circ.holds.batch_update_holds_by_notify_staff', egCore.auth.token(),
                                    patron.id,
                                    c.sel_hids,
                                    c.old, // TODO: for number changes, old val is effectively moot
                                    c.newval,
                                    c.name,
                                    carrierId).then(function(okList){ console.log(okList) });
                        });
                    });

                    // carry out the updates and close modal
                    chain.finally(function(){ $uibModalInstance.close() });
                }

                $scope.cancel = function () { $uibModalInstance.dismiss() }

                $scope.isNumberCh = function(c){
                    return !(c.name.includes('notify') || c.name.includes('carrier'));
                }

                $scope.chgCt = 0;
                $scope.groupChanged = function(ch_f, grpK){
                    var holdArr = ch_f.groups[grpK];
                    if (holdArr && holdArr.length > 0){
                        angular.forEach(holdArr, function(h){
                            if (h.isChecked) { h.isChecked = !h.isChecked; $scope.chgCt-- }
                            else { h.isChecked = true; $scope.chgCt++ }
                        });
                    }
                }
                
                $scope.nonGrpChanged = function(field_ch){
                    if (field_ch.isChecked) $scope.chgCt++;
                    else $scope.chgCt--;
                };

                // use this function as a keydown handler on form
                // elements that should not submit the form on enter.
                $scope.preventSubmit = function($event) {
                    if ($event.keyCode == 13)
                        $event.preventDefault();
                }

                $scope.prettyCarrier = function(carrierId){
                    var sms_carrierObj = carriers.find(function(c){ return c.id == carrierId});
                    return sms_carrierObj.name;
                };
                $scope.prettyBool = function(v){
                    return v ? 'YES' : 'NO';
                };
            }],
            resolve : {
                    changed_fields : function(){ return changed_hold_fields },
                    patron : function(){ return $scope.patron },
                    def_carrier_id : function(){
                                       var d = $scope.hold_rel_contacts.default_sms_carrier_id;
                                       return d.newval ? d.newval : d.old;
                                    },
                    default_phone : function() {
                                        return ($scope.hold_rel_contacts.default_phone.newval) ?
                                                    $scope.hold_rel_contacts.default_phone.newval :
                                                    $scope.hold_rel_contacts.default_phone.old;
                                    },
                    default_sms : function() {
                                        return ($scope.hold_rel_contacts.default_sms.newval) ?
                                                    $scope.hold_rel_contacts.default_sms.newval :
                                                    $scope.hold_rel_contacts.default_sms.old;
                                    },
                    carriers : function(){ return $scope.sms_carriers.map(function(c){ return egCore.idl.toHash(c) }) }
                }
        }).result;
    }
    
    $scope.edit_passthru.print = function() {
        var print_data = {patron : $scope.patron}

        return egCore.print.print({
            context : 'default',
            template : 'patron_data',
            scope : print_data
        });
    }
}])
