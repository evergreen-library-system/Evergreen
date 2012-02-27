dump('entering circ.checkout.js\n');

if (typeof circ == 'undefined') { circ = {}; }
circ.checkout = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.network'); this.network = new util.network();
    JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
    JSAN.use('util.money');
    JSAN.use('util.barcode');
};

circ.checkout.prototype = {

    'init' : function( params ) {

        var obj = this;

        obj.patron_id = params.patron_id;

        obj.auto_override_events = [];

        JSAN.use('circ.util');
        var columns = circ.util.columns( 
            { 
                'barcode' : { 'hidden' : false },
                'title' : { 'hidden' : false },
                'due_date' : { 'hidden' : false }
            } 
        );

        JSAN.use('util.list'); obj.list = new util.list('checkout_list');
        obj.list.init(
            {
                'columns' : columns,
                'on_select' : function() {
                    var sel = obj.list.retrieve_selection();
                    document.getElementById('clip_button').disabled = sel.length < 1;
                }
            }
        );
        
        JSAN.use('util.controller'); obj.controller = new util.controller();
        obj.controller.init(
            {
                'control_map' : {
                    'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
                    'sel_clip' : [
                        ['command'],
                        function() { obj.list.clipboard(); }
                    ],
                    'checkout_menu_placeholder' : [
                        ['render'],
                        function(e) {
                            return function() {
                                JSAN.use('util.widgets'); JSAN.use('util.functional'); JSAN.use('util.fm_utils');
                                var items = [ [ document.getElementById('circStrings').getString('staff.circ.checkout.barcode') , 'barcode' ] ].concat(
                                    util.functional.map_list(
                                        util.functional.filter_list(
                                            obj.data.list.my_cnct,
                                            function(o) {
                                                return util.fm_utils.compare_aou_a_is_b_or_ancestor(o.owning_lib(), obj.data.list.au[0].ws_ou());
                                            }
                                        ).sort(

                                            function(a,b) {
                                                try { 
                                                    return util.fm_utils.sort_func_aou_by_depth_and_then_string(
                                                        [ a.owning_lib(), a.name() ],
                                                        [ b.owning_lib(), b.name() ]
                                                    );
                                                } catch(E) {
                                                    alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkout.sorting.exception', [E]));
                                                    return 0;
                                                }
                                            }

                                        ),
                                        function(o) {
                                            return [ obj.data.hash.aou[ o.owning_lib() ].shortname() + ' : ' + o.name(), o.id() ];
                                        }
                                    )
                                );
                                g.error.sdump('D_TRACE','items = ' + js2JSON(items));
                                util.widgets.remove_children( e );
                                var ml = util.widgets.make_menulist(items);
                                e.appendChild( ml );
                                ml.setAttribute('id','checkout_menulist');
                                ml.setAttribute('accesskey','');
                                ml.addEventListener(
                                    'command',
                                    function(ev) {
                                        var tb = obj.controller.view.checkout_barcode_entry_textbox;
                                        var db = document.getElementById('duedate_hbox');
                                        if (ev.target.value == 'barcode') {
                                            db.hidden = false;
                                            tb.disabled = false;
                                            tb.value = '';
                                            tb.focus();
                                        } else {
                                            db.hidden = true;
                                            tb.disabled = true;
                                            tb.value = document.getElementById('circStrings').getString('staff.circ.non_cataloged');
                                        }
                                    }, false
                                );
                                obj.controller.view.checkout_menu = ml;
                            };
                        }
                    ],
                    'checkout_barcode_entry_textbox' : [
                        ['keypress'],
                        function(ev) {
                            if (ev.keyCode && ev.keyCode == 13) {
                                obj.checkout( { barcode: ev.target.value } );
                            }
                        }
                    ],
                    'checkout_duedate_datepicker' : [
                        ['change'],
                        function(ev) { 
                            try {
				document.getElementById('checkout_duedate_checkbox').checked = true;
                                if (obj.check_date(ev.target)) {
                                    ev.target.parentNode.setAttribute('style','');
                                } else {
                                    ev.target.parentNode.setAttribute('style','background-color: red');
                                }
                            } catch(E) {
                                alert('Error in checkout.js, checkout_duedate_datepicker @change: ' + E);
                            }
                        }
                    ],
                    'cmd_broken' : [
                        ['command'],
                        function() { alert(document.getElementById('circStrings').getString('staff.circ.checkout.unimplemented')); }
                    ],
                    'cmd_checkout_submit' : [
                        ['command'],
                        function() {
                            var params = {}; var count = 1;

                            if (obj.controller.view.checkout_menu.value == 'barcode' ||
                                obj.controller.view.checkout_menu.value === '') {
                                params.barcode = obj.controller.view.checkout_barcode_entry_textbox.value;
                            } else {
                                params.noncat = 1;
                                params.noncat_type = obj.controller.view.checkout_menu.value;
                                var r = window.prompt(
                                    document.getElementById('circStrings').getFormattedString('staff.circ.checkout.cmd_checkout_submit.msg', [obj.data.hash.cnct[params.noncat_type].name()]),
                                    '1',
                                    document.getElementById('circStrings').getString('staff.circ.checkout.cmd_checkout_submit.title')
                                );
                                if (r) {
                                    count = Number(r);
                                    if (count > 0) {
                                        if (count > 99) {
                                            obj.error.yns_alert(
                                                document.getElementById('circStrings').getFormattedString('staff.circ.checkout.cmd_checkout_submit.too_many.msg', [count, obj.data.hash.cnct[params.noncat_type].name()]),
                                                document.getElementById('circStrings').getString('staff.circ.checkout.cmd_checkout_submit.too_many.title'),
                                                document.getElementById('circStrings').getString('staff.circ.checkout.ok.btn'),
                                                null,
                                                null,
                                                document.getElementById('circStrings').getString('staff.circ.confirm')
                                            );
                                            return;
                                        } else if (count > 20) {
                                            r = obj.error.yns_alert(
                                                document.getElementById('circStrings').getFormattedString('staff.circ.checkout.cmd_checkout_submit.confirm.msg', [count, obj.data.hash.cnct[params.noncat_type].name()]),
                                                document.getElementById('circStrings').getString('staff.circ.checkout.cmd_checkout_submit.confirm.title'),
                                                document.getElementById('circStrings').getString('staff.circ.checkout.yes.btn'),
                                                document.getElementById('circStrings').getString('staff.circ.checkout.no.btn'),
                                                null,
                                                document.getElementById('circStrings').getString('staff.circ.confirm')
                                            );
                                            if (r !== 0) { return; }
                                        }
                                    } else {
                                        r = obj.error.yns_alert(
                                            document.getElementById('circStrings').getFormattedString('staff.circ.checkout.cmd_checkout_submit.non_numeric.msg', [r]),
                                            document.getElementById('circStrings').getString('staff.circ.checkout.cmd_checkout_submit.non_numeric.title'),
                                            document.getElementById('circStrings').getString('staff.circ.checkout.ok.btn'),
                                            null,
                                            null,
                                            document.getElementById('circStrings').getString('staff.circ.confirm')
                                        );
                                        return;
                                    }
                                } else {
                                    return;
                                }
                            }
                            for (var i = 0; i < count; i++) {
                                obj.checkout( params );
                            }
                        }
                    ],
                    'cmd_checkout_print' : [
                        ['command'],
                        function() {
                            try {
                                obj.print();
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_checkout_print',E);
                            }

                        }
                    ],
                    'cmd_checkout_export' : [
                        ['command'],
                        function() {
                            try {
                                obj.export_list();
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_checkout_export',E); 
                            }
                        }
                    ],


                    'cmd_checkout_reprint' : [
                        ['command'],
                        function() {
                            JSAN.use('util.print'); var print = new util.print();
                            print.reprint_last();
                        }
                    ],
                    'cmd_checkout_done' : [
                        ['command'],
                        function() {
                            try {
                                var no_print_prompting = obj.data.hash.aous['circ.staff_client.do_not_auto_attempt_print'];
                                if (no_print_prompting) {
                                    if (no_print_prompting.indexOf( "Checkout" ) > -1) {
                                        obj.list.clear();
                                        xulG.set_tab(urls.XUL_PATRON_BARCODE_ENTRY,{},{}); 
                                        return;
                                    }
                                }
                                if (document.getElementById('checkout_auto').checked) {
                                    obj.print(true,function() { 
                                        obj.list.clear();
                                        xulG.set_tab(urls.XUL_PATRON_BARCODE_ENTRY,{},{}); 
                                    });
                                } else {
                                    obj.print(false,function() {
                                        obj.list.clear();
                                        xulG.set_tab(urls.XUL_PATRON_BARCODE_ENTRY,{},{});
                                    });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_checkout_done',E);
                            }
                        }
                    ]
                }
            }
        );
        this.controller.render();
        //this.controller.view.checkout_barcode_entry_textbox.focus();

        this.check_disable();

        var robj = obj.network.simple_request(
            'FM_CIRC_COUNT_RETRIEVE_VIA_USER.authoritative',
            [ ses(), obj.patron_id ]
        );
        obj.items_out_count = (robj.out + robj.overdue + robj.claims_returned + robj.long_overdue );

    },

    'check_disable' : function() {
        var obj = this;
        try {
            if (typeof xulG.check_stop_checkouts == 'function') {
                var disable = xulG.check_stop_checkouts();
                if (disable) {
                    document.getElementById('checkout_submit_barcode_button').disabled = true;
                    document.getElementById('checkout_done').disabled = true;
                    document.getElementById('checkout_duedate_checkbox').disabled = true;
                    document.getElementById('checkout_duedate_timepicker').disabled = true;
                    obj.controller.view.checkout_menu.disabled = true;
                    obj.controller.view.checkout_barcode_entry_textbox.disabled = true;
                    obj.controller.view.checkout_duedate_datepicker.disabled = true;
                } else {
                    document.getElementById('checkout_submit_barcode_button').disabled = false;
                    document.getElementById('checkout_done').disabled = false;
                    document.getElementById('checkout_duedate_checkbox').disabled = false;
                    document.getElementById('checkout_duedate_timepicker').disabled = false;
                    obj.controller.view.checkout_menu.disabled = false;
                    obj.controller.view.checkout_barcode_entry_textbox.disabled = false;
                    obj.controller.view.checkout_duedate_datepicker.disabled = false;
                }
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.checkout.disable.error'),E);
        }
    },

    'print' : function(silent,f) {
        var obj = this;
        try {
            obj.patron = obj.network.simple_request('FM_AU_FLESHED_RETRIEVE_VIA_ID',[ses(),obj.patron_id]);
            var params = { 
                'patron' : obj.patron, 
                'lib' : obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ],
                'staff' : obj.data.list.au[0],
                'data' : {
                    'balance_owed' : util.money.sanitize( obj.most_recent_balance_owed ),
                },
                'printer_context' : 'receipt',
                'template' : 'checkout',
                'callback' : function() {
                    setTimeout(
                        function(){
                            if (typeof f == 'function') { 
                                setTimeout( 
                                    function() {
                                        f();
                                    }, 1000
                                );
                            } 
                        }, 1000
                    );
                }
            };
            if (silent) { params.no_prompt = true; }
            obj.list.print(params);
        } catch(E) {
            obj.error.standard_unexpected_error_alert('print',E);
        }
    },
    
    'export_list' : function(silent,f) {
        var obj = this;
        try {
            obj.list.dump_csv_to_clipboard();
        } catch(E) {
            obj.error.standard_unexpected_error_alert('export',E);
        }
    },

    'check_date' : function(node) {
        var obj = this;
        JSAN.use('util.date');
        try {
            obj.controller.view.checkout_barcode_entry_textbox.setAttribute('disabled','false');
            obj.controller.view.checkout_barcode_entry_textbox.disabled = false;
            obj.controller.view.cmd_checkout_submit.setAttribute('disabled','false');
            obj.controller.view.cmd_checkout_submit.disabled = false;
            if (util.date.check_past('YYYY-MM-DD',node.value) ) {
                obj.controller.view.checkout_barcode_entry_textbox.setAttribute('disabled','true');
                obj.controller.view.cmd_checkout_submit.setAttribute('disabled','true');
                return false;
            }
            return true;
        } catch(E) {
            throw(E);
        }
    },

    '_checkout_pending_hash' : {},

    '_checkout' : function(params,permit) {
        var obj = this;
        try {
        
            /**********************************************************************************************************************/
            /* This handles the return value of the checkout/renewal */
            function _checkout_callback(req,x) {
                try {

                    if (params.barcode) { 
                        delete obj._checkout_pending_hash[ params.barcode ];
                    }

                    var checkout = req.getResultObject();

                    if (checkout.ilsevent === '0') {
        
                        if (!checkout.payload) { checkout.payload = {}; }
        
                        if (!checkout.payload.circ) {
                            checkout.payload.circ = new aoc();
                            /*********************************************************************************************/
                            /* Non Cat */
                            if (checkout.payload.noncat_circ) {
                                checkout.payload.circ.circ_lib( checkout.payload.noncat_circ.circ_lib() );
                                checkout.payload.circ.circ_staff( checkout.payload.noncat_circ.staff() );
                                checkout.payload.circ.usr( checkout.payload.noncat_circ.patron() );
                                checkout.payload.circ.due_date( checkout.payload.noncat_circ.duedate() );
                            }
                        }
    
                        if (!checkout.payload.record) {
                            checkout.payload.record = new mvr();
                            /*********************************************************************************************/
                            /* Non Cat */
                            if (checkout.payload.noncat_circ) {
                                checkout.payload.record.title(
                                    obj.data.hash.cnct[ checkout.payload.noncat_circ.item_type() ].name()
                                );
                            }
                        }
            
                        if (!checkout.payload.copy) {
                            checkout.payload.copy = new acp();
                            checkout.payload.copy.barcode( '' );
                        }
            
                        /*********************************************************************************************/
                        /* Override mvr title/author with dummy title/author for Pre cat */
                        if (checkout.payload.copy.dummy_title()) {
                            checkout.payload.record.title( checkout.payload.copy.dummy_title() );
                        }
                        if (checkout.payload.copy.dummy_author()) {
                            checkout.payload.record.author( checkout.payload.copy.dummy_author() );
                        }
           
                        if (checkout.payload.patron_money) {
                            obj.most_recent_balance_owed = checkout.payload.patron_money.balance_owed();
                        }
 
                        obj.list.append(
                            {
                                'row' : {
                                    'my' : {
                                    'circ' : checkout.payload.circ,
                                    'mvr' : checkout.payload.record,
                                    'acp' : checkout.payload.copy,
                                    'acn' : checkout.payload.volume
                                    }
                                },
                                'to_top' : true
                            //I could override map_row_to_column here
                            }
                        );
                        var is_renewal = (
                            get_bool(checkout.payload.circ.opac_renewal())
                            ||get_bool(checkout.payload.circ.phone_renewal())
                            ||get_bool(checkout.payload.circ.desk_renewal())
                        );
                        try {
                            obj.error.work_log(
                                document.getElementById('circStrings').getFormattedString(
                                        is_renewal
                                        ? 'staff.circ.work_log_renew.message'
                                        : 'staff.circ.work_log_checkout.message',
                                    [
                                        ses('staff_usrname'),
                                        xulG.patron.family_name(),
                                        xulG.patron.card().barcode(),
                                        checkout.payload.copy.barcode()
                                    ]
                                ), {
                                    'au_id' : xulG.patron.id(),
                                    'au_family_name' : xulG.patron.family_name(),
                                    'au_barcode' : xulG.patron.card().barcode(),
                                    'acp_barcode' : checkout.payload.copy.barcode()
                                }
                            );
                        } catch(E) {
                            obj.error.sdump('D_ERROR','Error with work_logging in server/circ/checkout.js, _checkout:' + E);
                        }
                        document.getElementById('msg_area').removeChild(x);
                        /*
                        if (typeof obj.on_checkout == 'function') {
                            obj.on_checkout(checkout.payload);
                        }
                        */
                        if (typeof window.xulG == 'object' && typeof window.xulG.on_list_change == 'function') {
                            window.xulG.on_list_change(checkout.payload,is_renewal);
                        } else {
                            obj.error.sdump('D_CIRC','circ.checkout: No external .on_checkout()\n');
                        }
        
                    } else {
                        // Should get here with failed renewals
                        switch(Number(checkout.ilsevent)) {
                            case null /* custom event */ : 
                            case 5000 /* PERM_FAILURE */: 
                            case 1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */ : 
                            case 1213 /* PATRON_BARRED */ : 
                            case 1215 /* CIRC_EXCEEDS_COPY_RANGE */ : 
                            case 1224 /* PATRON_ACCOUNT_EXPIRED */ : 
                            case 1232 /* ITEM_DEPOSIT_REQUIRED */ : 
                            case 1233 /* ITEM_RENTAL_FEE_REQUIRED */ : 
                            case 1234 /* ITEM_DEPOSIT_PAID */ : 
                            case 1500 /* ACTION_CIRCULATION_NOT_FOUND */ : 
                            case 7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */ : 
                            case 7003 /* COPY_CIRC_NOT_ALLOWED */ : 
                            case 7004 /* COPY_NOT_AVAILABLE */ : 
                            case 7006 /* COPY_IS_REFERENCE */ : 
                            case 7007 /* COPY_NEEDED_FOR_HOLD */ : 
                            case 7008 /* MAX_RENEWALS_REACHED */ : 
                            case 7009 /* CIRC_CLAIMS_RETURNED */ : 
                            case 7010 /* COPY_ALERT_MESSAGE */ : 
                            case 7013 /* PATRON_EXCEEDS_FINES */ : 
                                x.setAttribute('style','color: red');
                                x.setAttribute('value', document.getElementById('circStrings').getFormattedString('staff.circ.checkout.barcode.failed', [params.barcode]));
                                if (typeof params.noncat == 'undefined') { obj.items_out_count--; }
                            break;
                            default: throw(checkout);
                        }
                    }
        
                } catch(E) {
                    x.setAttribute('style','color: red');
                    x.setAttribute('value', document.getElementById('circStrings').getFormattedString('staff.circ.checkout.barcode.failed', [params.barcode]));
                    if (typeof params.noncat == 'undefined') { obj.items_out_count--; }
                    obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkout.barcode.failed.alert', ['#3']),E);
                }
            }

            /**********************************************************************************************************************/
            /* This used to do the actual checkout/renewal */
        
            var x = document.createElement('label');
            x.setAttribute('style','color: green');
            if (params.barcode) {
                x.setAttribute('value',document.getElementById('circStrings').getFormattedString('staff.circ.checkout.barcode.pending', [params.barcode]));
            } else {
                x.setAttribute('value',document.getElementById('circStrings').getString('staff.circ.checkout.non_cataloged.pending'));
            }
            document.getElementById('msg_area').appendChild(x);

            /*
            obj.network.request(
                api.CHECKOUT.app,
                api.CHECKOUT.method,
                [ ses(), params, obj.items_out_count ],
                function(req) {
                    _checkout_callback(req,x);
                }
            );
            */
            
            if (typeof params.noncat == 'undefined') { obj.items_out_count++; }
           
           /* new */
            _checkout_callback({ 'getResultObject' : function() { return permit; } },x);

        } catch(E) {
            x.setAttribute('style','color: red');
            x.setAttribute('value', document.getElementById('circStrings').getFormattedString('staff.circ.checkout.barcode.failed', [params.barcode]));
            if (typeof params.noncat == 'undefined') { obj.items_out_count--; }
            obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkout.barcode.failed.alert', ['#2']),E);
        }
    },


    'test_barcode' : function(bc) {
        var obj = this;
        var x = document.getElementById('strict_barcode');
        if (x && x.checked !== true) { return true; }
        var good = util.barcode.check(bc);
        if (good) {
            return true;
        } else {
            if ( 1 == obj.error.yns_alert(
                        document.getElementById('circStrings').getFormattedString('staff.circ.check_digit.bad', [bc]),
                        document.getElementById('circStrings').getString('staff.circ.barcode.bad'),
                        document.getElementById('circStrings').getString('staff.circ.cancel'),
                        document.getElementById('circStrings').getString('staff.circ.barcode.accept'),
                        null,
                        document.getElementById('circStrings').getString('staff.circ.confirm'),
                        '/xul/server/skin/media/images/bad_barcode.png'
                )
            ) {
                return true;
            } else {
                return false;
            }
        }
    },

    'checkout' : function(params) {
        var obj = this;

        JSAN.use('util.date');
        if (document.getElementById('checkout_duedate_checkbox').checked) {
            if (! obj.check_date(obj.controller.view.checkout_duedate_datepicker)) return;
            var tp = document.getElementById('checkout_duedate_timepicker');
            var dp = obj.controller.view.checkout_duedate_datepicker;
            var tp_date = tp.dateValue;
            var dp_date = dp.dateValue;
            dp_date.setHours( tp_date.getHours() );
            dp_date.setMinutes( tp_date.getMinutes() );

            params.due_date = util.date.formatted_date(dp_date,'%{iso8601}');
        }

        if (typeof obj.on_checkout == 'function') { obj.on_checkout(params); }

        if (! (params.barcode||params.noncat)) { return; }

        if (params.barcode) {
            // Default is "just items"
            var barcode_context = 'asset';
            // Add actor (can be any string that includes 'actor') if looking up patrons at checkout
            if(String( obj.data.hash.aous['circ.staff_client.actor_on_checkout'] ) == 'true')
                barcode_context += '-actor';
            // Auto-complete the barcode
            var in_barcode = xulG.get_barcode(window, barcode_context, params.barcode);
            // user_false is "None of the above selected", don't error out/fall through as they already said no
            if(in_barcode == "user_false") return;
            // We have a barcode and there was no error?
            if(in_barcode && typeof in_barcode.ilsevent == 'undefined') {
                // Check if it was an actor barcode (will never happen unless actor was added above)
                if(in_barcode.type == 'actor') {
                    // Go to new patron (do not pass go, do not collect $200, do not prompt user)
                    var horizontal_interface = String( obj.data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
                    var loc = xulG.url_prefix( horizontal_interface ? 'XUL_PATRON_HORIZ_DISPLAY' : 'XUL_PATRON_DISPLAY' );
                    xulG.set_tab( loc, {}, { 'barcode' : in_barcode.barcode } );
                    return;
                }
                params.barcode = in_barcode.barcode;
            }

            if ( obj.test_barcode(params.barcode) ) { /* good */ } else { /* bad */ return; }

            if (typeof obj._checkout_pending_hash[ params.barcode ] != 'undefined') {

                obj.error.sdump('D_CIRC','Redundant barcode scan == ' + params.barcode);
                return; // redundant barcode scan

            } else {

                obj._checkout_pending_hash[ params.barcode ] = true;    

            }
        }


        /**********************************************************************************************************************/
        /* This used to be the Permissibility test before checkout */
        try {

            params.patron = obj.patron_id;

            var permit = obj.network.simple_request(
                //api.CHECKOUT_PERMIT.app,
                'CHECKOUT_FULL',
                [ ses(), params, obj.items_out_count ],
                null,
                {
                    'title' : document.getElementById('circStrings').getString('staff.circ.checkout.override.confirm'),
                    'overridable_events' : [ 
                        null /* custom event */,
                        1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */,
                        1213 /* PATRON_BARRED */,
                        1215 /* CIRC_EXCEEDS_COPY_RANGE */,
                        1232 /* ITEM_DEPOSIT_REQUIRED */,
                        1233 /* ITEM_RENTAL_FEE_REQUIRED */,
                        7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */,
                        7003 /* COPY_CIRC_NOT_ALLOWED */,
                        7004 /* COPY_NOT_AVAILABLE */, 
                        7006 /* COPY_IS_REFERENCE */, 
                        7010 /* COPY_ALERT_MESSAGE */,
                        7016 /* ITEM_ON_HOLDS_SHELF */,
                        7013 /* PATRON_EXCEEDS_FINES */
                    ],
                    'report_override_on_events' : [ /* Allow auto-override of Patron overrides only */
                        1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */,
                        1213 /* PATRON_BARRED */,
                        7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */,
                        7013 /* PATRON_EXCEEDS_FINES */
                    ],
                    'auto_override_these_events' : obj.auto_override_events,
                    'text' : {
                        '1212' : function(r) {
                            return document.getElementById('circStrings').getString('staff.circ.checkout.override.will_auto');
                        },
                        '1213' : function(r) {
                            return document.getElementById('circStrings').getString('staff.circ.checkout.override.will_auto');
                        },
                        '1232' : function(r) {
                            return document.getElementById('circStrings').getString('staff.circ.checkout.override.item_deposit_required.warning');
                        },
                        '1233' : function(r) {
                            return document.getElementById('circStrings').getString('staff.circ.checkout.override.item_rental_fee_required.warning');
                        },
                        '7002' : function(r) {
                            return document.getElementById('circStrings').getString('staff.circ.checkout.override.will_auto');
                        },
                        '7004' : function(r) {
                            try {
                                status_name = obj.data.hash.ccs[ r.payload.status() ].name();
                                return status_name;
                            } catch (E) {
                                return "Could not retrieve the name of the current status for the copy";  // XXX
                            }
                        },
                        '7010' : function(r) {
                            return r.payload;
                        },
                        '7013' : function(r) {
                            return document.getElementById('circStrings').getString('staff.circ.checkout.override.will_auto');
                        }
                    }
                }
            );

            if (!permit) { throw(permit); }

            function test_event(list,ev) {
                if (typeof list.ilsevent != 'undefined' ) {
                    if (list.ilsevent == ev) {
                        return list;
                    } else {
                        return false;
                    }
                } else {
                    for (var i = 0; i < list.length; i++) {
                        if (typeof list[i].ilsevent != 'undefined') {
                            if (list[i].ilsevent == ev) { return list[i]; }
                        }
                    }
                    return false;
                }
            }

            /**********************************************************************************************************************/
            /* Normal case, proceed with checkout */
            if (permit.ilsevent === '0') {
                if(permit._reported_events != 'undefined') {
                    obj.auto_override_events = obj.auto_override_events.concat(permit._reported_events);
                }
                JSAN.use('util.sound'); var sound = new util.sound(); sound.circ_good();
                params.permit_key = permit.payload;
                obj._checkout( params, permit ); 

            /**********************************************************************************************************************/
            /* Item not cataloged or barcode mis-scan.  Prompt for pre-cat option */
            } else {
            
                if (params.barcode) { delete obj._checkout_pending_hash[ params.barcode ];    }

                var found_handled = false; var found_not_handled = false; var msg = '';    

                if (test_event(permit,1202 /* ITEM_NOT_CATALOGED */)) {

                    if ( 1 == obj.error.yns_alert(
                        document.getElementById('circStrings').getString('staff.circ.checkout.not_cataloged.confirm'),
                        document.getElementById('circStrings').getString('staff.circ.alert'),
                        document.getElementById('circStrings').getString('staff.circ.cancel'),
                        document.getElementById('circStrings').getString('staff.circ.pre_cataloged'),
                        null,
                        document.getElementById('circStrings').getString('staff.circ.confirm'),
                        '/xul/server/skin/media/images/book_question.png'
                    ) ) {

                        obj.data.dummy_title = ''; obj.data.dummy_author = ''; obj.data.stash('dummy_title','dummy_author');
                        JSAN.use('util.window'); var win = new util.window();
                        win.open(urls.XUL_PRE_CAT, 'dummy_fields', 'chrome,resizable,modal');
                        obj.data.stash_retrieve();

                        params.permit_key = permit.payload;
                        params.dummy_title = obj.data.precat_dummy_title;
                        params.dummy_author = obj.data.precat_dummy_author;
                        params.dummy_isbn = obj.data.precat_dummy_isbn;
                        params.circ_modifier = obj.data.precat_circ_modifier;
                        params.precat = 1;

                        if (obj.data.precat_submit == 'go') { 
                            //obj._checkout( params ); No real request method here anymore
                            obj.checkout( params );
                        } else {
                            alert(document.getElementById('circStrings').getString('staff.circ.checkout.cancelled'));
                        }
                    }

                    return;
                }

                var test_permit;
                if (typeof permit.ilsevent != 'undefined') { test_permit = [ permit ]; } else { test_permit = permit; }

                var stop_checkout = false;
                for (var i = 0; i < test_permit.length; i++) {
                    switch(Number(test_permit[i].ilsevent)) {
                        case 1216 /* PATRON_CARD_INACTIVE */ :
                        case 1217 /* PATRON_INACTIVE */ :
                        case 1224 /* PATRON_ACCOUNT_EXPIRED */ :
                            stop_checkout = true;
                        break;
                    }
                }

                for (var i = 0; i < test_permit.length; i++) {
                    dump('found [' + test_permit[i].ilsevent + ']\n');
                    switch(test_permit[i].ilsevent == null || test_permit[i].ilsevent == '' ? null : Number(test_permit[i].ilsevent)) {
                        case null /* custom event */ :
                            found_handled = true;
                        break;
                        case 1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */ :
                            found_handled = true;
                        break;
                        case 1213 /* PATRON_BARRED */ :
                            found_handled = true;
                        break;
                        case 1215 /* CIRC_EXCEEDS_COPY_RANGE */ :
                            found_handled = true;
                        break;
                        case 1216 /* PATRON_CARD_INACTIVE */ :
                            found_handled = true;
                            msg += document.getElementById('circStrings').getString('staff.circ.checkout.card.inactive') + '\n';
                            obj.error.yns_alert(
                                msg,
                                document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                document.getElementById('circStrings').getString('staff.circ.checkout.ok.btn'),
                                null,
                                null,
                                document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                            );
                        break;
                        case 1217 /* PATRON_INACTIVE */ :
                            found_handled = true;
                            msg += document.getElementById('circStrings').getString('staff.circ.checkout.account.inactive') + '\n';
                            obj.error.yns_alert(
                                msg,
                                document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                document.getElementById('circStrings').getString('staff.circ.checkout.ok.btn'),
                                null,
                                null,
                                document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                            );
                        break;
                        case 1224 /* PATRON_ACCOUNT_EXPIRED */ :
                            found_handled = true;
                            msg += document.getElementById('circStrings').getString('staff.circ.checkout.account.expired') + '\n';
                            obj.error.yns_alert(
                                msg,
                                document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                document.getElementById('circStrings').getString('staff.circ.checkout.ok.btn'),
                                null,
                                null,
                                document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                            );
                        break;
                        case 1232 /* ITEM_DEPOSIT_REQUIRED */ :
                        case 1233 /* ITEM_RENTAL_FEE_REQUIRED */ :
                        case 7013 /* PATRON_EXCEEDS_FINES */ :
                            found_handled = true;
                        break;
                        case 7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */ :
                            found_handled = true;
                        break;
                        case 7003 /* COPY_CIRC_NOT_ALLOWED */ :
                            found_handled = true;
                        break;
                        case 7004 /* COPY_NOT_AVAILABLE */ :
                            msg += test_permit[i].desc + '\n' + document.getElementById('circStrings').getFormattedString('staff.circ.checkout.copy_status', [obj.data.hash.ccs [test_permit[i].payload.status() ].name()]) + '\n';
                            found_handled = true;
                        break;
                        case 7006 /* COPY_IS_REFERENCE */ :
                            msg += test_permit[i].desc + '\n';
                            found_handled = true;
                        break;
                        case 7009 /* CIRC_CLAIMS_RETURNED */ :
                            msg += test_permit[i].desc + '\n';
                            obj.error.yns_alert(
                                msg,
                                document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                document.getElementById('circStrings').getString('staff.circ.checkout.ok.btn'),
                                null,
                                null,
                                document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                            );
                            found_handled = true;
                        break;
                        case 7010 /* COPY_ALERT_MESSAGE */ :
                            msg += test_permit[i].desc + '\n' + document.getElementById('circStrings').getFormattedString('staff.circ.checkout.alert_message', [test_permit[i].payload]) + '\n';
                            found_handled = true;
                        break;
                        case 7016 /* ITEM_ON_HOLDS_SHELF */ :
                            msg += test_permit[i].desc + '\n';
                            found_handled = true;
                        break;
                        case 1202 /* ITEM_NOT_CATALOGED */ :
                            found_handled = true;
                        break;
                        case 5000 /* PERM_FAILURE */ :
                            msg += test_permit[i].desc + '\n' + document.getElementById('circStrings').getFormattedString('staff.circ.checkout.permission_denied', [test_permit[i].ilsperm]) + '\n';
                            found_handled = true;
                        break;
                        case 1702 /* OPEN_CIRCULATION_EXISTS */ :
                            msg += test_permit[i].desc + '\n';
                            found_handled = true;
                            var foreign_circ = true;
                            var my_circ; 

                            var payload = test_permit[i].payload;
                            if (payload) {
                                if (typeof payload.old_circ == 'object') {
                                    foreign_circ = false;
                                    my_circ = payload.old_circ;
                                }
                            }

                            if (foreign_circ) {
                                var my_copy = obj.network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[params.barcode]);
                                if (typeof my_copy.ilsevent != 'undefined') { throw(my_copy); }
                                my_circ = obj.network.simple_request('FM_CIRC_RETRIEVE_VIA_COPY',[ses(),my_copy.id(),1]);
                                if (typeof my_circ.ilsevent != 'undefined') { throw(my_copy); }
                                my_circ = my_circ[0];
                            }

                            if (! stop_checkout ) {

                                var due_date = my_circ.due_date() ? util.date.formatted_date( my_circ.due_date(), '%F' ) : null;
                                JSAN.use('util.date'); var today = util.date.formatted_date(new Date(),'%F');
                                if (due_date) {
                                    if (today > due_date) {
                                        msg += (document.getElementById('circStrings').getFormattedString('staff.circ.checkout.item_due', [ util.date.formatted_date( my_circ.due_date(), '%{localized}' ) ]) + '\n');
                                    }
                                }

                                if (foreign_circ) { // OFFER CANCEL, NORMAL CHECKIN, AND POSSIBLY FORGIVING-BACKDATED CHECKIN
                                    var r = obj.error.yns_alert(
                                        msg,
                                        document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                        document.getElementById('circStrings').getString('staff.circ.cancel'),
                                        document.getElementById('circStrings').getString('staff.circ.checkout.normal_checkin_then_checkout'),
                                        due_date ? (today > due_date ? document.getElementById('circStrings').getString('staff.circ.checkout.forgiving_checkin_then_checkout') : null) : null,
                                        document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                                    );
                                    JSAN.use('circ.util');
                                    switch(r) {
                                        case 1:
                                            circ.util.checkin_via_barcode( ses(), { 'barcode' : params.barcode, 'noop' : 1 } );
                                            obj.checkout(params);
                                        break;
                                        case 2:
                                            circ.util.checkin_via_barcode( ses(), { 'barcode' : params.barcode, 'noop' : 1 }, due_date );
                                            obj.checkout(params);
                                        break;
                                    }
                                } else { // EITHER AUTO-RENEW OR OFFER CANCEL, NORMAL CHECKIN, AND RENEW
                                    if (payload.auto_renew) {
                                        circ.util.renew_via_barcode( { 'barcode': params.barcode, 'patron' : obj.patron_id }, function(r) {
                                            try {
                                                params.renewal = true;
                                                obj._checkout( params, r[0] ); 
                                            } catch(E) {
                                                alert('Error in checkout.js, RENEW 1: ' + E);
                                            }
                                        } );
                                    } else {
                                        var r = obj.error.yns_alert(
                                            msg,
                                            document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                            document.getElementById('circStrings').getString('staff.circ.cancel'),
                                            document.getElementById('circStrings').getString('staff.circ.checkout.normal_checkin_then_checkout'),
                                            document.getElementById('circStrings').getString('staff.circ.checkout.offer_renewal'),
                                            document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                                        );
                                        JSAN.use('circ.util');
                                        switch(r) {
                                            case 1:
                                                circ.util.checkin_via_barcode( ses(), { 'barcode' : params.barcode, 'noop' : 1 } );
                                                obj.checkout(params);
                                            break;
                                            case 2:
                                                circ.util.renew_via_barcode( { 'barcode' : params.barcode, 'patron' : obj.patron_id }, function(r) {
                                                    try {
                                                        params.renewal = true;
                                                        obj._checkout( params, r[0] ); 
                                                    } catch(E) {
                                                        alert('Error in checkout.js, RENEW 2: ' + E);
                                                    }
                                                } );
                                            break;
                                        }
                                    }
                                }
                            } else {
                                obj.error.yns_alert(
                                    msg,
                                    document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                    document.getElementById('circStrings').getString('staff.circ.checkout.ok.btn'),
                                    null,
                                    null,
                                    document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                                );
                            }
                        break;
                        case 7014 /* COPY_IN_TRANSIT */ :
                            msg += test_permit[i].desc + '\n';
                            found_handled = true;
                            if (! stop_checkout ) {
                                var r = obj.error.yns_alert(
                                    msg,
                                    document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                    document.getElementById('circStrings').getString('staff.circ.cancel'),
                                    document.getElementById('circStrings').getString('staff.circ.checkout.abort_transit_then_checkout'),
                                    null,
                                    document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                                );
                                if (r == 1) {
                                    var robj = obj.network.simple_request('FM_ATC_VOID',[ ses(), { 'barcode' : params.barcode } ]);
                                    if (typeof robj.ilsevent == 'undefined') {
                                        obj.checkout(params);
                                    } else {
                                        switch(Number(robj.ilsevent)) {
                                            case 1225 /* TRANSIT_ABORT_NOT_ALLOWED */ :
                                                alert(robj.desc);
                                            break;
                                            case 5000 /* PERM_FAILURE */ :
                                            break;
                                            default:
                                                throw(robj);
                                            break;
                                        }
                                    }
                                }
                            } else {
                                obj.error.yns_alert(
                                    msg,
                                    document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                    document.getElementById('circStrings').getString('staff.circ.checkout.ok.btn'),
                                    null,
                                    null,
                                    document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                                );
                            }
                        break;
                        case -1 /* NETWORK_FAILURE */ :
                            msg += document.getElementById('circStrings').getString('staff.circ.checkout.network_failure') + '\n';
                            found_handled = true;
                            obj.error.yns_alert(
                                msg,
                                document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),
                                document.getElementById('circStrings').getString('staff.circ.checkout.ok.btn'),
                                null,
                                null,
                                document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                            );
                        break;
                        default:
                            msg += 'FIXME: ' + js2JSON(test_permit[i]) + '\n';
                            found_not_handled = true;
                        break;
                    }
                }
                
                if (found_not_handled) {
                    obj.error.standard_unexpected_error_alert(msg,permit);
                }

                obj.controller.view.checkout_barcode_entry_textbox.select();
                obj.controller.view.checkout_barcode_entry_textbox.focus();
            }

        } catch(E) {
            if (params.barcode) { delete obj._checkout_pending_hash[ params.barcode ];    }
            if (typeof E.ilsevent != 'undefined' && E.ilsevent == -1) {
                obj.error.standard_network_error_alert(document.getElementById('circStrings').getString('staff.circ.checkout.suggest_offline'));
            } else {
                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.checkout.barcode.check_out_failed'),E);
            }
            if (typeof obj.on_failure == 'function') {
                obj.on_failure(E);
            }
            if (typeof window.xulG == 'object' && typeof window.xulG.on_failure == 'function') {
                obj.error.sdump('D_CIRC','circ.checkout: Calling external .on_failure()\n');
                window.xulG.on_failure(E);
            } else {
                obj.error.sdump('D_CIRC','circ.checkout: No external .on_failure()\n');
            }
        }

    },

    'on_checkout' : function() {
        this.controller.view.checkout_menu.selectedIndex = 0;
        this.controller.view.checkout_barcode_entry_textbox.disabled = false;
        this.controller.view.checkout_barcode_entry_textbox.value = '';
        this.controller.view.checkout_barcode_entry_textbox.focus();
        document.getElementById('duedate_hbox').hidden = false;
    },

    'on_failure' : function() {
        this.controller.view.checkout_barcode_entry_textbox.select();
        this.controller.view.checkout_barcode_entry_textbox.focus();
    }
};

dump('exiting circ.checkout.js\n');
