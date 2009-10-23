dump('entering patron.summary.js\n');

function $(id) { return document.getElementById(id); }
var patronStrings = $('patronStrings');

if (typeof patron == 'undefined') patron = {};
patron.summary = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.window'); this.window = new util.window();
    JSAN.use('util.network'); this.network = new util.network();
    JSAN.use('util.widgets');
    this.w = window;
}

patron.summary.prototype = {

    'init' : function( params ) {

        var obj = this;

        obj.barcode = params['barcode'];
        obj.id = params['id'];
        if (params['show_name']) {
            document.getElementById('patron_name').hidden = false;
            document.getElementById('patron_name').setAttribute('hidden','false');
        }

        JSAN.use('OpenILS.data'); this.OpenILS = {}; 
        obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});
        var obscure_dob = String( obj.OpenILS.data.hash.aous['circ.obscure_dob'] ) == 'true';

        JSAN.use('util.controller'); obj.controller = new util.controller();
        obj.controller.init(
            {
                control_map : {
                    'cmd_broken' : [
                        ['command'],
                        function() { alert($("commonStrings").getString('common.unimplemented')); }
                    ],
                    'patron_alert' : [
                        ['render'],
                        function(e) {
                            return function() {
                                util.widgets.set_text( e, obj.patron.alert_message() || '' );
                                if (obj.patron.alert_message()) {
                                    e.parentNode.hidden = false;
                                } else {
                                    e.parentNode.hidden = true;
                                }
                            };
                        }
                    ],
                    'patron_usrname' : [
                        ['render'],
                        function(e) {
                            return function() {
                                util.widgets.set_text(e,obj.patron.usrname());
                            };
                        }
                    ],
                    'patron_profile' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.OpenILS.data.hash.pgt[
                                        obj.patron.profile()
                                    ].name()
                                );
                            };
                        }
                    ],
                    'patron_net_access' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    patronStrings.getString('staff.patron.summary.patron_net_access') + 
                                    ' ' + obj.OpenILS.data.hash.cnal[
                                        obj.patron.net_access_level()
                                    ].name()
                                );
                            };
                        }
                    ],
                    'patron_credit' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                JSAN.use('util.money');
                                util.widgets.set_text(e,
                                    '$' + 
                                    util.money.sanitize(
                                        obj.patron.credit_forward_balance()
                                    )
                                );
                            };
                        }
                    ],
                    'patron_bill' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,'...');
                                var under_btn; 
                                if (xulG) {
                                    if (xulG.display_window) {
                                        under_btn = xulG.display_window.document.getElementById('under_bills');
                                        if (under_btn) util.widgets.set_text(under_btn,'...');
                                    }
                                }
                                obj.network.simple_request(
                                    'FM_MOUS_RETRIEVE.authoritative',
                                    [ ses(), obj.patron.id() ],
                                    function(req) {
                                        try {
                                            JSAN.use('util.money');
                                            var robj = req.getResultObject();
                                            util.widgets.set_text(e, patronStrings.getFormattedString('staff.patron.summary.patron_bill.money', [util.money.sanitize( robj.balance_owed() )]));
                                            if (under_btn) util.widgets.set_text(under_btn, 
                                                patronStrings.getFormattedString('staff.patron.summary.patron_bill.money', [util.money.sanitize( robj.balance_owed() )]));
                                            var show_billing_tab_on_bills = String( obj.OpenILS.data.hash.aous['ui.circ.show_billing_tab_on_bills'] ) == 'true';
                                            if (show_billing_tab_on_bills && Number(robj.balance_owed()) > 0) {
                                                if (xulG) {
                                                    if (xulG.display_window) {
                                                        if (! obj.show_billing_tab_on_bills_done_once ) {
                                                            xulG.display_window.util.widgets.dispatch('command','cmd_patron_bills');
                                                            obj.show_billing_tab_on_bills_done_once = 1;
                                                        }
                                                    }
                                                }
                                            }
                                            obj.bills_summary = robj;
                                            if (obj.holds_summary && obj.bills_summary) 
                                                if (typeof window.xulG == 'object' && typeof window.xulG.stop_sign_page == 'function')
                                                    window.xulG.stop_sign_page( obj.patron, { 'holds_summary' : obj.holds_summary, 'bills_summary' : obj.bills_summary } ); 
                                        } catch(E) {
                                            alert('Error in summary.js, patron_bill callback: ' + E);
                                        }
                                    }
                                );
                            };
                        }
                    ],
                    'patron_checkouts' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,'...');
                                var e2 = document.getElementById( 'patron_overdue' ); if (e2) util.widgets.set_text(e2,'...');
                                var e3 = document.getElementById( 'patron_claimed_returned' ); if (e3) util.widgets.set_text(e3,'...');
                                var e4 = document.getElementById( 'patron_long_overdue' ); if (e4) util.widgets.set_text(e4,'...');
                                var e5 = document.getElementById( 'patron_lost' ); if (e5) util.widgets.set_text(e5,'...');
                                var e6 = document.getElementById( 'patron_noncat' ); if (e6) util.widgets.set_text(e6,'...');
                                var under_btn; 
                                if (xulG) {
                                    if (xulG.display_window) {
                                        under_btn = xulG.display_window.document.getElementById('under_items');
                                        if (under_btn) util.widgets.set_text(under_btn,'...');
                                    }
                                }
                                obj.network.simple_request(
                                    'FM_CIRC_COUNT_RETRIEVE_VIA_USER.authoritative',
                                    [ ses(), obj.patron.id() ],
                                    function(req) {
                                        try {
                                            var robj = req.getResultObject();
                                            util.widgets.set_text(e, robj.out + robj.overdue + robj.claims_returned + robj.long_overdue );
                                            if (e2) util.widgets.set_text(e2, robj.overdue    );
                                            if (e3) util.widgets.set_text(e3, robj.claims_returned    );
                                            if (e4) util.widgets.set_text(e4, robj.long_overdue    );
                                            if (e5) util.widgets.set_text(e5, robj.lost    );
                                            if (under_btn) util.widgets.set_text(under_btn, 
                                                String( robj.out + robj.overdue + robj.claims_returned + robj.long_overdue) + 
                                                ( robj.overdue > 0 ? '*' : '' )
                                            );
                                        } catch(E) {
                                            alert(E);
                                        }
                                    }
                                );
                                obj.network.simple_request(
                                    'FM_ANCC_RETRIEVE_VIA_USER.authoritative',
                                    [ ses(), obj.patron.id() ],
                                    function(req) {
                                        var robj = req.getResultObject();
                                        if (e6) util.widgets.set_text(e6,robj.length);
                                    }
                                );
                            };
                        }
                    ],
                    'patron_overdue' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                /* handled by 'patron_checkouts' */
                            };
                        }
                    ],
                    'patron_holds' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,'...');
                                var e2 = document.getElementById('patron_holds_available');
                                if (e2) util.widgets.set_text(e2,'...');
                                var under_btn; 
                                if (xulG) {
                                    if (xulG.display_window) {
                                        under_btn = xulG.display_window.document.getElementById('under_holds');
                                        if (under_btn) util.widgets.set_text(under_btn,'...');
                                    }
                                }
                                obj.network.simple_request(
                                    'FM_AHR_COUNT_RETRIEVE.authoritative',
                                    [ ses(), obj.patron.id() ],
                                    function(req) {
                                        var robj = req.getResultObject();
                                        util.widgets.set_text(e,
                                            robj.total
                                        );
                                        if (e2) util.widgets.set_text(e2,
                                            robj.ready
                                        );
                                        if (under_btn) util.widgets.set_text(under_btn, req.getResultObject().ready + '/' + req.getResultObject().total );
                                        obj.holds_summary = robj;
                                        if (obj.holds_summary && obj.bills_summary) 
                                            if (typeof window.xulG == 'object' && typeof window.xulG.stop_sign_page == 'function')
                                                window.xulG.stop_sign_page( obj.patron, { 'holds_summary' : obj.holds_summary, 'bills_summary' : obj.bills_summary } ); 
                                    }
                                );
                            };
                        }
                    ],
                    'patron_holds_available' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                /* handled by 'patron_holds' */
                            };
                        }
                    ],
                    'patron_card' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.card().barcode()
                                );
                            };
                        }
                    ],
                    'patron_ident_type_1' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                var ident_string = '';
                                var ident = obj.OpenILS.data.hash.cit[
                                    obj.patron.ident_type()
                                ];
                                if (ident) ident_string = ident.name()
                                util.widgets.set_text(e,
                                    ident_string
                                );
                            };
                        }
                    ],
                    'patron_ident_value_1' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                var val = obj.patron.ident_value();
                                val = val.replace(/.+(\d\d\d\d)$/,'xxxx$1');
                                util.widgets.set_text(e, val);
                            };
                        }
                    ],
                    'patron_ident_type_2' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                var ident_string = '';
                                var ident = obj.OpenILS.data.hash.cit[
                                    obj.patron.ident_type2()
                                ];
                                if (ident) ident_string = ident.name()
                                util.widgets.set_text(e,
                                    ident_string
                                );
                            };
                        }
                    ],
                    'patron_ident_value_2' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                var val = obj.patron.ident_value2();
                                val = val.replace(/.+(\d\d\d\d)$/,'xxxx$1');
                                util.widgets.set_text(e, val);
                            };
                        }
                    ],
                    'patron_date_of_exp' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    patronStrings.getString('staff.patron.summary.expires_on') + ' ' + (
                                        obj.patron.expire_date() ?
                                        obj.patron.expire_date().substr(0,10) :
                                        patronStrings.getString('staff.patron.field.unset') 
                                    )
                                );
                            };
                        }
                    ],
                    'patron_hold_alias' : [
                        ['render'],
                        function(e) {
                            return function() {
                                util.widgets.set_text(e,
                                    obj.patron.alias() ? obj.patron.alias() : ''
                                );
                            }
                        }
                    ],
                    'patron_date_of_birth' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                var hide_value = e.getAttribute('hide_value');
                                if ( obscure_dob && hide_value == 'true' ) {
                                    e.setAttribute( 'hidden_value',
                                        obj.patron.dob() ?
                                        obj.patron.dob().substr(0,10) :
                                        patronStrings.getString('staff.patron.field.unset') 
                                    );
                                    util.widgets.set_text(e,
                                        patronStrings.getString('staff.patron.field.hidden') 
                                    );
                                } else {
                                    util.widgets.set_text(e,
                                        obj.patron.dob() ?
                                        obj.patron.dob().substr(0,10) :
                                        patronStrings.getString('staff.patron.field.unset') 
                                    );
                                    e.setAttribute( 'hidden_value',
                                        patronStrings.getString('staff.patron.field.hidden') 
                                    );
                                }
                                var x = document.getElementById('PatronSummaryContact_date_of_birth_label');
                                if (x) {
                                    var click_to_hide_dob = x.getAttribute('click_to_hide_dob');
                                    if (!obscure_dob || click_to_hide_dob != 'true') {
                                        removeCSSClass(x,'click_link');
                                    } 
                                    if (obscure_dob && click_to_hide_dob == 'true') {
                                        addCSSClass(x,'click_link');
                                        x.onclick = function() {
                                            hide_value = e.getAttribute('hide_value');
                                            e.setAttribute('hide_value', hide_value == 'true' ? 'false' : 'true'); 
                                            var value = util.widgets.get_text(e);
                                            var hidden_value = e.getAttribute('hidden_value');
                                            util.widgets.set_text(e,hidden_value);
                                            e.setAttribute('hidden_value',value);
                                        }
                                    }
                                }
                            };
                        }
                    ],
                    'patron_day_phone' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.day_phone()
                                );
                            };
                        }
                    ],
                    'patron_evening_phone' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.evening_phone()
                                );
                            };
                        }
                    ],
                    'patron_other_phone' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.other_phone()
                                );
                            };
                        }
                    ],
                    'patron_email' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.email()
                                );
                            };
                        }
                    ],
                    'patron_alias' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.alias()
                                );
                            };
                        }
                    ],
                    'patron_photo_url' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                e.setAttribute('src',
                                    obj.patron.photo_url()
                                );
                            };
                        }
                    ],
                    'patron_library' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.OpenILS.data.hash.aou[
                                        obj.patron.home_ou()
                                    ].shortname()
                                );
                                e.setAttribute('tooltiptext',
                                    obj.OpenILS.data.hash.aou[
                                        obj.patron.home_ou()
                                    ].name()
                                );
                            };
                        }
                    ],
                    'patron_last_library' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.OpenILS.data.hash.aou[
                                        obj.patron.home_ou()
                                    ].shortname()
                                );
                                e.setAttribute('tooltiptext',
                                    obj.OpenILS.data.hash.aou[
                                        obj.patron.home_ou()
                                    ].name()
                                );
                            };
                        }
                    ],
                    'patron_mailing_address_street1' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.mailing_address().street1()
                                );
                                if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ],
                    'patron_mailing_address_street2' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.mailing_address().street2()
                                );
                                if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ],
                    'patron_mailing_address_city' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.mailing_address().city()
                                );
                                if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ],
                    'patron_mailing_address_state' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.mailing_address().state()
                                );
                                if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ],
                    'patron_mailing_address_post_code' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.mailing_address().post_code()
                                );
                                if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ],
                    'patron_physical_address_street1' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.billing_address().street1()
                                );
                                if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ],
                    'patron_physical_address_street2' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.billing_address().street2()
                                );
                                if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ],
                    'patron_physical_address_city' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.billing_address().city()
                                );
                                if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ],
                    'patron_physical_address_state' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.billing_address().state()
                                );
                                if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ],
                    'patron_physical_address_post_code' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                util.widgets.set_text(e,
                                    obj.patron.billing_address().post_code()
                                );
                                if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
                            };
                        }
                    ]
                }
            }
        );

        obj.retrieve();

        try {
            var caption = document.getElementById("PatronSummaryContact_caption");
            var arrow = document.getAnonymousNodes(caption)[0];
            var gb_content = document.getAnonymousNodes(caption.parentNode)[1];
            arrow.addEventListener(
                'click',
                function() {
                    setTimeout(
                        function() {
                            //alert('setting shrink_state to ' + gb_content.hidden);
                            //caption.setAttribute('shrink_state',gb_content.hidden);
                            netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
                            JSAN.use('util.file'); var file = new util.file('patron_id_shrink');
                            file.set_object(String(gb_content.hidden)); file.close();
                        }, 0
                    );
                }, false
            );
            //var shrink_state = caption.getAttribute('shrink_state');
            var shrink_state = false;
            netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
            JSAN.use('util.file'); var file = new util.file('patron_id_shrink');
            if (file._file.exists()) {
                shrink_state = file.get_object(); file.close();
            }
            //alert('shrink_state retrieved as ' + shrink_state);
            if (shrink_state != 'false' && shrink_state) {
                //alert('clicking the widget');
                util.widgets.click( arrow );
            }
        } catch(E) {
            obj.error.sdump('D_ERROR','with shrink_state in summary.js: ' + E);
        }
    },

    'retrieve' : function() {

        try {

            var obj = this;

            var chain = [];

            // Retrieve the patron
                function blah_retrieve() {
                    try {
                        var robj;
                        if (obj.barcode && obj.barcode != 'null') {
                            robj = obj.network.simple_request(
                                'FM_AU_RETRIEVE_VIA_BARCODE.authoritative',
                                [ ses(), obj.barcode ]
                            );
                        } else if (obj.id && obj.id != 'null') {
                            robj = obj.network.simple_request(
                                'FM_AU_FLESHED_RETRIEVE_VIA_ID',
                                [ ses(), obj.id ]
                            );
                        } else {
                            throw(patronStrings.getString('staff.patron.summary.retrieve.no_barcode'));
                        }
                        if (robj) {

                            if (instanceOf(robj,au)) {

                                obj.patron = robj;
                                JSAN.use('patron.util');
                                util.widgets.set_text('patron_name',
                                    patron.util.format_name( obj.patron )
                                );
                                patron.util.set_penalty_css(obj.patron);
                                JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
                                data.last_patron = obj.patron.id(); data.stash('last_patron');

                            } else {

                                throw(robj);

                            }
                        } else {

                            throw(robj);

                        }

                    } catch(E) {
                        throw(E);
                    }
                };
                blah_retrieve();

            /*
            // Retrieve the survey responses for required surveys
            chain.push(
                function() {
                    try {
                        var surveys = obj.OpenILS.data.list.my_asv;
                        var survey_responses = {};
                        for (var i = 0; i < surveys.length; i++) {
                            var s = obj.network.request(
                                api.FM_ASVR_RETRIEVE.app,
                                api.FM_ASVR_RETRIEVE.method,
                                [ ses(), surveys[i].id(), obj.patron.id() ]
                            );
                            survey_responses[ surveys[i].id() ] = s;
                        }
                        obj.patron.survey_responses( survey_responses );
                    } catch(E) {
                        var error = ('patron.summary.retrieve : ' + js2JSON(E));
                        obj.error.sdump('D_ERROR',error);
                        throw(error);
                    }
                }
            );
            */

            // Update the screen
            chain.push( function() { obj.controller.render(); } );

            // On Complete

            chain.push( function() {

                if (typeof window.xulG == 'object' && typeof window.xulG.on_finished == 'function') {
                    obj.error.sdump('D_PATRON_SUMMARY',
                        'patron.summary: Calling external .on_finished()\n');
                    window.xulG.on_finished(obj.patron);
                } else {
                    obj.error.sdump('D_PATRON_SUMMARY','patron.summary: No external .on_finished()\n');
                }

            } );

            // Do it
            JSAN.use('util.exec'); obj.exec = new util.exec();
            obj.exec.on_error = function(E) {

                if (typeof window.xulG == 'object' && typeof window.xulG.on_error == 'function') {
                    window.xulG.on_error(E);
                } else {
                    alert(js2JSON(E));
                }

            }
            this.exec.chain( chain );

        } catch(E) {
            if (typeof window.xulG == 'object' && typeof window.xulG.on_error == 'function') {
                window.xulG.on_error(E);
            } else {
                alert(js2JSON(E));
            }
        }
    }
}

dump('exiting patron.summary.js\n');
