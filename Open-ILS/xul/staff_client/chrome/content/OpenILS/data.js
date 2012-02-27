dump('entering OpenILS/data.js\n');

if (typeof OpenILS == 'undefined') OpenILS = {};
OpenILS.data = function () {

    try {
        /* We're going to turn this guy into a singleton, at least for a given window, and look for it in xulG */
        if (! window.xulG) { window.xulG = {}; }
        if (window.xulG._data) { return window.xulG._data; }

        JSAN.use('util.error'); this.error = new util.error();
        JSAN.use('util.network'); this.network = new util.network();
    } catch(E) {
        alert(location.href + '\nError in OpenILS.data constructor: ' + E);
        throw(E);
    }

    window.xulG._data = this;
    return this;
}

OpenILS.data.prototype = {

    'list' : {},
    'hash' : {},
    'tree' : {},

    'temp' : '',

    'data_progress' : function(msg) {
        try {
            var x = document.getElementById('data_progress');
            if (x) {
                x.appendChild( document.createTextNode( msg ) );
            }
        } catch(E) {
            this.error.sdump('D_ERROR',msg + '\n' + E);
        }
    },

    'init' : function (params) {

        try {
            if (params && params.via == 'stash') {    
                this.stash_retrieve();
            } else {
                this.network_retrieve();
            }
        
        } catch(E) {
            this.error.sdump('D_ERROR','Error in OpenILS.data.init('
                +js2JSON(params)+'): ' + js2JSON(E) );
        }


    },

    // This should be invoked only once per application, in a persistant window
    'init_observer_functions' : function() {
        try {
            var obj = this;                // OpenILS.data
            obj.observers = {};            //
            obj.observers.id = 1;        // Unique id for each observer function added
            obj.observers.id2path = {}; // Lookup for full_path via observer id
            obj.observers.cache = {};    // Observer funcs go in here

            // For a given path, this executes all the registered observer funcs
            obj.observers.dispatch = function(full_path, old_value, new_value) {
                obj.error.sdump('D_OBSERVERS', 'entering observers.dispatch\nfull_path = ' + full_path + '\nold_value = ' + js2JSON(old_value) + '\nnew_value = ' + js2JSON(new_value) + '\n');
                try {
                    var path = full_path.split(/\./).pop();
                    for (var i in obj.observers.cache[full_path]) {
                        try {
                            var o = obj.observers.cache[full_path][i];
                            if (typeof o.func == 'function') o.func(path, old_value, new_value);
                        } catch(E) {
                            obj.error.sdump('D_ERROR','Error in OpenILS.data.observers.dispatch(): ' + js2JSON(E) );
                        }
                    }
                } catch(E) {
                    obj.error.sdump('D_ERROR','Error in OpenILS.data.observers.dispatch(): ' + js2JSON(E) );
                }
            }

            // This registers an observer function for a given path
            obj.observers.add = function(full_path, func) {
                try {
                    obj.error.sdump('D_OBSERVERS', 'entering observers.add\nfull_path = ' + full_path + '\nfunc = ' + func + '\n');
                    var data_cache = Components.classes["@open-ils.org/openils_data_cache;1"].getService();
                    var stash = data_cache.wrappedJSObject.data;

                    var id = obj.observers.id++;
                    if (typeof obj.observers.cache[ full_path ] == 'undefined') obj.observers.cache[ full_path ] = {};
                    obj.observers.cache[ full_path ][ id ] = { 'func' : func, 'time_added' : new Date() };
                    obj.observers.id2path[ id ] = [ full_path ];

                    var path_list = full_path.split(/\./);
                    var observed_prop = path_list.pop();

                    // Convert soft path to object reference.  Error if any but the last node is undefined
                    for (var i in path_list) stash = stash[ path_list[i] ];

                    /*

                    // experiment with storing only json in cache to avoid the [ ] -> { '0' : .., '1' : .. } bug

                    if (stash[observed_prop] && getKeys( obj.observers.cache[ full_path ] ).length == 0) {
                        stash['_' + observed_prop] = js2JSON(stash[observed_prop]);
                    }

                    stash.__defineSetter__(observed_prop, function(x) { this['_'+observed_prop] = js2JSON(x); });
                    stash.__defineGetter__(observed_prop, function() { return JSON2js(this['_'+observed_prop]); });
                    */

                    stash.watch(
                        observed_prop,
                        function(p,old_value,new_value) {
                            obj.observers.dispatch(full_path,old_value,new_value);
                            return new_value;
                        }
                    );

                    return id;
                } catch(E) {
                    obj.error.sdump('D_ERROR','Error in OpenILS.data.observers.add(): ' + js2JSON(E) );
                }
            }

            // This unregisters an observer function for a given observer id
            obj.observers.remove = function(id) {
                try {
                    obj.error.sdump('D_OBSERVERS', 'entering observers.remove\nid = ' + id + '\n');
                    var path = obj.observers.id2path[ id ];
                    delete obj.observers.cache[ path ][ id ];
                    delete obj.observers.id2path[ id ];
                } catch(E) {
                    obj.error.sdump('D_ERROR','Error in OpenILS.data.observers.remove(): ' + js2JSON(E) );
                }
            }

            // This purges observer functions for a given path
            obj.observers.purge = function(full_path) {
                obj.error.sdump('D_OBSERVERS', 'entering observers.purge\nfull_path = ' + full_path + '\n');
                try {
                    var remove_these = [];
                    for (var id in obj.observers.cache[ full_path ]) remove_these.push( id );
                    for (var id in remove_these) delete obj.observers.id2path[ id ];
                    delete obj.observers.cache[ full_path ];
                } catch(E) {
                    obj.error.sdump('D_ERROR','Error in OpenILS.data.observers.purge(): ' + js2JSON(E) );
                }
            }

            obj.stash('observers'); // make this accessible globally

        } catch(E) {
            this.error.sdump('D_ERROR','Error in OpenILS.data.init_observer_functions(): ' + js2JSON(E) );
        }
    },

    'stash' : function () {
        try {
            var data_cache = Components.classes["@open-ils.org/openils_data_cache;1"].getService();
            for (var i = 0; i < arguments.length; i++) {
                try {
                    if (arguments[i] != 'hash' && arguments[i] != 'list') this.error.sdump('D_DATA_STASH','stashing ' + arguments[i] + ' : ' + this[arguments[i]] + (typeof this[arguments[i]] == 'object' ? ' = ' + (this[arguments[i]]) : '') + '\n');
                } catch(F) { alert(F); }
                data_cache.wrappedJSObject.data[arguments[i]] = this[arguments[i]];
            }
        } catch(E) {
            this.error.sdump('D_ERROR','Error in OpenILS.data.stash(): ' + js2JSON(E) );
        }
    },

    'lookup' : function(key,value) {
        try {
            var obj = this; var found;
            if (obj.hash[key] && obj.hash[key][value]) return obj.hash[key][value];
            switch(key) {
                case 'acnp':
                    found = obj.network.simple_request('FM_ACNP_RETRIEVE_VIA_PCRUD',[ ses(), { 'id' : { '=' : value } }]);
                    if (typeof found.ilsevent != 'undefined') throw(js2JSON(found));
                    found = found[0];
                break;
                case 'acns':
                    found = obj.network.simple_request('FM_ACNS_RETRIEVE_VIA_PCRUD',[ ses(), { 'id' : { '=' : value } }]);
                    if (typeof found.ilsevent != 'undefined') throw(js2JSON(found));
                    found = found[0];
                break;
                case 'acpl': 
                    found = obj.network.simple_request('FM_ACPL_RETRIEVE_VIA_ID.authoritative',[ value ]);
                break;
                case 'actsc':
                    found = obj.network.simple_request('FM_ACTSC_RETRIEVE_VIA_PCRUD',[ ses(), { 'id' : { '=' : value } }]);
                    if (typeof found.ilsevent != 'undefined') throw(js2JSON(found));
                    found = found[0];
                break;
                default: return undefined; break;
            }
            if (typeof found.ilsevent != 'undefined') throw(found);
            if (!obj.hash[key]) obj.hash[key] = {};
            obj.hash[key][value] = found;
            if (!obj.list[key]) obj.list[key] = [];
            obj.list[key].push( found );
            obj.stash('hash','list');
            return found;
        } catch(E) {
            alert('Error in OpenILS.data.lookup('+key+','+value+'): ' + E );
            return undefined;
        }
    },

    '_debug_stash' : function() {
        try {
            var data_cache = Components.classes["@open-ils.org/openils_data_cache;1"].getService();
            for (var i in data_cache.wrappedJSObject.data) {
                dump('_debug_stash ' + i + '\n');
            }
        } catch(E) {
            this.error.sdump('D_ERROR','Error in OpenILS.data._debug_stash(): ' + js2JSON(E) );
        }
    },

    '_fm_objects' : {

        'pgt' : [ api.FM_PGT_RETRIEVE.app, api.FM_PGT_RETRIEVE.method, [], true ],
        'cit' : [ api.FM_CIT_RETRIEVE.app, api.FM_CIT_RETRIEVE.method, [], true ],
        'citm' : [ api.FM_CITM_RETRIEVE.app, api.FM_CITM_RETRIEVE.method, [{'query':{'ctype' : 'item_type'}}], true ],
        /*
        'cst' : [ api.FM_CST_RETRIEVE.app, api.FM_CST_RETRIEVE.method, [], true ],
        */
        /*
        'acpl' : [ api.FM_ACPL_RETRIEVE.app, api.FM_ACPL_RETRIEVE.method, [], true ],
        */
        'ccs' : [ api.FM_CCS_RETRIEVE.app, api.FM_CCS_RETRIEVE.method, [], true ],
        'aou' : [ api.FM_AOU_RETRIEVE.app, api.FM_AOU_RETRIEVE.method, [], true ],
        'aout' : [ api.FM_AOUT_RETRIEVE.app, api.FM_AOUT_RETRIEVE.method, [], true ],
        'crahp' : [ api.FM_CRAHP_RETRIEVE.app, api.FM_CRAHP_RETRIEVE.method, [], true ]
    },

    'stash_retrieve' : function() {
        try {
            var data_cache = Components.classes["@open-ils.org/openils_data_cache;1"].getService();
            var dc = data_cache.wrappedJSObject.data;
            for (var i in dc) {
                this.error.sdump('D_DATA_RETRIEVE','Retrieving ' + i + ' : ' + dc[i] + '\n');
                this[i] = dc[i];
            }
        } catch(E) {
            this.error.sdump('D_ERROR','Error in OpenILS.data._debug_stash(): ' + js2JSON(E) );
        }
    },

    'load_saved_print_templates' : function() {
        var obj = this;
        try {
            JSAN.use('util.file'); var file = new util.file('print_list_templates');
            if (file._file.exists()) {
                try {
                    var x = file.get_object();
                    if (x) {
                        for (var i in x) {
                            obj.print_list_templates[i] = x[i];
                        }
                        // handle macro changes
                        var templates = [ 'bills_current', 'bills_historical' ];
                        for (var i = 0; i < templates.length; i++) {
                            if (obj.print_list_templates[templates[i]]) {
                                // mbts_id
                                obj.print_list_templates[templates[i]].line_item =
                                    obj.print_list_templates[templates[i]].line_item.replace(
                                        /%id%/g, '%mbts_id%');
                                // mbts_xact_start
                                obj.print_list_templates[templates[i]].line_item =
                                    obj.print_list_templates[templates[i]].line_item.replace(
                                        /%xact_start%/g, '%mbts_xact_start%');
                                // mbts_xact_finish
                                obj.print_list_templates[templates[i]].line_item =
                                    obj.print_list_templates[templates[i]].line_item.replace(
                                        /%xact_finish%/g, '%mbts_xact_finish%');
                            }
                        }
                        //
                        obj.stash('print_list_templates');
                        obj.data_progress('Saved print templates retrieved from file. ');
                    }
                } catch(E) {
                    alert(E);
                }
            }
            file.close();
        } catch(E) {
            alert("Error in OpenILS.data, load_saved_print_templates(): " + E);
        }
    },

    'fetch_print_strategy' : function() {
        var obj = this;
        try {
            obj.print_strategy = {};
            var print_contexts = [ 'default', 'receipt', 'label', 'mail', 'offline' ];
            for (var i in print_contexts) {
                JSAN.use('util.file'); var file = new util.file('print_strategy.' + print_contexts[i]);
                if (file._file.exists()) {
                    try {
                        var x = file.get_content();
                        if (x) {
                            obj.print_strategy[ print_contexts[i] ] = x;
                            obj.data_progress('Print strategy ' + print_contexts[i] + ' retrieved from file. ');
                        }
                    } catch(E) {
                        alert(E);
                    }
                }
                file.close();
            }
            obj.stash('print_strategy');
        } catch(E) {
            alert('Error in OpenILS.data, fetch_print_strategy(): ' + E);
        }
    },

    'print_list_defaults' : function() {
        var obj = this;
        //if (typeof obj.print_list_templates == 'undefined') {
        {
            obj.print_list_types = [ 
                'offline_checkout', 
                'offline_checkin', 
                'offline_renew', 
                'offline_inhouse_use', 
                'items', 
                'bills', 
                'payment', 
                'holds', 
                /* 'patrons' */
            ];
            // We define this for the benefit of the editor.
            // We don't assign them here, leaving that to the user.
            // Without one assigned per template the context the util.print was created with will be used instead.
            obj.print_list_contexts = [
                'default',
                'receipt',
                'label',
                'mail',
                'offline',
            ]; 
            obj.print_list_templates = { 
                'item_status' : {
                    'type' : 'items',
                    'header' : 'The following items have been examined:<hr/><ol>',
                    'line_item' : '<li>%title%<br/>\r\nBarcode: %barcode%\r\n',
                    'footer' : '</ol><hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\n<br/>\r\n'
                }, 
                'transit_list' : {
                    'type' : 'transits',
                    'header' : 'Transits:<hr/><ol>',
                    'line_item' : '<li>From: %transit_source% To: %transit_dest_lib%<br/>\r\nWhen: %transit_source_send_time%<br />\r\nBarcode: %transit_item_barcode% Title: %transit_item_title%<br/>\r\n',
                    'footer' : '</ol><hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\n<br/>\r\n'
                }, 
                'items_out' : {
                    'type' : 'items',
                    'header' : 'Welcome to %LIBRARY%!<br/>\r\nYou have the following items:<hr/><ol>',
                    'line_item' : '<li>%title%<br/>\r\nBarcode: %barcode% Due: %due_date%\r\n',
                    'footer' : '</ol><hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\nYou were helped by %STAFF_FIRSTNAME%<br/>\r\n<br/>\r\n'
                }, 
                'renew' : {
                    'type' : 'items',
                    'header' : 'Welcome to %LIBRARY%!<br/>\r\nYou have renewed the following items:<hr/><ol>',
                    'line_item' : '<li>%title%<br/>\r\nBarcode: %barcode% Due: %due_date%\r\n',
                    'footer' : '</ol><hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\nYou were helped by %STAFF_FIRSTNAME%<br/>\r\n<br/>\r\n'
                }, 
                'checkout' : {
                    'type' : 'items',
                    'header' : 'Welcome to %LIBRARY%!<br/>\r\nYou checked out the following items:<hr/><ol>',
                    'line_item' : '<li>%title%<br/>\r\nBarcode: %barcode% Due: %due_date%\r\n',
                    'footer' : '</ol><hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\nYou were helped by %STAFF_FIRSTNAME%<br/>\r\n<br/>\r\n'
                }, 
                'offline_checkout' : {
                    'type' : 'offline_checkout',
                    'header' : 'Patron %patron_barcode%<br/>\r\nYou checked out the following items:<hr/><ol>',
                    'line_item' : '<li>Barcode: %barcode%<br/>\r\nDue: %due_date%\r\n',
                    'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n'
                },
                'checkin' : {
                    'type' : 'items',
                    'header' : 'You checked in the following items:<hr/><ol>',
                    'line_item' : '<li>%title%<br/>\r\nBarcode: %barcode%  Call Number: %call_number%\r\n',
                    'footer' : '</ol><hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\n<br/>\r\n'
                }, 
                'bill_payment' : {
                    'type' : 'payment',
                    'header' : 'Welcome to %LIBRARY%!<br/>A receipt of your  transaction:<hr/> <table width="100%"> <tr> <td>Original Balance:</td> <td align="right">$%original_balance%</td> </tr> <tr> <td>Payment Method:</td> <td align="right">%payment_type%</td> </tr> <tr> <td>Payment Received:</td> <td align="right">$%payment_received%</td> </tr> <tr> <td>Payment Applied:</td> <td align="right">$%payment_applied%</td> </tr> <tr> <td>Billings Voided:</td> <td align="right">%voided_balance%</td> </tr> <tr> <td>Change Given:</td> <td align="right">$%change_given%</td> </tr> <tr> <td>New Balance:</td> <td align="right">$%new_balance%</td> </tr> </table> <p> Note: %note% </p> <p> Specific bills: <blockquote>',
                    'line_item' : 'Bill #%bill_id%  %last_billing_type% Received: $%payment%<br />%barcode% %title%<br /><br />',
                    'footer' : '</blockquote> </p> <hr />%SHORTNAME% %TODAY_TRIM%<br/> <br/> '
                },
                'bills_historical' : {
                    'type' : 'bills',
                    'header' : 'Welcome to %LIBRARY%!<br/>You had the following bills:<hr/><ol>',
                    'line_item' : '<dt><b>Bill #%mbts_id%</b> %title% </dt> <dd> <table> <tr valign="top"><td>Date:</td><td>%mbts_xact_start%</td></tr> <tr valign="top"><td>Type:</td><td>%xact_type%</td></tr> <tr valign="top"><td>Last Billing:</td><td>%last_billing_type%<br/>%last_billing_note%</td></tr> <tr valign="top"><td>Total Billed:</td><td>$%total_owed%</td></tr> <tr valign="top"><td>Last Payment:</td><td>%last_payment_type%<br/>%last_payment_note%</td></tr> <tr valign="top"><td>Total Paid:</td><td>$%total_paid%</td></tr> <tr valign="top"><td><b>Balance:</b></td><td><b>$%balance_owed%</b></td></tr> </table><br/>',
                    'footer' : '</ol><hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\n<br/>\r\n'
                }, 
                'bills_current' : {
                    'type' : 'bills',
                    'header' : 'Welcome to %LIBRARY%!<br/>You have the following bills:<hr/><ol>',
                    'line_item' : '<dt><b>Bill #%mbts_id%</b></dt> <dd> <table> <tr valign="top"><td>Date:</td><td>%mbts_xact_start%</td></tr> <tr valign="top"><td>Type:</td><td>%xact_type%</td></tr> <tr valign="top"><td>Last Billing:</td><td>%last_billing_type%<br/>%last_billing_note%</td></tr> <tr valign="top"><td>Total Billed:</td><td>$%total_owed%</td></tr> <tr valign="top"><td>Last Payment:</td><td>%last_payment_type%<br/>%last_payment_note%</td></tr> <tr valign="top"><td>Total Paid:</td><td>$%total_paid%</td></tr> <tr valign="top"><td><b>Balance:</b></td><td><b>$%balance_owed%</b></td></tr> </table><br/>',
                    'footer' : '</ol><hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\n<br/>\r\n'
                },
                'offline_checkin' : {
                    'type' : 'offline_checkin',
                    'header' : 'You checked in the following items:<hr/><ol>',
                    'line_item' : '<li>Barcode: %barcode%\r\n',
                    'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n'
                },
                'offline_renew' : {
                    'type' : 'offline_renew',
                    'header' : 'You renewed the following items:<hr/><ol>',
                    'line_item' : '<li>Barcode: %barcode%\r\n',
                    'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n'
                },
                'offline_inhouse_use' : {
                    'type' : 'offline_inhouse_use',
                    'header' : 'You marked the following in-house items used:<hr/><ol>',
                    'line_item' : '<li>Barcode: %barcode%\r\nUses: %count%',
                    'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n'
                },
                'in_house_use' : {
                    'type' : 'items',
                    'header' : 'You marked the following in-house items used:<hr/><ol>',
                    'line_item' : '<li>Barcode: %barcode%\r\nUses: %uses%\r\n<br />%alert_message%',
                    'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n'
                },
                'holds' : {
                    'type' : 'holds',
                    'header' : 'Welcome to %LIBRARY%!<br/>\r\nYou have the following titles on hold:<hr/><ol>',
                    'line_item' : '<li>%title%\r\n',
                    'footer' : '</ol><hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\nYou were helped by %STAFF_FIRSTNAME%<br/>\r\n<br/>\r\n'
                },
                'holds_on_bib' : {
                    'type' : 'holds',
                    'inherit' : 'holds'
                },
                'holds_for_patron' : {
                    'type' : 'holds',
                    'inherit' : 'holds'
                },
                'holds_shelf' : {
                    'type' : 'holds',
                    'inherit' : 'holds'
                },
                'holds_pull_list' : {
                    'type' : 'holds',
                    'inherit' : 'holds'
                },
                'hold_slip' : {
                    'type' : 'holds',
                    'header' : 'This item needs to be routed to <b>%route_to%</b>:<br/>\r\nBarcode: %item_barcode%<br/>\r\nTitle: %item_title%<br/>\r\n<br/>\r\n%hold_for_msg%<br/>\r\nBarcode: %PATRON_BARCODE%<br/>\r\nNotify by phone: %notify_by_phone%<br/>\r\nNotified by text: %notify_by_text%<br/>\r\nNotified by email: %notify_by_email%<br/>\r\n',
                    'line_item' : '%formatted_note%<br/>\r\n',
                    'footer' : '<br/>\r\nRequest date: %request_date%<br/>\r\nSlip Date: %TODAY_TRIM%<br/>\r\nPrinted by %STAFF_FIRSTNAME% at %SHORTNAME%<br/>\r\n<br/>\r\n'
                },
                'transit_slip' : {
                    'type' : 'transits',
                    'header' : 'This item needs to be routed to <b>%route_to%</b>:<br/>\r\n%route_to_org_fullname%<br/>\r\n%street1%<br/>\r\n%street2%<br/>\r\n%city_state_zip%<br/>\r\n<br/>\r\nBarcode: %item_barcode%<br/>\r\nTitle: %item_title%<br/>\r\nAuthor: %item_author%<br>\r\n<br/>\r\n',
                    'line_item' : '',
                    'footer' : 'Slip Date: %TODAY_TRIM%<br/>\r\nPrinted by %STAFF_FIRSTNAME% at %SHORTNAME%<br/>\r\n<br/>\r\n'
                },
                'hold_transit_slip' : {
                    'type' : 'transits',
                    'header' : 'This item needs to be routed to <b>%route_to%</b>:<br/>\r\n%route_to_org_fullname%<br/>\r\n%street1%<br/>\r\n%street2%<br/>\r\n%city_state_zip%<br/>\r\n<br/>\r\nBarcode: %item_barcode%<br/>\r\nTitle: %item_title%<br/>\r\nAuthor: %item_author%<br>\r\n<br/>\r\n%hold_for_msg%<br/>\r\nBarcode: %PATRON_BARCODE%<br/>\r\nNotify by phone: %notify_by_phone%<br/>\r\nNotified by text: %notify_by_text%<br/>\r\nNotified by email: %notify_by_email%<br/>\r\n',
                    'line_item' : '%formatted_note%<br/>\r\n',
                    'footer' : '<br/>\r\nRequest date: %request_date%<br/>\r\nSlip Date: %TODAY_TRIM%<br/>\r\nPrinted by %STAFF_FIRSTNAME% at %SHORTNAME%<br/>\r\n<br/>\r\n'
                },
                'holdings_maintenance' : {
                    'type' : 'items',
                    'header' : 'Title: %title%<br/>\r\nAuthor: %author%<br/>\r\nISBN: %isbn% Edition: %edition% PubDate: %pubdate%<br/>\r\nTCN: %tcn_value% Record ID: %mvr_doc_id%<br/>\r\nCreator: %creator% Create Date: %create_date%<br/>\r\nEditor: %editor% Edit Date: %edit_date%<hr/>\r\n',
                    'line_item' : '%prefix% %tree_location% %suffix% %parts% %acp_status%<br/>\r\n',
                    'footer' : '<hr />%SHORTNAME% %TODAY_TRIM%<br/>\r\n<br/>\r\n'
                }
            }; 

            obj.stash( 'print_list_templates', 'print_list_types' );
        }
    },

    'network_retrieve' : function() {
        var obj = this;

        JSAN.use('util.file'); var file = new util.file('global_font_adjust');
        if (file._file.exists()) {
            try {
                var x = file.get_object();
                if (x) {
                    obj.global_font_adjust = x;
                    obj.stash('global_font_adjust');
                    obj.data_progress('Saved font settings retrieved from file. ');
                }
            } catch(E) {
                alert(E);
            }
        }
        file.close();

        JSAN.use('util.file'); var file = new util.file('no_sound');
        if (file._file.exists()) {
            try {
                var x = file.get_content();
                if (x) {
                    obj.no_sound = x;
                    obj.stash('no_sound');
                    obj.data_progress('Saved sound settings retrieved from file. ');
                }
            } catch(E) {
                alert(E);
            }
        }
        file.close();

        obj.print_list_defaults();
        obj.data_progress('Default print templates set. ');
        obj.load_saved_print_templates();
        obj.fetch_print_strategy();
        JSAN.use('util.print'); (new util.print()).GetPrintSettings();
        obj.data_progress('Printer settings retrieved. ');

        JSAN.use('util.functional');
        JSAN.use('util.fm_utils');

        function gen_fm_retrieval_func(classname,data) {
            var app = data[0]; var method = data[1]; var params = data[2]; var cacheable = data[3];
            return function () {

                function convert() {
                    try {
                        if (obj.list[classname].constructor.name == 'Array') {
                            obj.hash[classname] = 
                                util.functional.convert_object_list_to_hash(
                                    obj.list[classname],
                                    classname == 'citm' ? 'code' : null
                                );
                        }
                    } catch(E) {

                        obj.error.sdump('D_ERROR',E + '\n');
                    }

                }

                try {
                    var level = obj.error.sdump_levels.D_SES_RESULT;
                    if (classname == 'aou' || classname == 'my_aou')
                        obj.error.sdump_levels.D_SES_RESULT = false;
                    var robj = obj.network.request( app, method, params);
                    if (robj != null && typeof robj.ilsevent != 'undefined') {
                        obj.error.standard_unexpected_error_alert('The staff client failed to retrieve expected data from this call, "' + method + '"',robj);
                        throw(robj);
                    }
                    obj.list[classname] = robj == null ? [] : robj;
                    obj.error.sdump_levels.D_SES_RESULT = level;
                    convert();
                    obj.data_progress('Retrieved list for ' + classname + ' objects. ');

                } catch(E) {
                    // if cacheable, try offline
                    if (cacheable) {
                        /* FIXME -- we're going to revisit caching and do it differently
                        try {
                            var file = new util.file( classname );
                            obj.list[classname] = file.get_object(); file.close();
                            convert();
                        } catch(E) {
                            throw(E);
                        }
                        */
                        throw(E); // for now
                    } else {
                        throw(E); // for now
                    }
                }
            }
        }

        // If we don't clear these, then things like obj.list['acnp_for_lib_1'] may stick around
        obj.hash = {}; obj.list = {};

        this.chain = [];

        this.chain.push(
            function() {
                try {
                    var robj = obj.network.simple_request('CIRC_MODIFIER_LIST',[{'full':true}]);
                    if (typeof robj.ilsevent != 'undefined') throw(robj);
                    obj.list.ccm = robj == null ? [] : robj;
                    obj.hash.ccm = util.functional.convert_object_list_to_hash( obj.list.ccm );
                    obj.list.circ_modifier = util.functional.map_list( obj.list.ccm, function(o) { return o.code(); } );
                    obj.data_progress('Retrieved circ modifier list. ');
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'cnal',
                    [
                        api.FM_CNAL_RETRIEVE.app,
                        api.FM_CNAL_RETRIEVE.method,
                        [ obj.session.key ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'bpt',
                    [
                        api.FM_BPT_PCRUD_SEARCH.app,
                        api.FM_BPT_PCRUD_SEARCH.method,
                        [ obj.session.key, {"id":{"!=":null}}, {"order_by":{"bpt":"id"}} ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'csp',
                    [
                        api.FM_CSP_PCRUD_SEARCH.app,
                        api.FM_CSP_PCRUD_SEARCH.method,
                        [ obj.session.key, {"id":{"!=":null}}, {"order_by":{"csp":"id"}} ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'acnc',
                    [
                        api.FM_ACNC_RETRIEVE_VIA_PCRUD.app,
                        api.FM_ACNC_RETRIEVE_VIA_PCRUD.method,
                        [ obj.session.key, {"id":{"!=":null}}, {"order_by":{"acnc":"name"}} ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'ahrcc',
                    [
                        api.FM_AHRCC_PCRUD_SEARCH.app,
                        api.FM_AHRCC_PCRUD_SEARCH.method,
                        [ obj.session.key, {"id":{"!=":null}}, {"order_by":{"ahrcc":"label"}} ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );


        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'au',
                    [
                        api.FM_AU_RETRIEVE_VIA_SESSION.app,
                        api.FM_AU_RETRIEVE_VIA_SESSION.method,
                        [ obj.session.key ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
                obj.list.au = [ obj.list.au ];
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'my_asv',
                    [
                        api.FM_ASV_RETRIEVE_REQUIRED.app,
                        api.FM_ASV_RETRIEVE_REQUIRED.method,
                        [ obj.session.key ],
                        true
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'asv',
                    [
                        api.FM_ASV_RETRIEVE.app,
                        api.FM_ASV_RETRIEVE.method,
                        [ obj.session.key ],
                        true
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        obj.error.sdump('D_DEBUG','_fm_objects = ' + js2JSON(this._fm_objects) + '\n');

        for (var i in this._fm_objects) {
            this.chain.push( gen_fm_retrieval_func(i,this._fm_objects[i]) );
        }

        // The previous org_tree call returned a tree, not a list or hash.
        this.chain.push(
            function () {
                obj.tree.aou = obj.list.aou;
                obj.list.aou = util.fm_utils.flatten_ou_branch( obj.tree.aou );
                for (var i = 0; i < obj.list.aou.length; i++) {
                    var c = obj.list.aou[i].children();
                    if (!c) c = [];
                    c = c.sort(
                        function( a, b ) {
                            if (a.shortname() < b.shortname()) return -1;
                            if (a.shortname() > b.shortname()) return 1;
                            return 0;
                        }
                    );
                    obj.list.aou[i].children( c );
                }
                obj.list.aou = util.fm_utils.flatten_ou_branch( obj.tree.aou );
                obj.hash.aou = util.functional.convert_object_list_to_hash( obj.list.aou );
            }
        );

        // The previous pgt call returned a tree, not a list or hash.
        this.chain.push(
            function () {
                obj.tree.pgt = obj.list.pgt;
                obj.list.pgt = util.fm_utils.flatten_ou_branch( obj.tree.pgt );
                obj.hash.pgt = util.functional.convert_object_list_to_hash( obj.list.pgt );
            }
        );

        // Do these after we get the user object

        this.chain.push(
            function() {
                try {
                    var robj = obj.network.simple_request('FM_AOUS_RETRIEVE',[ obj.session.key, obj.list.au[0].ws_ou() ]);
                    if (typeof robj.ilsevent != 'undefined') throw(robj);
                    obj.hash.aous = robj;
                    obj.data_progress('Retrieved org unit settings. ');
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(

            function() {

                gen_fm_retrieval_func('my_aou', 
                    [ 
                        api.FM_AOU_RETRIEVE_RELATED_VIA_SESSION.app,
                        api.FM_AOU_RETRIEVE_RELATED_VIA_SESSION.method,
                        [ obj.session.key, obj.list.au[0].ws_ou() ], /* use ws_ou and not home_ou */
                        true
                    ]
                )();
            }
        );

        this.chain.push(

            function () {

                gen_fm_retrieval_func( 'my_actsc', 
                    [ 
                        api.FM_ACTSC_RETRIEVE_VIA_AOU.app,
                        api.FM_ACTSC_RETRIEVE_VIA_AOU.method,
                        [ obj.session.key, obj.list.au[0].ws_ou() ],
                        true
                    ]
                )();
            }
        );

        this.chain.push(

            function () {

                gen_fm_retrieval_func( 'my_asc', 
                    [ 
                        api.FM_ASC_RETRIEVE_VIA_AOU.app,
                        api.FM_ASC_RETRIEVE_VIA_AOU.method,
                        [ obj.session.key, obj.list.au[0].ws_ou() ],
                        true
                    ]
                )();
            }
        );


        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'cnct',
                    [
                        api.FM_CNCT_RETRIEVE.app,
                        api.FM_CNCT_RETRIEVE.method,
                        [ obj.list.au[0].ws_ou() ], 
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'my_cnct',
                    [
                        api.FM_CNCT_RETRIEVE.app,
                        api.FM_CNCT_RETRIEVE.method,
                        [ obj.list.au[0].ws_ou() ], 
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'acpl',
                    [
                        api.FM_ACPL_RETRIEVE.app,
                        api.FM_ACPL_RETRIEVE.method,
                        [ obj.list.au[0].ws_ou() ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'csc',
                    [
                        api.FM_CSC_RETRIEVE_VIA_PCRUD.app,
                        api.FM_CSC_RETRIEVE_VIA_PCRUD.method,
                        [ obj.session.key, {"id":{"!=":null}}, {"order_by":{"csc":"name"}} ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'atb',
                    [
                        api.FM_ATB_RETRIEVE_VIA_PCRUD.app,
                        api.FM_ATB_RETRIEVE_VIA_PCRUD.method,
                        [
                            obj.session.key,
                            {
                                "-or": [
                                    { "ws" : obj.list.au[0].wsid() },
                                    { "usr" : obj.list.au[0].id() },
                                    { "org" : util.functional.map_list( obj.list.my_aou, function(o) { return o.id(); } ) }
                                ]
                            },
                            {
                                "order_by":{"atb":"label"}
                            }
                        ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );


        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'acnp',
                    [
                        api.FM_ACNP_RETRIEVE_VIA_PCRUD.app,
                        api.FM_ACNP_RETRIEVE_VIA_PCRUD.method,
                        [ obj.session.key, {"owning_lib":{"=":obj.list.au[0].ws_ou()}}, {"order_by":{"acnp":"label_sortkey"}} ],
                        false
                    ]
                );
                try {
                    f();
                    obj.list['acnp_for_lib_'+obj.list.au[0].ws_ou()] = obj.list.acnp;
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'acns',
                    [
                        api.FM_ACNS_RETRIEVE_VIA_PCRUD.app,
                        api.FM_ACNS_RETRIEVE_VIA_PCRUD.method,
                        [ obj.session.key, {"owning_lib":{"=":obj.list.au[0].ws_ou()}}, {"order_by":{"acns":"label_sortkey"}} ],
                        false
                    ]
                );
                try {
                    f();
                    obj.list['acns_for_lib_'+obj.list.au[0].ws_ou()] = obj.list.acns;
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        this.chain.push(
            function() {
                var f = gen_fm_retrieval_func(
                    'cbt',
                    [
                        api.FM_CBT_RETRIEVE.app,
                        api.FM_CBT_RETRIEVE.method,
                        [ obj.session.key, obj.list.au[0].ws_ou() ],
                        false
                    ]
                );
                try {
                    f();
                } catch(E) {
                    var error = 'Error: ' + js2JSON(E);
                    obj.error.sdump('D_ERROR',error);
                    throw(E);
                }
            }
        );

        if (typeof this.on_complete == 'function') {

            this.chain.push( this.on_complete );
        }
        JSAN.use('util.exec'); this.exec = new util.exec();
        this.exec.on_error = function(E) { 
        
            if (typeof obj.on_error == 'function') {
                return obj.on_error(E); /* false breaks chain */
            } else {
                alert('oops: ' + E ); 
                return false; /* break chain */
            }

        }

        this.exec.chain( this.chain );

    }
}

dump('exiting OpenILS/data.js\n');
