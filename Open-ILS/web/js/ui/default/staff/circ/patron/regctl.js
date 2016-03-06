
angular.module('egCoreMod')
// toss tihs onto egCoreMod since the page app may vary

.factory('patronRegSvc', ['$q', 'egCore', function($q, egCore) {

    var service = {
        field_doc : {},            // config.idl_field_doc
        profiles : [],             // permission groups
        edit_profiles : [],        // perm groups we can modify
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
        init_done : false           // have we loaded our initialization data?
    };

    // launch a series of parallel data retrieval calls
    service.init = function(scope) {

        // Data loaded here only needs to be retrieved the first time this
        // tab becomes active within the current instance of the patron app.
        // In other words, navigating between patron tabs will not cause
        // all of this data to be reloaded.  Navigating to a separate app
        // and returning will cause the data to be reloaded.
        if (service.init_done) return $q.when();
        service.init_done = true;

        return $q.all([
            service.get_field_doc(),
            service.get_perm_groups(),
            service.get_ident_types(),
            service.get_user_settings(),
            service.get_org_settings(),
            service.get_stat_cats(),
            service.get_surveys(),
            service.get_clone_user(),
            service.get_stage_user(),
            service.get_net_access_levels()
        ]);
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
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.username.exists',
            egCore.auth.token(), usrname);
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

    // resolves to a hash of perm-name => boolean value indicating
    // wether the user has the permission at org_id.
    service.has_perms_for_org = function(org_id) {

        var perms_needed = [
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
            'ui.patron.edit.au.juvenile.show',
            'ui.patron.edit.au.juvenile.suggest',
            'ui.patron.edit.au.ident_value.show',
            'ui.patron.edit.au.ident_value.suggest',
            'ui.patron.edit.au.ident_value2.show',
            'ui.patron.edit.au.ident_value2.suggest',
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
            'ui.patron.edit.au.alert_message.show',
            'ui.patron.edit.au.alert_message.suggest',
            'ui.patron.edit.aua.post_code.regex',
            'ui.patron.edit.aua.post_code.example',
            'ui.patron.edit.aua.county.require',
            'format.date',
            'ui.patron.edit.default_suggested',
            'opac.barcode_regex',
            'opac.username_regex',
            'sms.enable',
            'ui.patron.edit.aua.state.require',
            'ui.patron.edit.aua.state.suggest',
            'ui.patron.edit.aua.state.show'
        ]).then(function(settings) {
            service.org_settings = settings;
            return service.process_org_settings(settings);
        });
    };

    // some org settings require the retrieval of additional data
    service.process_org_settings = function(settings) {

        var promises = [];

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

    service.get_field_doc = function() {
        return egCore.pcrud.search('fdoc', {
            fm_class: ['au', 'ac', 'aua', 'actsc', 'asv', 'asvq', 'asva']})
        .then(null, null, function(doc) {
            if (!service.field_doc[doc.fm_class()]) {
                service.field_doc[doc.fm_class()] = {};
            }
            service.field_doc[doc.fm_class()][doc.field()] = doc;
        });
    };

    service.get_user_settings = function() {
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

            angular.forEach(setting_types, function(stype) {
                service.user_setting_types[stype.name()] = stype;
                if (static_types.indexOf(stype.name()) == -1) {
                    service.opt_in_setting_types[stype.name()] = stype;
                }
            });

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
                        service.user_settings[setting.name()] = 
                            setting.reg_default();
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

    service.dupe_patron_search = function(patron, type, value) {
        var search;

        console.log('Dupe search called with "'+ type +'" and value '+ value);

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
            return service.init_new_patron();

        service.patron = current;
        return service.init_existing_patron(current)
    }

    service.ingest_address = function(patron, addr) {
        addr.valid = addr.valid == 't';
        addr.within_city_limits = addr.within_city_limits == 't';
        addr._is_mailing = (patron.mailing_address && 
            addr.id == patron.mailing_address.id);
        addr._is_billing = (patron.billing_address && 
            addr.id == patron.billing_address.id);
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

        var patron = egCore.idl.toHash(current);

        patron.home_ou = egCore.org.get(patron.home_ou.id);
        patron.expire_date = new Date(Date.parse(patron.expire_date));
        patron.dob = service.parse_dob(patron.dob);
        patron.profile = current.profile(); // pre-hash version
        patron.net_access_level = current.net_access_level();
        patron.ident_type = current.ident_type();
        patron.groups = current.groups(); // pre-hash

        angular.forEach(
            ['juvenile', 'barred', 'active', 'master_account'],
            function(field) { patron[field] = patron[field] == 't'; }
        );

        angular.forEach(patron.cards, function(card) {
            card.active = card.active == 't';
            if (card.id == patron.card.id) {
                patron.card = card;
                card._primary = 'on';
            }
        });

        angular.forEach(patron.addresses, 
            function(addr) { service.ingest_address(patron, addr) });

        // toss entries for existing stat cat maps into our living 
        // stat cat entry map, which is modified within the template.
        angular.forEach(patron.stat_cat_entries, function(map) {
            service.stat_cat_entry_maps[map.stat_cat.id] = map.stat_cat_entry;
        });

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
            _primary : 'on'
        };

        var user = {
            isnew : true,
            active : true,
            card : card,
            cards : [card],
            home_ou : egCore.org.get(egCore.auth.user().ws_ou()),
            stat_cat_entries : [],
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
        var d = new Date(); // always local time zone, yay.
        d.setFullYear(parts[0]);
        d.setMonth(parts[1]);
        d.setDate(parts[2]);
        return d;
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
                _primary : 'on'
            };

            user.cards.push(user.card);
            if (user.usrname == '') 
                user.usrname = card.barcode;
        }
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
            patron.dob(patron.dob().toISOString().replace(/T.*/,''));
        if (patron.ident_type()) 
            patron.ident_type(patron.ident_type().id());
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

        if (!patron.isnew()) patron.ischanged(true);

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
            service.stage_user.row_id()
        );
    }

    service.save_user_settings = function(new_user, user_settings) {
        // user_settings contains the values from the scope/form.
        // service.user_settings contain the values from page load time.

        var settings = {};
        if (service.patron_id) {
            // only update modified settings for existing patrons
            angular.forEach(user_settings, function(val, key) {
                if (val !== service.user_settings[key])
                    settings[key] = val;
            });

        } else {
            // all non-null setting values are updated for new patrons
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

        if (service.org_settings['opac.barcode_regex']) {
            patterns.ac.barcode = 
                new RegExp(service.org_settings['opac.barcode_regex']);
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
}]);


function PatronRegCtrl($scope, $routeParams, 
    $q, $modal, $window, egCore, patronSvc, patronRegSvc, egUnloadPrompt) {

    $scope.page_data_loaded = false;
    $scope.clone_id = patronRegSvc.clone_id = $routeParams.clone_id;
    $scope.stage_username = 
        patronRegSvc.stage_username = $routeParams.stage_username;
    $scope.patron_id = 
        patronRegSvc.patron_id = $routeParams.edit_id || $routeParams.id;

    // for existing patrons, disable barcode input by default
    $scope.disable_bc = $scope.focus_usrname = Boolean($scope.patron_id);
    $scope.focus_bc = !Boolean($scope.patron_id);
    $scope.dupe_counts = {};

    // map of perm name to true/false for perms the logged in user
    // has at the currently selected patron home org unit.
    $scope.perms = {};

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
            $scope.generate_password();
        }
        $scope.hold_notify_phone = true;
        $scope.hold_notify_email = true;

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
    var field_patterns = {au : {}, ac : {}, aua : {}};
    $scope.field_pattern = function(cls, field) { 
        if (!field_patterns[cls][field])
            field_patterns[cls][field] = new RegExp('.*');
        return field_patterns[cls][field];
    }

    // Main page load function.  Kicks off tab init and data loading.
    $q.all([

        $scope.initTab ? // initTab comes from patron app
            $scope.initTab('edit', $routeParams.id) : $q.when(),

        patronRegSvc.init()

    ]).then(function() {
        // called after initTab and patronRegSvc.init have completed

        var prs = patronRegSvc; // brevity
        // in standalone mode, we have no patronSvc
        $scope.patron = prs.init_patron(patronSvc ? patronSvc.current : null);
        $scope.field_doc = prs.field_doc;
        $scope.edit_profiles = prs.edit_profiles;
        $scope.ident_types = prs.ident_types;
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
        // clone the user settings back into the patronRegSvc so
        // we have a copy of the original state of the settings.
        prs.user_settings = {};
        angular.forEach($scope.user_settings, function(val, key) {
            prs.user_settings[key] = val;
        });

        extract_hold_notify();
        $scope.handle_home_org_changed();

        if ($scope.org_settings['ui.patron.edit.default_suggested'])
            $scope.edit_passthru.vis_level = 1;

        if ($scope.patron.isnew) 
            set_new_patron_defaults(prs);

        $scope.page_data_loaded = true;

        prs.set_field_patterns(field_patterns);
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
    var field_visibility = {
        'ac.barcode' : 3,
        'au.usrname' : 3,
        'au.passwd' :  3,
        'au.first_given_name' : 3,
        'au.family_name' : 3,
        'au.ident_type' : 3,
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
        'surveys' : 1
    }; 

    // returns true if the selected field should be visible
    // given the current required/suggested/all setting.
    $scope.show_field = function(field_key) {

        if (field_visibility[field_key] == undefined) {
            // compile and cache the visibility for the selected field

            // org settings have not been received yet.
            if (!$scope.org_settings) return false;

            var req_set = 'ui.patron.edit.' + field_key + '.require';
            var sho_set = 'ui.patron.edit.' + field_key + '.show';
            var sug_set = 'ui.patron.edit.' + field_key + '.suggest';

            if ($scope.org_settings[req_set]) {
                field_visibility[field_key] = 3;
            } else if ($scope.org_settings[sho_set]) {
                field_visibility[field_key] = 2;
            } else if ($scope.org_settings[sug_set]) {
                field_visibility[field_key] = 1;
            } else {
                field_visibility[field_key] = 0;
            }
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

    $scope.set_expire_date = function() {
        if (!$scope.patron.profile) return;
        var seconds = egCore.date.intervalToSeconds(
            $scope.patron.profile.perm_interval());
        var now_epoch = new Date().getTime();
        $scope.patron.expire_date = new Date(
            now_epoch + (seconds * 1000 /* milliseconds */))
    }

    // grp is the pgt object
    $scope.set_profile = function(grp) {
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
            if (resp == '1') {
                $scope.dupe_barcode = true;
                console.log('duplicate barcode detected: ' + bc);
                // DUPLICATE CARD
            } else {
                if (!$scope.patron.usrname)
                    $scope.patron.usrname = bc;
                // No dupe -- A-OK
            }
        });
    }

    $scope.cards_dialog = function() {
        $modal.open({
            templateUrl: './circ/patron/t_patron_cards_dialog',
            controller: 
                   ['$scope','$modalInstance','cards', 'perms',
            function($scope , $modalInstance , cards, perms) {
                // scope here is the modal-level scope
                $scope.args = {cards : cards};
                $scope.perms = perms;
                $scope.ok = function() { $modalInstance.close($scope.args) }
                $scope.cancel = function () { $modalInstance.dismiss() }
            }],
            resolve : {
                cards : function() {
                    // scope here is the controller-level scope
                    return $scope.patron.cards;
                },
                perms : function() {
                    return $scope.perms;
                }
            }
        }).result.then(
            function(args) {
                angular.forEach(args.cards, function(card) {
                    card.ischanged = true; // assume cards need updating, OK?
                    if (card._primary == 'on' && 
                        card.id != $scope.patron.card.id) {
                        $scope.patron.card = card;
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
        var hold_notify = '';
        var splitter = '';
        if ($scope.hold_notify_phone) {
            hold_notify = 'phone';
            splitter = ':';
        }
        if ($scope.hold_notify_email) {
            hold_notify = splitter + 'email';
            splitter = ':';
        }
        if ($scope.hold_notify_sms) {
            hold_notify = splitter + 'sms';
            splitter = ':';
        }
        $scope.user_settings['opac.hold_notify'] = hold_notify;
    }

    // dialog for selecting additional permission groups
    $scope.secondary_groups_dialog = function() {
        $modal.open({
            templateUrl: './circ/patron/t_patron_groups_dialog',
            controller: 
                   ['$scope','$modalInstance','linked_groups','pgt_depth',
            function($scope , $modalInstance , linked_groups , pgt_depth) {

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

                $scope.ok = function() { $modalInstance.close($scope.args) }
                $scope.cancel = function () { $modalInstance.dismiss() }
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
        notify = $scope.user_settings['opac.hold_notify'];
        if (!notify) return;
        $scope.hold_notify_phone = Boolean(notify.match(/phone/));
        $scope.hold_notify_email = Boolean(notify.match(/email/));
        $scope.hold_notify_sms = Boolean(notify.match(/sms/));
    }

    $scope.invalidate_field = function(field) {
        patronRegSvc.invalidate_field($scope.patron, field);
    }


    $scope.dupe_value_changed = function(type, value) {
        $scope.dupe_counts[type] = 0;
        patronRegSvc.dupe_patron_search($scope.patron, type, value)
        .then(function(res) {
            $scope.dupe_counts[type] = res.count;
            if (res.count) {
                $scope.dupe_search_encoded = 
                    encodeURIComponent(js2JSON(res.search));
            } else {
                $scope.dupe_search_encoded = '';
            }
        });
    }

    $scope.handle_home_org_changed = function() {
        org_id = $scope.patron.home_ou.id();
        patronRegSvc.has_perms_for_org(org_id).then(function(map) {
            angular.forEach(map, function(v, k) { $scope.perms[k] = v });
        });
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

    // obj could be the patron, an address, etc.
    // This is called any time a form field achieves then loses focus.
    // It does not necessarily mean the field has changed.
    // The alternative is ng-change, but it's called with each character
    // typed, which would be overkill for many of the actions called here.
    $scope.handle_field_changed = function(obj, field_name) {
        var cls = obj.classname; // set by egIdl
        var value = obj[field_name];

        console.log('changing field ' + field_name + ' to ' + value);

        switch (field_name) {
            case 'day_phone' : 
                if ($scope.patron.day_phone && 
                    $scope.patron.isnew && 
                    $scope.org_settings['patron.password.use_phone']) {
                    $scope.patron.passwd = phone.substr(-4);
                }
            case 'evening_phone' : 
            case 'other_phone' : 
                $scope.dupe_value_changed('phone', value);
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
                break;

            case 'dob':
                maintain_juvenile_flag();
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

    // Returns true if any input elements are tagged as invalid
    $scope.edit_passthru.has_invalid_fields = function() {
        return $('#patron-reg-container .ng-invalid').length > 0;
    }

    // Returns true if the Save and Save & Clone buttons should be disabled.
    $scope.edit_passthru.hide_save_actions = function() {
        var can_save = $scope.patron.isnew ?
            $scope.perms.CREATE_USER : $scope.perms.UPDATE_USER;

        return (
            !can_save ||
            $scope.dupe_username ||
            $scope.dupe_barcode ||
            $scope.edit_passthru.has_invalid_fields()
        );
    }

    $scope.edit_passthru.save = function(save_args) {
        if (!save_args) save_args = {};

        // remove page unload warning prompt
        egUnloadPrompt.clear();

        // toss the deleted addresses back into the patron's list of
        // addresses so it's included in the update
        $scope.patron.addresses = 
            $scope.patron.addresses.concat(deleted_addresses);
        
        compress_hold_notify();

        var updated_user;

        patronRegSvc.save_user($scope.patron)
        .then(function(new_user) { 
            if (new_user && new_user.classname) {
                updated_user = new_user;
                return patronRegSvc.save_user_settings(
                    new_user, $scope.user_settings); 
            } else {
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

        }).then(function() {

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

            } else {
                // reload the current page
                $window.location.href = location.href;
            }
        });
    }
}

// This controller may be loaded from different modules (patron edit vs.
// register new patron), so we have to inject the controller params manually.
PatronRegCtrl.$inject = ['$scope', '$routeParams', '$q', '$modal', 
    '$window', 'egCore', 'patronSvc', 'patronRegSvc', 'egUnloadPrompt'];

