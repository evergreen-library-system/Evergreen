/**
 * Checkin, checkout, and renew
 */

angular.module('egCoreMod')

.factory('egCirc',

       ['$uibModal','$q','egCore','egAlertDialog','egConfirmDialog','egAddCopyAlertDialog','egCopyAlertManagerDialog','egCopyAlertEditorDialog',
        'egWorkLog',
function($uibModal , $q , egCore , egAlertDialog , egConfirmDialog,  egAddCopyAlertDialog , egCopyAlertManagerDialog,  egCopyAlertEditorDialog ,
         egWorkLog) {

    var service = {
        // auto-override these events after the first override
        auto_override_circ_events : {},
        // auto-skip these events after the first skip
        auto_skip_circ_events : {},
        require_initials : false,
        never_auto_print : {
            hold_shelf_slip : false,
            hold_transit_slip : false,
            transit_slip : false
        },
        in_flight_checkins: {}
    };

    egCore.startup.go().finally(function() {
        egCore.org.settings([
            'ui.staff.require_initials.patron_standing_penalty',
            'ui.admin.work_log.max_entries',
            'ui.admin.patron_log.max_entries',
            'circ.staff_client.do_not_auto_attempt_print',
            'circ.clear_hold_on_checkout'
        ]).then(function(set) {
            service.require_initials = Boolean(set['ui.staff.require_initials.patron_standing_penalty']);
            service.clearHold = Boolean(set['circ.clear_hold_on_checkout']);

            if (angular.isArray(set['circ.staff_client.do_not_auto_attempt_print'])) {
                if (set['circ.staff_client.do_not_auto_attempt_print'].indexOf('Hold Slip') > 1)
                    service.never_auto_print['hold_shelf_slip'] = true;
                if (set['circ.staff_client.do_not_auto_attempt_print'].indexOf('Hold/Transit Slip') > 1)
                    service.never_auto_print['hold_transit_slip'] = true;
                if (set['circ.staff_client.do_not_auto_attempt_print'].indexOf('Transit Slip') > 1)
                    service.never_auto_print['transit_slip'] = true;
            }
        });
    });

    service.reset = function() {
        service.auto_override_circ_events = {};
        service.auto_skip_circ_events = {};
    }

    // these events cannot be overriden
    service.nonoverridable_events = [
        'ACTION_CIRCULATION_NOT_FOUND',
        'ACTOR_USER_NOT_FOUND',
        'ASSET_COPY_NOT_FOUND',
        'PATRON_INACTIVE',
        'PATRON_CARD_INACTIVE',
        'PATRON_ACCOUNT_EXPIRED',
        'PERM_FAILURE' // should be handled elsewhere
    ]

    // Default to checked for "Automatically override for subsequent items?"
    service.default_auto_override = [
        'PATRON_EXCEEDS_OVERDUE_COUNT',
        'PATRON_BARRED',
        'PATRON_EXCEEDS_LOST_COUNT',
        'PATRON_EXCEEDS_CHECKOUT_COUNT',
        'PATRON_EXCEEDS_FINES',
        'PATRON_EXCEEDS_LONGOVERDUE_COUNT'
    ]

    // these checkin events do not produce alerts when 
    // options.suppress_alerts is in effect.
    service.checkin_suppress_overrides = [
        'COPY_BAD_STATUS',
        'PATRON_BARRED',
        'PATRON_INACTIVE',
        'PATRON_ACCOUNT_EXPIRED',
        'ITEM_DEPOSIT_PAID',
        'CIRC_CLAIMS_RETURNED',
        'COPY_ALERT_MESSAGE',
        'COPY_STATUS_LOST',
        'COPY_STATUS_LOST_AND_PAID',
        'COPY_STATUS_LONG_OVERDUE',
        'COPY_STATUS_MISSING',
        'PATRON_EXCEEDS_FINES'
    ]

    // these events can be overridden by staff during checkin
    service.checkin_overridable_events = 
        service.checkin_suppress_overrides.concat([
        'TRANSIT_CHECKIN_INTERVAL_BLOCK'
    ])

    // Performs a checkout.
    // Returns a promise resolved with the original params and options
    // and the final checkout event (e.g. in the case of override).
    // Rejected if the checkout cannot be completed.
    //
    // params : passed directly as arguments to the server API 
    // options : non-parameter controls.  e.g. "override", "check_barcode"
    service.checkout = function(params, options) {
        if (!options) options = {};
        params.new_copy_alerts = 1;

        console.debug('egCirc.checkout() : ' 
            + js2JSON(params) + ' : ' + js2JSON(options));

        // handle barcode completion
        return service.handle_barcode_completion(params.copy_barcode)
        .then(function(barcode) {
            console.debug('barcode after completion: ' + barcode);
            params.copy_barcode = barcode;

            var promise = options.check_barcode ? 
                service.test_barcode(params.copy_barcode) : $q.when();

            // avoid re-check on override, etc.
            delete options.check_barcode;

            return promise.then(function() {

                var method = 'open-ils.circ.checkout.full';
                if (options.override) method += '.override';

                return egCore.net.request(
                    'open-ils.circ', method, egCore.auth.token(), params

                ).then(function(evt) {

                    if (!angular.isArray(evt)) evt = [evt];

                    if (evt[0].payload && evt[0].payload.auto_renew == 1) {
                        // open circulation found with auto-renew toggle on.
                        console.debug('Auto-renewing item ' + params.copy_barcode);
                        options.auto_renew = true;
                        return service.renew(params, options);
                    }

                    var action = params.noncat ? 'noncat_checkout' : 'checkout';

                    return service.flesh_response_data(action, evt, params, options)
                    .then(function() {
                        return service.handle_checkout_resp(evt, params, options);
                    })
                    .then(function(final_resp) {
                        return service.munge_resp_data(final_resp,action,method)
                    })
                });
            });
        });
    }

    // Performs a renewal.
    // Returns a promise resolved with the original params and options
    // and the final checkout event (e.g. in the case of override)
    // Rejected if the renewal cannot be completed.
    service.renew = function(params, options) {
        if (!options) options = {};
        params.new_copy_alerts = 1;

        console.debug('egCirc.renew() : ' 
            + js2JSON(params) + ' : ' + js2JSON(options));

        // handle barcode completion
        return service.handle_barcode_completion(params.copy_barcode)
        .then(function(barcode) {
            params.copy_barcode = barcode;

            var promise = options.check_barcode ? 
                service.test_barcode(params.copy_barcode) : $q.when();

            // avoid re-check on override, etc.
            delete options.check_barcode;

            return promise.then(function() {

                var method = 'open-ils.circ.renew';
                if (options.override) method += '.override';

                return egCore.net.request(
                    'open-ils.circ', method, egCore.auth.token(), params

                ).then(function(evt) {

                    if (!angular.isArray(evt)) evt = [evt];

                    return service.flesh_response_data(
                        'renew', evt, params, options)
                    .then(function() {
                        return service.handle_renew_resp(evt, params, options);
                    })
                    .then(function(final_resp) {
                        final_resp.auto_renew = options.auto_renew;
                        return service.munge_resp_data(final_resp,'renew',method)
                    })
                });
            });
        });
    }

    // Performs a checkin
    // Returns a promise resolved with the original params and options,
    // plus the final checkin event (e.g. in the case of override).
    // Rejected if the checkin cannot be completed.
    service.checkin = function(params, options) {
        if (!options) options = {};
        params.new_copy_alerts = 1;

        console.debug('egCirc.checkin() : ' 
            + js2JSON(params) + ' : ' + js2JSON(options));

        // handle barcode completion
        return service.handle_barcode_completion(params.copy_barcode)
        .then(function(barcode) {
            params.copy_barcode = barcode;

            var promise = options.check_barcode ? 
                service.test_barcode(params.copy_barcode) : $q.when();

            // avoid re-check on override, etc.
            delete options.check_barcode;

            return promise.then(function() {

                var method = 'open-ils.circ.checkin';
                if (options.override) method += '.override';

                // Multiple checkin API calls should never be active
                // for a single barcode.
                if (service.in_flight_checkins[barcode]) {
                    console.error('Barcode ' + barcode 
                        + ' is already in flight for checkin, skipping');
                    return $q.reject();
                }
                service.in_flight_checkins[barcode] = true;

                return egCore.net.request(
                    'open-ils.circ', method, egCore.auth.token(), params

                ).then(function(evt) {
                    delete service.in_flight_checkins[barcode];

                    if (!angular.isArray(evt)) evt = [evt];
                    return service.flesh_response_data(
                        'checkin', evt, params, options)
                    .then(function() {
                        return service.handle_checkin_resp(evt, params, options);
                    })
                    .then(function(final_resp) {
                        return service.munge_resp_data(final_resp,'checkin',method)
                    })
                }, function() {delete service.in_flight_checkins[barcode]});
            });
        });
    }

    // provide consistent formatting of the final response data
    service.munge_resp_data = function(final_resp,worklog_action,worklog_method) {
        var data = final_resp.data = {};

        if (!final_resp.evt[0]) {
            egCore.audio.play('error.unknown.no_event');
            return;
        }

        var payload = final_resp.evt[0].payload;
        if (!payload) {
            egCore.audio.play('error.unknown.no_payload');
            return;
        }

        // retrieve call number affixes prior to sending payload data to the grid
        if (payload.volume && typeof payload.volume.prefix() != 'object') {
            egCore.pcrud.retrieve('acnp',payload.volume.prefix()).then(function(p) {payload.volume.prefix(p)});
        };
        if (payload.volume && typeof payload.volume.suffix() != 'object') {
            egCore.pcrud.retrieve('acns',payload.volume.suffix()).then(function(s) {payload.volume.suffix(s)});
        };

        data.circ = payload.circ;
        data.parent_circ = payload.parent_circ;
        data.hold = payload.hold;
        data.record = payload.record;
        data.acp = payload.copy;
        data.acn = payload.volume ?  payload.volume : payload.copy ? payload.copy.call_number() : null;
        data.au = payload.patron;
        data.transit = payload.transit;
        data.status = payload.status;
        data.message = payload.message;
        data.title = final_resp.evt[0].title;
        data.author = final_resp.evt[0].author;
        data.isbn = final_resp.evt[0].isbn;
        data.route_to = final_resp.evt[0].route_to;


        if (payload.circ) data.duration = payload.circ.duration();
        if (payload.circ) data.circ_lib = payload.circ.circ_lib();

        // for checkin, the mbts lives on the main circ
        if (payload.circ && payload.circ.billable_transaction())
            data.mbts = payload.circ.billable_transaction().summary();

        // on renewals, the mbts lives on the parent circ
        if (payload.parent_circ && payload.parent_circ.billable_transaction())
            data.mbts = payload.parent_circ.billable_transaction().summary();

        if (!data.route_to) {
            if (data.transit && !data.transit.dest_recv_time() && !data.transit.cancel_time()) {
                data.route_to = data.transit.dest().shortname();
            } else if (data.acp) {
                data.route_to = data.acp.location().name();
            }
        }
        // allow us to get at the monograph parts associated with a copy
        if (payload.copy && payload.copy.parts()) {
            data._monograph_part = payload.copy.parts().map(function(part) {
                return part.label();
            }).join(',');
        }

        egWorkLog.record(
            (worklog_action == 'checkout' || worklog_action == 'noncat_checkout')
            ? egCore.strings.EG_WORK_LOG_CHECKOUT
            : (worklog_action == 'renew'
                ? egCore.strings.EG_WORK_LOG_RENEW
                : egCore.strings.EG_WORK_LOG_CHECKIN // worklog_action == 'checkin'
            ),{
                'action' : worklog_action,
                'method' : worklog_method,
                'response' : final_resp
            }
        );

        return final_resp;
    }

    service.handle_overridable_checkout_event = function(evt, params, options) {

        if (options.override) {
            // override attempt already made and failed.
            // NOTE: I don't think we'll ever get here, since the
            // override attempt should produce a perm failure...
            angular.forEach(evt, function(e){ console.debug('override failed: ' + e.textcode); });
            return $q.reject();

        } 

        if (evt.filter(function(e){return !service.auto_override_circ_events[e.textcode];}).length == 0) {
            // user has already opted to override these type
            // of events.  Re-run the checkout w/ override.
            options.override = true;
            return service.checkout(params, options);
        } 

        // Ask the user if they would like to override this event.
        // Some events offer a stock override dialog, while others
        // require additional context.

        switch(evt[0].textcode) {
            case 'COPY_NOT_AVAILABLE':
                return service.copy_not_avail_dialog(evt, params, options);
            case 'COPY_ALERT_MESSAGE':
                return service.copy_alert_dialog(evt[0], params, options, 'checkout');
            default: 
                return service.override_dialog(evt, params, options, 'checkout');
        }
    }

    service.handle_overridable_renew_event = function(evt, params, options) {

        if (options.override) {
            // override attempt already made and failed.
            // NOTE: I don't think we'll ever get here, since the
            // override attempt should produce a perm failure...
            angular.forEach(evt, function(e){ console.debug('override failed: ' + e.textcode); });
            return $q.reject();

        } 

        // renewal auto-overrides are the same as checkout
        if (evt.filter(function(e){return !service.auto_override_circ_events[e.textcode];}).length == 0) {
            // user has already opted to override these type
            // of events.  Re-run the renew w/ override.
            options.override = true;
            return service.renew(params, options);
        } 

        // Ask the user if they would like to override this event.
        // Some events offer a stock override dialog, while others
        // require additional context.

        switch(evt[0].textcode) {
            case 'COPY_ALERT_MESSAGE':
                return service.copy_alert_dialog(evt[0], params, options, 'renew');
            default: 
                return service.override_dialog(evt, params, options, 'renew');
        }
    }


    service.handle_overridable_checkin_event = function(evt, params, options) {

        if (options.override) {
            // override attempt already made and failed.
            // NOTE: I don't think we'll ever get here, since the
            // override attempt should produce a perm failure...
            angular.forEach(evt, function(e){ console.debug('override failed: ' + e.textcode); });
            return $q.reject();

        } 

        if (options.suppress_popups
            && evt.filter(function(e){return service.checkin_suppress_overrides.indexOf(e.textcode) == -1;}).length == 0) {
            // Events are suppressed.  Re-run the checkin w/ override.
            options.override = true;
            return service.checkin(params, options);
        } 

        // Ask the user if they would like to override this event.
        // Some events offer a stock override dialog, while others
        // require additional context.

        switch(evt[0].textcode) {
            case 'COPY_ALERT_MESSAGE':
                return service.copy_alert_dialog(evt[0], params, options, 'checkin');
            default: 
                return service.override_dialog(evt, params, options, 'checkin');
        }
    }


    service.handle_renew_resp = function(evt, params, options) {

        var final_resp = {evt : evt, params : params, options : options};

        // track the barcode regardless of whether it refers to a copy
        angular.forEach(evt, function(e){ e.copy_barcode = params.copy_barcode; });

        // test for success first to simplify things
        if (evt[0].textcode == 'SUCCESS') {
            egCore.audio.play('info.renew');
            return $q.when(final_resp);
        }

        // handle Overridable and Non-Overridable Events, but only if no skipped non-overridable events
        if (evt.filter(function(e){return service.auto_skip_circ_events[e.textcode];}).length == 0) {
            return service.handle_overridable_renew_event(evt, params, options);
        }

        // Other events
        switch (evt[0].textcode) {
            case 'COPY_IN_TRANSIT':
            case 'PATRON_CARD_INACTIVE':
            case 'PATRON_INACTIVE':
            case 'PATRON_ACCOUNT_EXPIRED':
            case 'CIRC_CLAIMS_RETURNED':
            case 'ITEM_NOT_CATALOGED':
            case 'ASSET_COPY_NOT_FOUND':
                // since handle_overridable_renew_event essentially advertises these events at some point,
                // we no longer need the original alerts; however, the sound effects are still nice.
                egCore.audio.play('warning.renew');
                return $q.reject();

            default:
                egCore.audio.play('warning.renew.unknown');
                return service.exit_alert(
                    egCore.strings.CHECKOUT_FAILED_GENERIC, {
                        barcode : params.copy_barcode,
                        textcode : evt[0].textcode,
                        desc : evt[0].desc
                    }
                );
        }
    }


    service.handle_checkout_resp = function(evt, params, options) {

        var final_resp = {evt : evt, params : params, options : options};

        // track the barcode regardless of whether it refers to a copy
        angular.forEach(evt, function(e){ e.copy_barcode = params.copy_barcode; });

        // test for success first to simplify things
        if (evt[0].textcode == 'SUCCESS') {
            egCore.audio.play('success.checkout');
            return $q.when(final_resp);
        }

        // other events that should precede generic overridable/non-overridable handling
        switch (evt[0].textcode) {
            case 'ITEM_NOT_CATALOGED':
                egCore.audio.play('error.checkout.no_cataloged');
                return service.precat_dialog(params, options);

            case 'OPEN_CIRCULATION_EXISTS':
                // auto_renew checked in service.checkout()
                egCore.audio.play('error.checkout.open_circ');
                return service.circ_exists_dialog(evt, params, options);

            case 'COPY_IN_TRANSIT':
                egCore.audio.play('warning.checkout.in_transit');
                return service.copy_in_transit_dialog(evt, params, options);
        }

        // handle Overridable and Non-Overridable Events, but only if no skipped non-overridable events
        if (evt.filter(function(e){return service.auto_skip_circ_events[e.textcode];}).length == 0) {
            return service.handle_overridable_checkout_event(evt, params, options);
        }

        // Other events
        switch (evt[0].textcode) {
            case 'PATRON_CARD_INACTIVE':
            case 'PATRON_INACTIVE':
            case 'PATRON_ACCOUNT_EXPIRED':
            case 'CIRC_CLAIMS_RETURNED':
            case 'ITEM_NOT_CATALOGED':
            case 'ASSET_COPY_NOT_FOUND':
                // since handle_overridable_checkout_event essentially advertises these events at some point,
                // we no longer need the original alerts; however, the sound effects are still nice.
                egCore.audio.play('warning.checkout');
                return $q.reject();

            default:
                egCore.audio.play('error.checkout.unknown');
                return service.exit_alert(
                    egCore.strings.CHECKOUT_FAILED_GENERIC, {
                        barcode : params.copy_barcode,
                        textcode : evt[0].textcode,
                        desc : evt[0].desc
                    }
                );
        }
    }

    // returns a promise resolved with the list of circ mods
    service.get_circ_mods = function() {
        if (egCore.env.ccm) 
            return $q.when(egCore.env.ccm.list);

        return egCore.pcrud.retrieveAll('ccm', null, {atomic : true})
        .then(function(list) { 
            egCore.env.absorbList(list, 'ccm');
            return list;
        });
    };

    // returns a promise resolved with the list of noncat types
    service.get_noncat_types = function() {
        if (egCore.env.cnct) 
            return $q.when(egCore.env.cnct.list);

        return egCore.pcrud.search('cnct', 
            {owning_lib : 
                egCore.org.fullPath(egCore.auth.user().ws_ou(), true)}, 
            null, {atomic : true}
        ).then(function(list) { 
            egCore.env.absorbList(list, 'cnct');
            return list;
        });
    }

    service.get_all_penalty_types = function() {
        if (egCore.env.csp) 
            return $q.when(egCore.env.csp.list);
        return egCore.pcrud.retrieveAll('csp', {}, {atomic : true}).then(
            function(penalties) {
                return egCore.env.absorbList(penalties, 'csp').list;
            }
        );
    }

    // ideally all of these data should be returned with the response,
    // but until then, grab what we need.
    service.flesh_response_data = function(action, evt, params, options) {
        var promises = [];
        var payload;
        if (!evt[0] || !(payload = evt[0].payload)) return $q.when();
        
        promises.push(service.flesh_copy_location(payload.copy));
        if (payload.copy) {
            promises.push(service.flesh_acn_owning_lib(payload.volume));
            promises.push(service.flesh_copy_circ_library(payload.copy));
            promises.push(service.flesh_copy_circ_modifier(payload.copy));
            promises.push(
                service.flesh_copy_status(payload.copy)

                .then(function() {
                    // copy is in transit, but no transit was delivered
                    // in the payload.  Do this here instead of below to
                    // ensure consistent copy status fleshiness
                    if (!payload.transit && payload.copy.status().id() == 6) { // in-transit
                        return service.find_copy_transit(evt, params, options)
                        .then(function(trans) {
                            if (trans) {
                                trans.source(egCore.org.get(trans.source()));
                                trans.dest(egCore.org.get(trans.dest()));
                                payload.transit = trans;
                            }
                        })
                    }
                })
            );
        }

        // local flesh transit
        if (transit = payload.transit) {
            transit.source(egCore.org.get(transit.source()));
            transit.dest(egCore.org.get(transit.dest()));
        } 

        // TODO: renewal responses should include the patron
        if (!payload.patron) {
            var user_id;
            if (payload.circ) user_id = payload.circ.usr();
            if (payload.noncat_circ) user_id = payload.noncat_circ.patron();
            if (user_id) {
                promises.push(
                    egCore.pcrud.retrieve('au', user_id)
                    .then(function(user) {payload.patron = user})
                );
            }
        }

        // extract precat values
        angular.forEach(evt, function(e){ e.title = payload.record ? payload.record.title() : 
            (payload.copy ? payload.copy.dummy_title() : null);});

        angular.forEach(evt, function(e){ e.author = payload.record ? payload.record.author() : 
            (payload.copy ? payload.copy.dummy_author() : null);});

        angular.forEach(evt, function(e){ e.isbn = payload.record ? payload.record.isbn() : 
            (payload.copy ? payload.copy.dummy_isbn() : null);});

        return $q.all(promises);
    }

    service.flesh_acn_owning_lib = function(acn) {
        if (!acn) return $q.when();
        return $q.when(acn.owning_lib(egCore.org.get( acn.owning_lib() )));
    }

    service.flesh_copy_circ_library = function(copy) {
        if (!copy) return $q.when();
        
        return $q.when(copy.circ_lib(egCore.org.get( copy.circ_lib() )));
    }

    // fetches the full list of circ modifiers
    service.flesh_copy_circ_modifier = function(copy) {
        if (!copy) return $q.when();
        if (egCore.env.ccm)
            return $q.when(copy.circ_modifier(egCore.env.ccm.map[copy.circ_modifier()]));
        return egCore.pcrud.retrieveAll('ccm', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'ccm');
                copy.circ_modifier(egCore.env.ccm.map[copy.circ_modifier()]);
            }
        );
    }

    // fetches the full list of copy statuses
    service.flesh_copy_status = function(copy) {
        if (!copy) return $q.when();
        if (egCore.env.ccs) 
            return $q.when(copy.status(egCore.env.ccs.map[copy.status()]));
        return egCore.pcrud.retrieveAll('ccs', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'ccs');
                copy.status(egCore.env.ccs.map[copy.status()]);
            }
        );
    }

    // there may be *many* copy locations and we may be handling items
    // for other locations.  Fetch copy locations as-needed and cache.
    service.flesh_copy_location = function(copy) {
        if (!copy) return $q.when();
        if (angular.isObject(copy.location())) return $q.when(copy);
        if (egCore.env.acpl) {
            if (egCore.env.acpl.map[copy.location()]) {
                copy.location(egCore.env.acpl.map[copy.location()]);
                return $q.when(copy);
            }
        } 
        return egCore.pcrud.retrieve('acpl', copy.location())
        .then(function(loc) {
            egCore.env.absorbList([loc], 'acpl'); // append to cache
            copy.location(loc);
            return copy;
        });
    }


    // fetch org unit addresses as needed.
    service.get_org_addr = function(org_id, addr_type) {
        var org = egCore.org.get(org_id);
        var addr_id = org[addr_type]();

        if (!addr_id) return $q.when(null);

        if (egCore.env.aoa && egCore.env.aoa.map[addr_id]) 
            return $q.when(egCore.env.aoa.map[addr_id]); 

        return egCore.pcrud.retrieve('aoa', addr_id).then(function(addr) {
            egCore.env.absorbList([addr], 'aoa');
            return egCore.env.aoa.map[addr_id]; 
        });
    }
    
    //retrieve addresses from multiple org units
    service.cache_org_addr = function (org_ids, addr_type) {
        var addr_ids = [];
        org_ids.forEach(function(org_id){
            var org = egCore.org.get(org_id);
            var addr_id = org[addr_type](); 
            if(addr_id)addr_ids.push(addr_id);
        });
		if (!addr_ids.length) return $q.when(null);
        return egCore.pcrud.search('aoa', {id: addr_ids},{},{ atomic: true}).then(function(addrs) {
            return egCore.env.absorbList(addrs, 'aoa');
        });
    }

    service.exit_alert = function(msg, scope) {
        return egAlertDialog.open(msg, scope).result.then(
            function() {return $q.reject()});
    }

    // opens a dialog asking the user if they would like to override
    // the returned event.
    service.override_dialog = function(evt, params, options, action) {
        if (!angular.isArray(evt)) evt = [evt];

        egCore.audio.play('warning.circ.event_override');
        var copy_alert = evt.filter(function(e) {
            return e.textcode == 'COPY_ALERT_MESSAGE';
        });
        evt = evt.filter(function(e) {
            return e.textcode !== 'COPY_ALERT_MESSAGE';
        });

        return $uibModal.open({
            templateUrl: './circ/share/t_event_override_dialog',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', 
                function($scope, $uibModalInstance) {
                $scope.events = evt;
                $scope.action = action;

                // Find the event, if any, that is for ITEM_ON_HOLDS_SHELF
                //  and grab the patron name of the owner. 
                $scope.holdEvent = evt.filter(function(e) {
                    return e.textcode === 'ITEM_ON_HOLDS_SHELF'
                });

                if ($scope.holdEvent.length > 0) {
                    // Ensure we have a scalar here
                    if (angular.isArray($scope.holdEvent)) {
                        $scope.holdEvent = $scope.holdEvent[0];
                    }

                    $scope.patronName = $scope.holdEvent.payload.patron_name;
                    $scope.holdID = $scope.holdEvent.payload.hold_id;
                    $scope.patronID = $scope.holdEvent.payload.patron_id;
                }

                $scope.copy_barcode = params.copy_barcode; // may be null

                // Implementation note: Why not use a primitive here? It
                // doesn't work.  See: 
                // http://stackoverflow.com/questions/18642371/checkbox-not-binding-to-scope-in-angularjs
                $scope.formdata = {
                    clearHold : service.clearHold,
                    nonoverridable: evt.filter(function(e){
                        return service.nonoverridable_events.indexOf(e.textcode) > -1;}).length > 0,
                    event_ui_data : Object.fromEntries(
                        evt.map( e => [ e.ilsevent, {
                            // non-overridable events will be rare, but they are skippable.  We use
                            // the same checkbox variable to track desired skip and auto-override
                            // selections.
                            overridable: service.nonoverridable_events.indexOf(e.textcode) == -1,
                            // for non-overridable events, we'll default the checkbox to any previous
                            // choice made for the current patron, though normally the UI will be
                            // suppressed unless some previously unencountered events are in the set
                            checkbox: service.nonoverridable_events.indexOf(e.textcode) > -1
                            ? (service.auto_skip_circ_events[e.textcode] == undefined
                                ? false
                                : service.auto_skip_circ_events[e.textcode]
                            )
                            // if a given event is overridable, said checkbox will default to any previous
                            // choice made for the current patron, as long as there are no non-overridable
                            // events in the set (because we'll disable the checkbox in that case and don't
                            // want to imply that we're going to set an auto-override)
                            : (service.auto_override_circ_events[e.textcode] == undefined
                                ? (
                                    service.nonoverridable_events.indexOf(e.textcode) > -1
                                    ? false
                                    : service.default_auto_override.indexOf(e.textcode) > -1
                                )
                                : service.auto_override_circ_events[e.textcode]
                            )
                        }])
                    ) 
                };

                function update_auto_override_and_skip_lists() {
                    angular.forEach(evt, function(e){
                        if ($scope.formdata.nonoverridable) {
                            // the action had at least one non-overridable event, so let's only
                            // record skip choices for those
                            if (!$scope.formdata.event_ui_data[e.ilsevent].overridable) {
                                if ($scope.formdata.event_ui_data[e.ilsevent].checkbox) {
                                    // grow the skip list
                                    service.auto_skip_circ_events[e.textcode] = true;
                                } else {
                                    // shrink the skip list
                                    service.auto_skip_circ_events[e.textcode] = false;
                                }
                            }
                        } else {
                            // record all auto-override choices
                            if ($scope.formdata.event_ui_data[e.ilsevent].checkbox) {
                                // grow the auto-override list
                                service.auto_override_circ_events[e.textcode] = true;
                            } else {
                                // shrink the auto-override list
                                service.auto_override_circ_events[e.textcode] = false;
                            }
                        }
                    });
                    // for debugging
                    window.oils_auto_skip_circ_events = service.auto_skip_circ_events;
                    window.oils_auto_override_circ_events = service.auto_override_circ_events;
                }

                $scope.ok = function() { 
                    update_auto_override_and_skip_lists();
                    // Handle the cancellation of the assciated hold here
                    if ($scope.formdata.clearHold && $scope.holdID) {
                        egCore.net.request(
                            'open-ils.circ',
                            'open-ils.circ.hold.cancel',
                            egCore.auth.token(), $scope.holdID,
                            5, // staff forced
                            'Item checked out by other patron' // FIXME I18n
                        ).then(function(resp) {
                            if (evt = egCore.evt.parse(resp)) {
                                egCore.audio.play(
                                    'warning.hold.cancel_failed');
                                console.error('unable to cancel hold: ' 
                                    + evt.toString());
                            } else {
                                egCore.net.request(
                                    'open-ils.circ', 'open-ils.circ.hold.details.retrieve',
                                    egCore.auth.token(), $scope.holdID, {
                                        'suppress_notices': true,
                                        'suppress_transits': true,
                                        'suppress_mvr' : true,
                                        'include_usr' : true
                                }).then(function(details) {
                                    //console.log('details', details);
                                    egWorkLog.record(
                                        egCore.strings.EG_WORK_LOG_CANCELED_HOLD
                                        ,{
                                            'action' : 'canceled_hold',
                                            'method' : 'open-ils.circ.hold.cancel',
                                            'hold_id' : $scope.holdID,
                                            'patron_id' : details.hold.usr().id(),
                                            'user' : details.patron_last,
                                            'item' : details.copy ? details.copy.barcode() : null,
                                            'item_id' : details.copy ? details.copy.id() : null
                                        }
                                    );
                                });
                            }
                        });
                    }
                    $uibModalInstance.close();
                }

                $scope.skip = function($event) {
                    update_auto_override_and_skip_lists();
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }

                $scope.cancel = function ($event) { 
                    window.oils_cancel_batch = true;
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        }).result.then(
            function() {
                options.override = true;

                if (copy_alert.length > 0) {
                    return service.copy_alert_dialog(copy_alert, params, options, action);
                }

                if (action == 'checkin') {
                    return service.checkin(params, options);
                }

                return service[action](params, options);
            }
        );
    }

    service.copy_not_avail_dialog = function(evt, params, options) {
        if (!angular.isArray(evt)) evt = [evt];

        var copy_alert = evt.filter(function(e) {
            return e.textcode == 'COPY_ALERT_MESSAGE';
        });
        evt = evt.filter(function(e) {
            return e.textcode !== 'COPY_ALERT_MESSAGE';
        });
        evt = evt[0];

        return $uibModal.open({
            templateUrl: './circ/share/t_copy_not_avail_dialog',
            backdrop: 'static',
            controller: 
                       ['$scope','$uibModalInstance','copyStatus',
                function($scope , $uibModalInstance , copyStatus) {
                $scope.copyStatus = copyStatus;
                $scope.ok = function() {$uibModalInstance.close()}
                $scope.cancel = function() {$uibModalInstance.dismiss()}
            }],
            resolve : {
                copyStatus : function() {
                    return egCore.pcrud.retrieve(
                        'ccs', evt.payload.status());
                }
            }
        }).result.then(
            function() {
                options.override = true;

                if (copy_alert.length > 0) {
                    return service.copy_alert_dialog(copy_alert, params, options, 'checkout');
                }

                return service.checkout(params, options);
            }
        );
    }

    // Opens a dialog allowing the user to fill in the desired non-cat count.
    // Unlike other dialogs, which kickoff circ actions internally
    // as a result of events, this dialog does not kick off any circ
    // actions. It just collects the count and and resolves the promise.
    //
    // This assumes the caller has already handled the noncat-type
    // selection and just needs to collect the count info.
    service.noncat_dialog = function(params, options) {
        var noncatMax = 99; // hard-coded max
        
        // the caller should presumably have fetched the noncat_types via
        // our API already, but fetch them again (from cache) to be safe.
        return service.get_noncat_types().then(function() {

            params.noncat = true;
            var type = egCore.env.cnct.map[params.noncat_type];

            return $uibModal.open({
                templateUrl: './circ/share/t_noncat_dialog',
                backdrop: 'static',
                controller: 
                    ['$scope', '$uibModalInstance',
                    function($scope, $uibModalInstance) {
                    $scope.focusMe = true;
                    $scope.type = type;
                    $scope.count = 1;
                    $scope.noncatMax = noncatMax;
                    $scope.ok = function(count) { $uibModalInstance.close(count) }
                    $scope.cancel = function ($event) { 
                        $uibModalInstance.dismiss() 
                        $event.preventDefault();
                    }
                }],
            }).result.then(
                function(count) {
                    if (count && count > 0 && count <= noncatMax) { 
                        // NOTE: in Chrome, form validation ensure a valid number
                        params.noncat_count = count;
                        return $q.when(params);
                    } else {
                        return $q.reject();
                    }
                }
            );
        });
    }

    // Opens a dialog allowing the user to fill in pre-cat copy info.
    service.precat_dialog = function(params, options) {

        return $uibModal.open({
            templateUrl: './circ/share/t_precat_dialog',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', 'circMods', 'has_precat_perm',
                function($scope, $uibModalInstance, circMods, has_precat_perm) {
                $scope.focusMe = true;
                $scope.precatArgs = {
                    copy_barcode : params.copy_barcode
                };

                $scope.can_create_precats = has_precat_perm;
                $scope.circModifiers = circMods;
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }

                // use this function as a keydown handler on form
                // elements that should not submit the form on enter.
                $scope.preventSubmit = function($event) {
                    if ($event.keyCode == 13)
                        $event.preventDefault();
                }
            }],
            resolve : {
                circMods : function() { return service.get_circ_mods(); },
                has_precat_perm : function(){ return egCore.perm.hasPermHere('CREATE_PRECAT'); }
            }
        }).result.then(
            function(args) {
                if (!args || !args.dummy_title) return $q.reject();
                if(args.circ_modifier == "") args.circ_modifier = null;
                angular.forEach(args, function(val, key) {params[key] = val});
                params.precat = true;
                return service.checkout(params, options);
            }
        );
    }

    // find the open transit for the given copy barcode; flesh the org
    // units locally.
    service.find_copy_transit = function(evt, params, options) {
        if (angular.isArray(evt)) evt = evt[0];

        // NOTE: evt.payload.transit may exist, but it's not necessarily
        // the transit we want, since a transit close + open in the API
        // returns the closed transit.

         return egCore.pcrud.search('atc',
            {   dest_recv_time : null, cancel_time : null},
            {   flesh : 1, 
                flesh_fields : {atc : ['target_copy']},
                join : {
                    acp : {
                        filter : {
                            barcode : params.copy_barcode,
                            deleted : 'f'
                        }
                    }
                },
                limit : 1,
                order_by : {atc : 'source_send_time desc'}, 
            }, {authoritative : true}
        ).then(function(transit) {
            transit.source(egCore.org.get(transit.source()));
            transit.dest(egCore.org.get(transit.dest()));
            return transit;
        });
    }

    service.copy_in_transit_dialog = function(evt, params, options) {
        if (angular.isArray(evt)) evt = evt[0];
        return $uibModal.open({
            templateUrl: './circ/share/t_copy_in_transit_dialog',
            backdrop: 'static',
            controller: 
                       ['$scope','$uibModalInstance','transit',
                function($scope , $uibModalInstance , transit) {
                $scope.transit = transit;
                $scope.ok = function() { $uibModalInstance.close(transit) }
                $scope.cancel = function() { $uibModalInstance.dismiss() }
            }],
            resolve : {
                // fetch the conflicting open transit w/ fleshed copy
                transit : function() {
                    return service.find_copy_transit(evt, params, options);
                }
            }
        }).result.then(
            function(transit) {
                // user chose to abort the transit then checkout
                return service.abort_transit(transit.id())
                .then(function() {
                    return service.checkout(params, options);
                });
            }
        );
    }

    service.abort_transit = function(transit_id) {
        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.transit.abort',
            egCore.auth.token(), {transitid : transit_id}
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                alert(evt);
                return $q.reject();
            }
            return $q.when();
        });
    }

    service.last_copy_circ = function(copy_id) {
        return egCore.pcrud.search('circ', 
            {target_copy : copy_id},
            {order_by : {circ : 'xact_start desc' }, limit : 1}
        );
    }

    service.circ_exists_dialog = function(evt, params, options) {
        if (angular.isArray(evt)) evt = evt[0];

        if (!evt.payload.old_circ) {
            return egCore.net.request(
                'open-ils.search',
                'open-ils.search.asset.copy.fleshed2.find_by_barcode',
                params.copy_barcode
            ).then(function(resp){
                console.log(resp);
                if (egCore.evt.parse(resp)) {
                    console.error(egCore.evt.parse(resp));
                } else {
                    return egCore.net.request(
                         'open-ils.circ',
                         'open-ils.circ.copy_checkout_history.retrieve',
                         egCore.auth.token(), resp.id(), 1
                    ).then( function (circs) {
                        evt.payload.old_circ = circs[0];
                        return service.circ_exists_dialog_impl( evt, params, options );
                    });
                }
            });
        } else {
            return service.circ_exists_dialog_impl( evt, params, options );
        }
    },

    service.circ_exists_dialog_impl = function (evt, params, options) {

        var openCirc = evt.payload.old_circ;
        var sameUser = openCirc.usr() == params.patron_id;
        
        return $uibModal.open({
            templateUrl: './circ/share/t_circ_exists_dialog',
            backdrop: 'static',
            controller: 
                       ['$scope','$uibModalInstance',
                function($scope , $uibModalInstance) {
                $scope.args = {forgive_fines : false};
                $scope.circDate = openCirc.xact_start();
                $scope.sameUser = sameUser;
                $scope.ok = function() { $uibModalInstance.close($scope.args) }
                $scope.cancel = function($event) { 
                    $uibModalInstance.dismiss();
                    $event.preventDefault(); // form, avoid calling ok();
                }
            }]
        }).result.then(
            function(args) {
                if (sameUser) {
                    params.void_overdues = args.forgive_fines;
                    options.sameCopyCheckout = true;
                    return service.renew(params, options);
                }

                return service.checkin({
                    barcode : params.copy_barcode,
                    noop : true,
                    void_overdues : args.forgive_fines
                }).then(function(checkin_resp) {
                    if (checkin_resp.evt[0].textcode == 'SUCCESS') {
                        return service.checkout(params, options);
                    } else {
                        alert(egCore.evt.parse(checkin_resp.evt[0]));
                        return $q.reject();
                    }
                });
            }
        );
    }

    service.batch_backdate = function(circ_ids, backdate) {
        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.post_checkin_backdate.batch',
            egCore.auth.token(), circ_ids, backdate);
    }

    service.backdate_dialog = function(circ_ids) {
        return $uibModal.open({
            templateUrl: './circ/share/t_backdate_dialog',
            backdrop: 'static',
            controller: 
                       ['$scope','$uibModalInstance',
                function($scope , $uibModalInstance) {

                var today = new Date();
                $scope.dialog = {
                    num_circs : circ_ids.length,
                    num_processed : 0,
                    backdate : today
                }

                $scope.$watch('dialog.backdate', function(newval) {
                    if (newval && newval > today) 
                        $scope.dialog.backdate = today;
                });


                $scope.cancel = function() { 
                    $uibModalInstance.dismiss();
                }

                $scope.ok = function() { 

                    var bd = $scope.dialog.backdate.toISOString().replace(/T.*/,'');
                    service.batch_backdate(circ_ids, bd)
                    .then(
                        function() { // on complete
                            $uibModalInstance.close({backdate : bd});
                        },
                        null,
                        function(resp) { // on response
                            console.debug('backdate returned ' + resp);
                            if (resp == '1') {
                                $scope.num_processed++;
                            } else {
                                console.error(egCore.evt.parse(resp));
                            }
                        }
                    );
                }
            }]
        }).result;
    }

    service.mark_claims_returned = function(barcode, date, override) {

        var method = 'open-ils.circ.circulation.set_claims_returned';
        if (override) method += '.override';

        console.debug('claims returned ' + method);

        return egCore.net.request(
            'open-ils.circ', method, egCore.auth.token(),
            {barcode : barcode, backdate : date})

        .then(function(resp) {

            if (resp == 1) { // success
                console.debug('claims returned succeeded for ' + barcode);
                return barcode;

            } else if (evt = egCore.evt.parse(resp)) {
                console.debug('claims returned failed: ' + evt.toString());

                if (evt.textcode == 'PATRON_EXCEEDS_CLAIMS_RETURN_COUNT') {
                    // TODO check perms before offering override option?

                    if (override) return;// just to be safe

                    return egConfirmDialog.open(
                        egCore.strings.TOO_MANY_CLAIMS_RETURNED, '', {}
                    ).result.then(function() {
                        return service.mark_claims_returned(barcode, date, true);
                    });
                }

                if (evt.textcode == 'PERM_FAILURE') {
                    console.error('claims returned permission denied')
                    // TODO: auth override dialog?
                }
            }
        });
    }

    service.mark_claims_returned_dialog = function(copy_barcodes) {
        if (!copy_barcodes.length) return;

        return $uibModal.open({
            templateUrl: './circ/share/t_mark_claims_returned_dialog',
            backdrop: 'static',
            controller: 
                       ['$scope','$uibModalInstance',
                function($scope , $uibModalInstance) {

                var today = new Date();
                $scope.args = {
                    barcodes : copy_barcodes,
                    date : today
                };

                $scope.$watch('args.date', function(newval) {
                    if (newval && newval > today) 
                        $scope.args.backdate = today;
                });

                $scope.cancel = function() {$uibModalInstance.dismiss()}
                $scope.ok = function() { 

                    var date = $scope.args.date.toISOString().replace(/T.*/,'');

                    var deferred = $q.defer();

                    // serialize the action on each barcode so that the 
                    // caller will never see multiple alerts at the same time.
                    function mark_one() {
                        var bc = copy_barcodes.pop();
                        if (!bc) {
                            deferred.resolve();
                            $uibModalInstance.close();
                            return;
                        }

                        // finally -> continue even when one fails
                        service.mark_claims_returned(bc, date)
                        .finally(function(barcode) {
                            if (barcode) deferred.notify(barcode);
                            mark_one();
                        });
                    }
                    mark_one(); // kick it off
                    return deferred.promise;
                }
            }]
        }).result;
    }

    // serially checks in each barcode with claims_never_checked_out set
    // returns promise, notified on each barcode, resolved after all
    // checkins are complete.
    service.mark_claims_never_checked_out = function(barcodes) {
        if (!barcodes.length) return;

        var deferred = $q.defer();
        egConfirmDialog.open(
            egCore.strings.MARK_NEVER_CHECKED_OUT, '', {barcodes : barcodes}

        ).result.then(function() {
            function mark_one() {
                var bc = barcodes.pop();

                if (!bc) { // all done
                    deferred.resolve();
                    return;
                }

                service.checkin(
                    {claims_never_checked_out : true, copy_barcode : bc})
                .finally(function() { 
                    deferred.notify(bc);
                    mark_one();
                })
            }
            mark_one();
        });

        return deferred.promise;
    }

    service.mark_damaged = function(params) {
        if (!params) return $q.when();
        return $uibModal.open({
            backdrop: 'static',
            templateUrl: './circ/share/t_mark_damaged',
            controller:
                ['$scope', '$uibModalInstance', 'egCore', 'egBilling', 'egItem',
                function($scope, $uibModalInstance, egCore, egBilling, egItem) {
                    var doRefresh = params.refresh;
                    
                    $scope.showBill = params.charge != null && params.circ;
                    $scope.billArgs = {charge: params.charge};
                    $scope.mode = 'charge';
                    $scope.barcode = params.barcode;
                    if (params.circ) {
                        $scope.circ = params.circ;
                        $scope.circ_checkin_time = params.circ.checkin_time();
                        $scope.circ_patron_name = params.circ.usr().family_name() + ", "
                            + params.circ.usr().first_given_name() + " "
                            + params.circ.usr().second_given_name();
                    }
                    egBilling.fetchBillingTypes().then(function(res) {
                        $scope.billingTypes = res;
                    });

                    $scope.btnChargeFees = function() {
                        $scope.mode = 'charge';
                        $scope.billArgs.charge = params.charge;
                    }
                    $scope.btnWaiveFees = function() {
                        $scope.mode = 'waive';
                        $scope.billArgs.charge = 0;
                    }

                    $scope.cancel = function ($event) { 
                        $uibModalInstance.dismiss();
                    }
                    $scope.ok = function() {
                        handle_mark_item_damaged();
                    }

                    var handle_mark_item_damaged = function() {
                        var applyFines;
                        if ($scope.showBill)
                            applyFines = $scope.billArgs.charge ? 'apply' : 'noapply';

                        egCore.net.request(
                            'open-ils.circ',
                            'open-ils.circ.mark_item_damaged',
                            egCore.auth.token(), params.id, {
                                apply_fines: applyFines,
                                override_amount: $scope.billArgs.charge,
                                override_btype: $scope.billArgs.type,
                                override_note: $scope.billArgs.note,
                                handle_checkin: !applyFines
                        }).then(function(resp) {
                            if (evt = egCore.evt.parse(resp)) {
                                doRefresh = false;
                                console.debug("mark damaged more information required. Pushing back.");
                                service.mark_damaged({
                                    id: params.id,
                                    barcode: params.barcode,
                                    charge: evt.payload.charge,
                                    circ: evt.payload.circ,
                                    refresh: params.refresh
                                });
                                console.error('mark damaged failed: ' + evt);
                            }
                        }).then(function() {
                            if (doRefresh) egItem.add_barcode_to_list(params.barcode);
                        });
                        $uibModalInstance.close();
                    }
                }]
        }).result;
    }

    service.handle_mark_item_event = function(copy, status, args, event) {
        var dlogTitle, dlogMessage;
        switch (event.textcode) {
        case 'ITEM_TO_MARK_CHECKED_OUT':
            if (status.id() === 4) {
                // checked out items shouldn't be marked missing
                console.error(
                    'Mark item ' + status.name() + ' for ' +
                    copy.barcode + ' failed: ' + event
                );
                return service.exit_alert(
                    egCore.strings.MARK_MISSING_FAILURE_CHECKED_OUT,
                    {barcode : copy.barcode});
            }
            dlogTitle = egCore.strings.MARK_ITEM_CHECKED_OUT;
            dlogMessage = egCore.strings.MARK_ITEM_CHECKIN_CONTINUE;
            args.handle_checkin = 1;
            break;
        case 'ITEM_TO_MARK_IN_TRANSIT':
            dlogTitle = egCore.strings.MARK_ITEM_IN_TRANSIT;
            dlogMessage = egCore.strings.MARK_ITEM_ABORT_CONTINUE;
            args.handle_transit = 1;
            break;
        case 'ITEM_TO_MARK_LAST_HOLD_COPY':
            dlogTitle = egCore.strings.MARK_ITEM_LAST_HOLD_COPY;
            dlogMessage = egCore.strings.MARK_ITEM_CONTINUE;
            args.handle_last_hold_copy = 1;
            break;
        case 'COPY_DELETE_WARNING':
            dlogTitle = egCore.strings.MARK_ITEM_RESTRICT_DELETE;
            dlogMessage = egCore.strings.MARK_ITEM_CONTINUE;
            args.handle_copy_delete_warning = 1;
            break;
        case 'PERM_FAILURE':
            console.error('Mark item ' + status.name() + ' for ' + copy.barcode + ' failed: ' +
                          event);
            return service.exit_alert(egCore.strings.PERMISSION_DENIED,
                                      {permission : event.ilsperm});
            break;
        default:
            console.error('Mark item ' + status.name() + ' for ' + copy.barcode + ' failed: ' +
                          event);
            return service.exit_alert(egCore.strings.MARK_ITEM_FAILURE,
                                      {status : status.name(), barcode : copy.barcode,
                                       textcode : event.textcode});
            break;
        }
        return egConfirmDialog.open(
            dlogTitle, dlogMessage,
            {
                barcode : copy.barcode,
                status : status.name(),
                ok : function () {},
                cancel : function () {}
            }
        ).result.then(function() {
            return service.mark_item(copy, status, args);
        });
    }

    service.mark_item = function(copy, markstatus, args) {
        if (!copy) return $q.when();

        // If any new back end mark_item calls are added, also add
        // them here to use them from the staff client.
        // TODO: I didn't find any JS constants for copy status.
        var req;
        switch (markstatus.id()) {
        case 2:
            // Not implemented in the staff client, yet.
            // req = "open-ils.circ.mark_item_bindery";
            break;
        case 4:
            req = "open-ils.circ.mark_item_missing";
            break;
        case 9:
            // Not implemented in the staff client, yet.
            // req = "open-ils.circ.mark_item_on_order";
            break;
        case 10:
            // Not implemented in the staff client, yet.
            // req = "open-ils.circ.mark_item_ill";
            break;
        case 11:
            // Not implemented in the staff client, yet.
            // req = "open-ils.circ.mark_item_cataloging";
            break;
        case 12:
            // Not implemented in the staff client, yet.
            // req = "open-ils.circ.mark_item_reserves";
            break;
        case 13:
            req = "open-ils.circ.mark_item_discard";
            break;
        case 14:
            // Damaged is for handling of events. It's main handler is elsewhere.
            req = "open-ils.circ.mark_item_damaged";
            break;
        }

        return egCore.net.request(
            'open-ils.circ',
            req,
            egCore.auth.token(),
            copy.id,
            args
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                return service.handle_mark_item_event(copy, markstatus, args, evt);
            }
        });
    }

    service.mark_discard = function(copies) {
        return egConfirmDialog.open(
            egCore.strings.MARK_DISCARD_CONFIRM, '',
            {
                num_items : copies.length,
                ok : function() {},
                cancel : function() {}
            }
        ).result.then(function() {
            return egCore.pcrud.retrieve('ccs', 13)
                .then(function(resp) {
                    var promises = [];
                    angular.forEach(copies, function(copy) {
                        promises.push(service.mark_item(copy, resp, {}))
                    });
                    return $q.all(promises);
                });
        });
    }

    service.mark_missing = function(copies) {
        return egConfirmDialog.open(
            egCore.strings.MARK_MISSING_CONFIRM, '',
            {
                num_items : copies.length,
                ok : function() {},
                cancel : function() {}
            }
        ).result.then(function() {
            return egCore.pcrud.retrieve('ccs', 4)
                .then(function(resp) {
                    var modified = [];
                    var promise = $q.when();
                    angular.forEach(copies, function(copy) {
                        promise = promise.then(function() {
                            return service.mark_item(
                                copy, resp, {}
                            ).then(function() {
                                modified.push(copy.barcode);
                            }).catch(function(){});
                        });
                    });
                    promise = promise.then(function() {
                        if (!modified.length) return $q.reject();
                        return modified;
                    });
                    return promise;
                });
        });
    }



    // Mark circulations as lost via copy barcode.  As each item is 
    // processed, the returned promise is notified of the barcode.
    // No confirmation dialog is presented.
    service.mark_lost = function(copy_barcodes) {
        var deferred = $q.defer();
        var promises = [];

        angular.forEach(copy_barcodes, function(barcode) {
            promises.push(
                egCore.net.request(
                    'open-ils.circ',
                    'open-ils.circ.circulation.set_lost',
                    egCore.auth.token(), {barcode : barcode}
                ).then(function(resp) {
                    if (evt = egCore.evt.parse(resp)) {
                        console.error("Mark lost failed: " + evt.toString());
                        return;
                    }
                    // inform the caller as each item is processed
                    deferred.notify(barcode);
                })
            );
        });

        $q.all(promises).then(function() {deferred.resolve()});
        return deferred.promise;
    }

    service.abort_transits = function(transit_ids) {
        return egConfirmDialog.open(
            egCore.strings.ABORT_TRANSIT_CONFIRM, '',
            {   num_transits : transit_ids.length,
                ok : function() {},
                cancel : function() {}
            }

        ).result.then(function() {
            var promises = [];
            angular.forEach(transit_ids, function(transit_id) {
                promises.push(
                    egCore.net.request(
                        'open-ils.circ',
                        'open-ils.circ.transit.abort',
                        egCore.auth.token(), {transitid : transit_id}
                    ).then(function(resp) {
                        if (evt = egCore.evt.parse(resp)) {
                            console.error('abort transit failed: ' + evt);
                        }
                    })
                );
            });

            return $q.all(promises);
        });
    }

    service.add_copy_alerts = function(item_ids) {
        // Instead of opening modal, open new tab with Angular route
        const copyIds = item_ids.join(',');
        window.open(`/eg2/staff/cat/item/alerts?copyIds=${copyIds}`, '_blank');
    }

    service.manage_copy_alerts = function(item_ids) {
        // Instead of opening modal, open new tab with Angular route
        const copyIds = item_ids.join(',');
        window.open(`/eg2/staff/cat/item/alerts?copyIds=${copyIds}`, '_blank');
    }

    // alert when copy location alert_message is set.
    // This does not affect processing, it only produces a click-through
    service.handle_checkin_loc_alert = function(evt, params, options) {
        if (angular.isArray(evt)) evt = evt[0];

        var copy = evt && evt.payload ? evt.payload.copy : null;

        if (copy && !options.suppress_popups
            && copy.location().checkin_alert() == 't') {

            return egAlertDialog.open(
                egCore.strings.LOCATION_ALERT_MSG, {copy : copy}).result;
        }

        return $q.when();
    }

    service.handle_checkin_resp = function(evt, params, options) {
        if (!angular.isArray(evt)) evt = [evt];

        var final_resp = {evt : evt, params : params, options : options};

        var copy, hold, transit;
        if (evt[0].payload) {
            copy = evt[0].payload.copy;
            hold = evt[0].payload.hold;
            transit = evt[0].payload.transit;
        }

        // track the barcode regardless of whether it's valid
        angular.forEach(evt, function(e){ e.copy_barcode = params.copy_barcode; });

        angular.forEach(evt, function(e){ console.debug('checkin event ' + e.textcode); });

        if (evt.filter(function(e){return service.checkin_overridable_events.indexOf(e.textcode) > -1;}).length > 0)
            return service.handle_overridable_checkin_event(evt, params, options);

        switch (evt[0].textcode) {

            case 'SUCCESS':
            case 'NO_CHANGE':

                switch(Number(copy.status().id())) {

                    case 0: /* AVAILABLE */                                        
                    case 4: /* MISSING */                                          
                    case 7: /* RESHELVING */ 

                        egCore.audio.play('success.checkin');

                        // see if the copy location requires an alert
                        return service.handle_checkin_loc_alert(evt, params, options)
                        .then(function() {return final_resp});

                    case 8: /* ON HOLDS SHELF */
                        egCore.audio.play('info.checkin.holds_shelf');
                        
                        if (hold) {

                            if (hold.pickup_lib() == egCore.auth.user().ws_ou()) {
                                // inform user if the item is on the local holds shelf
                            
                                evt[0].route_to = egCore.strings.ROUTE_TO_HOLDS_SHELF;
                                return service.route_dialog(
                                    './circ/share/t_hold_shelf_dialog', 
                                    evt[0], params, options
                                ).then(function() { return final_resp });

                            } else {
                                // normally, if the hold was on the shelf at a 
                                // different location, it would be put into 
                                // transit, resulting in a ROUTE_ITEM event.
                                egCore.audio.play('warning.checkin.wrong_shelf');
                                return $q.when(final_resp);
                            }
                        } else {

                            console.error('checkin: item on holds shelf, '
                                + 'but hold info not returned from checkin');
                            return $q.when(final_resp);
                        }

                    case 11: /* CATALOGING */
                        egCore.audio.play('info.checkin.cataloging');
                        evt[0].route_to = egCore.strings.ROUTE_TO_CATALOGING;
                        if (options.no_precat_alert || options.suppress_popups)
                            return $q.when(final_resp);
                        return egAlertDialog.open(
                            egCore.strings.PRECAT_CHECKIN_MSG, params)
                            .result.then(function() {return final_resp});


                    case 15: /* ON_RESERVATION_SHELF */
                        egCore.audio.play('info.checkin.reservation');
                        // TODO: show booking reservation dialog
                        return $q.when(final_resp);

                    default:
                        egCore.audio.play('success.checkin');
                        console.debug('Unusual checkin copy status (may have been set via copy alert): '
                            + copy.status().id() + ' : ' + copy.status().name());
                        return $q.when(final_resp);
                }
                
            case 'ROUTE_ITEM':
                return service.route_dialog(
                    './circ/share/t_transit_dialog', 
                    evt[0], params, options
                ).then(function(data) {
                    if (transit && data.transit && transit.dest().id() != data.transit.dest().id())
                        final_resp.evt[0].route_to = data.transit.dest().shortname();
                    return final_resp;
                });

            case 'ASSET_COPY_NOT_FOUND':
                egCore.audio.play('error.checkin.not_found');
                if (options.suppress_popups) return $q.when(final_resp);
                return egAlertDialog.open(
                    egCore.strings.UNCAT_ALERT_DIALOG, params)
                    .result.then(function() {return final_resp});

            case 'ITEM_NOT_CATALOGED':
                egCore.audio.play('error.checkin.not_cataloged');
                evt[0].route_to = egCore.strings.ROUTE_TO_CATALOGING;
                if (options.no_precat_alert || options.suppress_popups)
                    return $q.when(final_resp);
                return egAlertDialog.open(
                    egCore.strings.PRECAT_CHECKIN_MSG, params)
                    .result.then(function() {return final_resp});

            case 'HOLD_CAPTURE_DELAYED':
                return service.hold_capture_delay_dialog(
                    evt[0], params, options, 'checkin');

            default:
                egCore.audio.play('error.checkin.unknown');
                console.warn('unhandled checkin response : ' + evt[0].textcode);
                return $q.when(final_resp);
        }
    }

    // collect transit, addresses, and hold info that's not already
    // included in responses.
    service.collect_route_data = function(tmpl, evt, params, options) {
        if (angular.isArray(evt)) evt = evt[0];
        var promises = [];
        var data = {};
        var addr_deferred = $q.defer();
        // associates org units with the address they're needed for
        var addr_orgs = {};
        promises.push(addr_deferred.promise);
        
        if (evt.org && !tmpl.match(/hold_shelf/)) {
            addr_orgs['address'] = evt.org; 
        }
		
		if(evt.payload.transit){
            addr_orgs['source_address'] = evt.payload.transit.source().id(); 			
		}

        if(Object.keys(addr_orgs).length){
            promises.push(
                service.cache_org_addr(Object.values(addr_orgs),'holds_address')
                .then(function(){
                    // promise to assign all of the addresses we need
                    var addr_promises = [];
                    Object.keys(addr_orgs).forEach(function(key){
                        addr_promises.push(
                            service.get_org_addr(addr_orgs[key], 'holds_address')
                            .then(function(addr) { 
                                // assign address to field in data
                                data[key] = addr; 
                            })
                        )
                    });
                    $q.all(addr_promises).then(addr_deferred.resolve());
            }));
        }
        else{
            // no addresses are needed so continue
            addr_deferred.resolve();
        }
        
        if (evt.payload.hold) {
            promises.push(
                egCore.pcrud.retrieve('au', 
                    evt.payload.hold.usr(), {
                        flesh : 1,
                        flesh_fields : {'au' : ['card', 'profile']}
                    }
                ).then(function(patron) {data.patron = patron})
            );
        }


        if (!tmpl.match(/hold_shelf/)) {
            var courier_deferred = $q.defer();
            promises.push(courier_deferred.promise);
            promises.push(
                service.find_copy_transit(evt, params, options)
                .then(function(trans) {
                    data.transit = trans;
                    egCore.org.settings('lib.courier_code', trans.dest().id())
                    .then(function(s) {
                        data.dest_courier_code = s['lib.courier_code'];
                        courier_deferred.resolve();
                    });
                })
            );
        }

        return $q.all(promises).then(function() { return data });
    }

    service.route_dialog = function(tmpl, evt, params, options) {
        if (angular.isArray(evt)) evt = evt[0];

        return service.collect_route_data(tmpl, evt, params, options)
        .then(function(data) {

            var template = data.transit ?
                (data.patron ? 'hold_transit_slip' : 'transit_slip') :
                'hold_shelf_slip';
            if (service.never_auto_print[template]) {
                // do not show the dialog or print if the
                // disabled automatic print attempt type list includes
                // the specified template
                return data;
            }

            // All actions flow from the print data

            var print_context = {
                copy : egCore.idl.toHash(evt.payload.copy),
                title : evt.title,
                author : evt.author,
                call_number : egCore.idl.toHash(evt.payload.volume)
            };

            var acn = print_context.call_number; // fix up pre/suffixes
            if (acn.prefix == -1) acn.prefix = "";
            if (acn.suffix == -1) acn.suffix = "";

            if (data.transit) {
                // route_dialog includes the "route to holds shelf" 
                // dialog, which has no transit
                print_context.transit = egCore.idl.toHash(data.transit);
                print_context.dest_courier_code = data.dest_courier_code;
                if (data.address) {
                    print_context.dest_address = egCore.idl.toHash(data.address);
                }
                if (data.source_address) {
                    print_context.source_address = egCore.idl.toHash(data.source_address);
                }
                print_context.dest_location =
                    egCore.idl.toHash(egCore.org.get(data.transit.dest()));
                print_context.source_location =
                    egCore.idl.toHash(egCore.org.get(data.transit.source()));
                print_context.copy.status = egCore.idl.toHash(print_context.copy.status);
            }

            if (data.patron) {
                print_context.hold = egCore.idl.toHash(evt.payload.hold);
                var notes = print_context.hold.notes;
                if(notes.length > 0){
                    print_context.hold_notes = [];
                    angular.forEach(notes, function(n){
                        print_context.hold_notes.push(n);
                    });
                }
                print_context.patron = egCore.idl.toHash(data.patron);
            }

            var sound = 'info.checkin.transit';
            if (evt.payload.hold) sound += '.hold';
            egCore.audio.play(sound);

            function print_transit(template) {
                return egCore.print.print({
                    context : 'default', 
                    template : template, 
                    scope : print_context
                }).then(function() { return data });
            }

            // when auto-print is on, skip the dialog and go straight
            // to printing.
            if (options.auto_print_holds_transits || options.suppress_popups) 
                return print_transit(template);

            return $uibModal.open({
                templateUrl: tmpl,
                backdrop: 'static',
                controller: [
                            '$scope','$uibModalInstance',
                    function($scope , $uibModalInstance) {

                    $scope.today = new Date();

                    // copy the print scope into the dialog scope
                    angular.forEach(print_context, function(val, key) {
                        $scope[key] = val;
                    });

                    $scope.ok = function() {$uibModalInstance.close()}

                    $scope.print = function() { 
                        $uibModalInstance.close();
                        print_transit(template);
                    }
                }]

            }).result.then(function() { return data });
        });
    }

    // action == what action to take if the user confirms the alert
    service.copy_alert_dialog = function(evt, params, options, action) {
        egCore.audio.play('warning.circ.item_alert');
        if (angular.isArray(evt)) evt = evt[0];
        if (!angular.isArray(evt.payload)) {
            return egConfirmDialog.open(
                egCore.strings.COPY_ALERT_MSG_DIALOG_TITLE, 
                evt.payload,  // payload == alert message text
                {   copy_barcode : params.copy_barcode,
                    ok : function() {},
                    cancel : function() {}
                }
            ).result.then(function() {
                options.override = true;
                return service[action](params, options);
            });
        } else { // we got a list of copy alert objects ...
            return egCopyAlertManagerDialog.open({
                alerts : evt.payload,
                mode : action,
                ok : function(the_next_status) {
                        if (the_next_status !== null) {
                            params.next_copy_status = [ the_next_status ];
                            params.capture = 'nocapture';
                        }
                     },
                cancel : function() {}
            }).result.then(function() {
                options.override = true;
                return service[action](params, options);
            });
        }
    }

    // action == what action to take if the user confirms the alert
    service.hold_capture_delay_dialog = function(evt, params, options, action) {
        if (angular.isArray(evt)) evt = evt[0];
        return $uibModal.open({
            templateUrl: './circ/checkin/t_hold_verify',
            backdrop: 'static',
            controller:
                       ['$scope','$uibModalInstance','params',
                function($scope , $uibModalInstance , params) {
                $scope.copy_barcode = params.copy_barcode;
                $scope.capture = function() {
                    params.capture = 'capture';
                    $uibModalInstance.close();
                };
                $scope.nocapture = function() {
                    params.capture = 'nocapture';
                    $uibModalInstance.close();
                };
                $scope.cancel = function() { $uibModalInstance.dismiss(); };
            }],
            resolve : {
                params : function() {
                    return params;
                }
            }
        }).result.then(
            function(r) {
                return service[action](params, options);
            }
        );
    }

    // check the barcode.  If it's no good, show the warning dialog
    // Resolves on success, rejected on error
    service.test_barcode = function(bc) {

        var ok = service.check_barcode(bc);
        if (ok) return $q.when();

        egCore.audio.play('warning.circ.bad_barcode');
        return $uibModal.open({
            templateUrl: './circ/share/t_bad_barcode_dialog',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', 
                function($scope, $uibModalInstance) {
                $scope.barcode = bc;
                $scope.ok = function() { $uibModalInstance.close() }
                $scope.cancel = function() { $uibModalInstance.dismiss() }
            }]
        }).result;
    }

    // check() and checkdigit() copied directly 
    // from chrome/content/util/barcode.js

    service.check_barcode = function(bc) {
        if (bc != Number(bc)) return false;
        bc = bc.toString();
        // "16.00" == Number("16.00"), but the . is bad.
        // Throw out any barcode that isn't just digits
        if (bc.search(/\D/) != -1) return false;
        var last_digit = bc.substr(bc.length-1);
        var stripped_barcode = bc.substr(0,bc.length-1);
        return service.barcode_checkdigit(stripped_barcode).toString() == last_digit;
    }

    service.barcode_checkdigit = function(bc) {
        var reverse_barcode = bc.toString().split('').reverse();
        var check_sum = 0; var multiplier = 2;
        for (var i = 0; i < reverse_barcode.length; i++) {
            var digit = reverse_barcode[i];
            var product = digit * multiplier; product = product.toString();
            var temp_sum = 0;
            for (var j = 0; j < product.length; j++) {
                temp_sum += Number( product[j] );
            }
            check_sum += Number( temp_sum );
            multiplier = ( multiplier == 2 ? 1 : 2 );
        }
        check_sum = check_sum.toString();
        var next_multiple_of_10 = (check_sum.match(/(\d*)\d$/)[1] * 10) + 10;
        var check_digit = next_multiple_of_10 - Number(check_sum);
        if (check_digit == 10) check_digit = 0;
        return check_digit;
    }

    service.handle_barcode_completion = function(barcode) {
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            egCore.auth.token(), egCore.auth.user().ws_ou(), 
            'asset', barcode)

        .then(function(resp) {
            // TODO: handle event during barcode lookup
            if (evt = egCore.evt.parse(resp)) {
                console.error(evt.toString());
                return $q.reject();
            }

            // no matching barcodes: return the barcode as entered
            // by the user (so that, e.g., checkout can fall back to
            // precat/noncat handling)
            if (!resp || !resp[0]) {
                return barcode;
            }

            // exactly one matching barcode: return it
            if (resp.length == 1) {
                return resp[0].barcode;
            }

            // multiple matching barcodes: let the user pick one 
            console.debug('multiple matching barcodes');
            var matches = [];
            var promises = [];
            var final_barcode;
            angular.forEach(resp, function(cp) {
                promises.push(
                    egCore.net.request(
                        'open-ils.circ',
                        'open-ils.circ.copy_details.retrieve',
                        egCore.auth.token(), cp.id
                    ).then(function(r) {
                        matches.push({
                            barcode: r.copy.barcode(),
                            title: r.mvr.title(),
                            org_name: egCore.org.get(r.copy.circ_lib()).name(),
                            org_shortname: egCore.org.get(r.copy.circ_lib()).shortname()
                        });
                    })
                );
            });
            return $q.all(promises)
            .then(function() {
                return $uibModal.open({
                    templateUrl: './circ/share/t_barcode_choice_dialog',
                    backdrop: 'static',
                    controller:
                        ['$scope', '$uibModalInstance',
                        function($scope, $uibModalInstance) {
                        $scope.matches = matches;
                        $scope.ok = function(barcode) {
                            $uibModalInstance.close();
                            final_barcode = barcode;
                        }
                        $scope.cancel = function() {$uibModalInstance.dismiss()}
                    }],
                }).result.then(function() { return final_barcode });
            })
        });
    }

    function generate_note_dialog_watch_callback($scope,egCore,allPenalties) {
        return function(newval) {
            if (newval) {
                var selected_penalty = allPenalties.filter(function(p) {
                        return p.id() == newval; })[0];
                var penalty_id = selected_penalty.id();
                if (penalty_id == 20 || penalty_id == 21 || penalty_id == 25) {
                    $scope.args.custom_penalty = penalty_id;
                    $scope.args.penalty = penalty_id;
                }
                if (penalty_id > 100) {
                    $scope.args.custom_penalty = penalty_id;
                    $scope.args.penalty = null;
                }
                // there's a $watch on custom_depth
                if (selected_penalty.org_depth() || selected_penalty.org_depth() == 0) {
                    $scope.args.custom_depth = selected_penalty.org_depth();
                } else {
                    $scope.args.custom_depth = $scope.args.org.ou_type().depth();
                }
            }
        };
    }

    function init_note($scope , $uibModalInstance , allPenalties , goodOrgs) {
                $scope.focusNote = true;
                $scope.penalties = allPenalties.filter(
                    function(p) { return p.id() > 100 || p.id() == 20 || p.id() == 21 || p.id() == 25; });
                $scope.set_penalty = function(id) {
                    if (!($scope.args.pub && $scope.args.read_date) && !$scope.args.deleted) {
                        $scope.args.penalty = id;
                    }
                }
                $scope.require_initials = service.require_initials;
                $scope.update_org = function(org) {
                    if (!($scope.args.pub && $scope.args.read_date) && !$scope.args.deleted) {
                        $scope.args.org = org;
                    }
                }
                $scope.cant_use_org = function(org_id) {
                    return ($scope.args.pub && $scope.args.read_date) || $scope.args.deleted || goodOrgs.indexOf(org_id) == -1;
                }
                $scope.args = {
                    pub : false,
                    penalty : 21, // default to Note
                    org : egCore.org.get(egCore.auth.user().ws_ou())
                };
                $scope.args.max_depth = $scope.args.org.ou_type().depth();
                $scope.ok = function(count) { $uibModalInstance.close($scope.args) }
                $scope.cancel = function($event) { 
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
                $scope.$watch('args.penalty', generate_note_dialog_watch_callback($scope,egCore,allPenalties));
                $scope.$watch('args.custom_penalty', generate_note_dialog_watch_callback($scope,egCore,allPenalties));
                $scope.$watch('args.custom_depth', function(org_depth) {
                    if (org_depth || org_depth == 0) {
                        egCore.net.request(
                            'open-ils.actor',
                            'open-ils.actor.org_unit.ancestor_at_depth.retrieve',
                            egCore.auth.token(), egCore.auth.user().ws_ou(), org_depth
                        ).then(function(ctx_org) {
                            if (ctx_org) {
                                $scope.args.org = egCore.org.get(ctx_org);
                            }
                        });
                    }
                });
    }

    service.create_note = function(user_id) {
        return $uibModal.open({
            templateUrl: './circ/share/t_new_message_dialog',
            backdrop: 'static',
            controller:
                   ['$scope','$uibModalInstance','allPenalties','goodOrgs',init_note],
            resolve : {
                allPenalties : service.get_all_penalty_types,
                goodOrgs : egCore.perm.hasPermAt('UPDATE_USER', true)
            }
        }).result.then(
            function(args) {
                var pen = new egCore.idl.ausp();
                var msg = {
                    pub : args.pub,
                    title : args.title,
                    message : args.note ? args.note : ''
                };
                pen.usr(user_id);
                pen.org_unit(args.org.id());
                if (args.initials) msg.message = (args.note ? args.note : '') + ' [' + args.initials + ']';
                if (args.custom_penalty) {
                    pen.standing_penalty(args.custom_penalty);
                } else {
                    pen.standing_penalty(args.penalty);
                }
                pen.staff(egCore.auth.user().id());
                pen.set_date('now');

                return egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.user.note.apply',
                    egCore.auth.token(), pen, msg
                );
            }
        );
    }

    service.batch_create_note = function(container_id) {
        return $uibModal.open({
            templateUrl: './circ/share/t_new_message_dialog',
            backdrop: 'static',
            controller:
                   ['$scope','$uibModalInstance','allPenalties','goodOrgs',init_note],
            resolve : {
                allPenalties : service.get_all_penalty_types,
                goodOrgs : egCore.perm.hasPermAt('UPDATE_USER', true)
            }
        }).result.then(
            function(args) {
                var pen = new egCore.idl.ausp();
                var msg = new egCore.idl.aum();
                msg.pub(args.pub);
                msg.title(args.title);
                msg.message(args.note ? args.note : '');
                pen.org_unit(args.org.id());
                if (args.initials) msg.message((args.note ? args.note : '') + ' [' + args.initials + ']');
                if (args.custom_penalty) {
                    pen.standing_penalty(args.custom_penalty);
                } else {
                    pen.standing_penalty(args.penalty);
                }
                pen.staff(egCore.auth.user().id());
                pen.set_date('now');

                return egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.container.user.batch_create_message',
                    egCore.auth.token(), container_id, pen, msg
                );
            }
        );
    }

    // assumes, for now anyway,  penalty type is fleshed onto usr_penalty.
    service.edit_note = function(pen,aum) {
        return $uibModal.open({
            templateUrl: './circ/share/t_new_message_dialog',
            backdrop: 'static',
            controller: 
                   ['$scope','$uibModalInstance','allPenalties','goodOrgs',
            function($scope , $uibModalInstance , allPenalties , goodOrgs) {
                // We may need to vivicate usr_penalty (pen) or usr_message (aum)
                if (!pen) {
                    pen = new egCore.idl.ausp();
                    pen.usr(aum.usr());
                    pen.org_unit(aum.sending_lib()); // FIXME: preserve sending_lib or use ws_ou?
                    pen.staff(egCore.auth.user().id());
                    pen.set_date('now');
                    pen.usr_message(aum.id());
                    pen.isnew(true);
                    aum.ischanged(true);
                }
                if (!aum) {
                    aum = new egCore.idl.aum();
                    aum.create_date('now');
                    aum.sending_lib(pen.org_unit());
                    aum.pub(false);
                    aum.usr(pen.usr());
                    aum.isnew(true);
                    pen.ischanged(true);
                }

                $scope.focusNote = true;
                $scope.penalties = allPenalties.filter(
                    function(p) { return p.id() > 100 || p.id() == 20 || p.id() == 21 || p.id() == 25; });
                $scope.set_penalty = function(id) {
                    if (!($scope.args.pub && $scope.args.read_date) && !$scope.args.deleted) {
                        $scope.args.penalty = id;
                    }
                }
                $scope.require_initials = service.require_initials;
                $scope.update_org = function(org) {
                    if (!($scope.args.pub && $scope.args.read_date) && !$scope.args.deleted) {
                        $scope.args.org = org;
                    }
                }
                $scope.cant_use_org = function(org_id) {
                    return ($scope.args.pub && $scope.args.read_date) || $scope.args.deleted || goodOrgs.indexOf(org_id) == -1;
                }
                var penalty_id = pen.standing_penalty();
                $scope.args = {
                    penalty : pen.isnew()
                        ? 21 // default to Note
                        : penalty_id,
                    pub : typeof aum.pub() == 'boolean'
                        ? aum.pub()
                        : aum.pub() == 't',
                    title : aum.title(),
                    note : aum.message() ? aum.message() : '',
                    org : egCore.org.get(pen.org_unit()),
                    deleted : typeof aum.deleted() == 'boolean'
                        ? aum.deleted()
                        : aum.deleted() == 't',
                    read_date : aum.read_date(),
                    edit_date : aum.edit_date(),
                    stop_date : aum.stop_date(),
                    editor : aum.editor()
                }
                $scope.args.max_depth = $scope.args.org.ou_type().depth();
                $scope.original_org = $scope.args.org;
                $scope.workstation_depth = egCore.org.get(egCore.auth.user().ws_ou()).ou_type().depth();
                if (penalty_id == 20 || penalty_id == 21 || penalty_id == 25) {
                    $scope.args.custom_penalty = penalty_id;
                }
                if (penalty_id > 100) {
                    $scope.args.custom_penalty = penalty_id;
                    $scope.args.penalty = null;
                }
                $scope.ok = function(count) { $uibModalInstance.close($scope.args) }
                $scope.cancel = function($event) { 
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
                $scope.$watch('args.penalty', generate_note_dialog_watch_callback($scope,egCore,allPenalties));
                $scope.$watch('args.custom_penalty', generate_note_dialog_watch_callback($scope,egCore,allPenalties));
                $scope.$watch('args.custom_depth', function(org_depth) {
                    if (org_depth || org_depth == 0) {
                        if (org_depth > $scope.workstation_depth) {
                            $scope.args.org = $scope.original_org;
                        } else {
                            egCore.net.request(
                                'open-ils.actor',
                                'open-ils.actor.org_unit.ancestor_at_depth.retrieve',
                                egCore.auth.token(), egCore.auth.user().ws_ou(), org_depth
                            ).then(function(ctx_org) {
                                if (ctx_org) {
                                    $scope.args.org = egCore.org.get(ctx_org);
                                }
                            });
                        }
                    }
                });
            }],
            resolve : {
                allPenalties : service.get_all_penalty_types,
                goodOrgs : egCore.perm.hasPermAt('UPDATE_USER', true)
            }
        }).result.then(
            function(args) {
                aum.pub(args.pub);
                aum.title(args.title);
                aum.message(args.note);
                aum.sending_lib(egCore.org.get(egCore.auth.user().ws_ou()).id());
                pen.org_unit(egCore.org.get(args.org).id());
                if (args.initials) aum.message((args.note ? args.note : '') + ' [' + args.initials + ']');
                if (args.custom_penalty) {
                    pen.standing_penalty(args.custom_penalty);
                } else {
                    pen.standing_penalty(args.penalty);
                }
                return egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.user.note.modify',
                    egCore.auth.token(), pen, aum
                );
            }
        );
    }

    return service;

}]);


