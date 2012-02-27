var error;
var data;
var net;
var hold_usr;

function my_init() {
    try {
        ui_setup(); // JSAN, tab name, etc.
        error.sdump('D_TRACE','my_init() for place_hold.xul');

        JSAN.use('OpenILS.data');
        data = new OpenILS.data();
        data.stash_retrieve();

        JSAN.use('util.network');
        net = new util.network();

        var copy_ids = xul_param('copy_ids');

        populate_hold_usr_textbox();
        populate_pickup_lib_menu();

        $('request_btn').addEventListener(
            'command',
            function(ev) {
                make_request(copy_ids,false);
            },
            false
        );
        
        set_remaining_event_listeners();

    } catch(E) {
        alert('Error in place_hold.js, my_init(): ' + E);
    }
}

function make_request(copy_ids,override) {
    try {

        if (!hold_usr) {
            alert( $('patronStrings').getString('staff.item.batch.hold.user_not_found') );
            return;
        }

        var args = {
            'hold_type' : $('hold_type_menu').value,
            'patronid' : hold_usr,
            'depth' : 0, 
            'pickup_lib' : $('pickup_lib_menu').value
        };

        oils_lock_page();
        $('progress_meter').hidden = false;
        $('request_btn').disabled = true;
        $('cancel_btn').disabled = true;

        net.simple_request(
            override
            ? 'FM_AHR_CHECK_AND_CREATE.batch.override'
            : 'FM_AHR_CHECK_AND_CREATE.batch',
            [ ses(), args, copy_ids ],
            handle_results
        );

    } catch(E) {
        alert('Error in place_hold.js, make_request(): ' + E);
    }
}

function handle_results(req) {
    try {
        oils_unlock_page();
        $('progress_meter').hidden = true;

        var results = req.getResultObject();
        if(typeof(results.length) != "number") {
            results = [results];
        }

        var successes = [];
        var failures = {};
        var failed_targets = [];
        var failure_count = 0;

        for (var i = 0; i < results.length; i++) {
            var payload = results[i];
            var target = payload.target;
            var result = payload.result;
            if (typeof result.length != 'undefined') {
                // Array; grab first exception for simplicity
                result = result[0];
            }

            if (typeof result == 'string' || typeof result == 'number') {
                successes.push( result ); // hold id's
            } else {
                failure_count++;
                if (typeof failures[ result.textcode ] == 'undefined') {
                    failures[ result.textcode ] = [];
                }
                failures[ result.textcode ].push( target );
                failed_targets.push( target );
            }
        }

        var msg = document.createElement('description');
        msg.appendChild(
            document.createTextNode(
                $('patronStrings').getFormattedString('staff.item.batch.hold.x_holds_created',[ successes.length ])
            )
        );
        $('msgs').appendChild(msg);

        if (failure_count>0) {
            $('desc').hidden = false;
            handle_failures(failures,failed_targets);
        }
    } catch(E) {
        alert('Error in place_hold.js, handle_results(): ' + E);
    }
}

function handle_failures(failures,failed_targets) {
    try {
        for (k in failures) {
            var err_box = document.createElement('hbox');
            var err_msg = document.createElement('description');
            err_box.appendChild(err_msg);
            $('msgs').appendChild(err_box);
            err_msg.appendChild(
                document.createTextNode(
                    $('patronStrings').getFormattedString('staff.item.batch.hold.x_failed_holds',[ failures[k].length, k ])
                )
            );
            addCSSClass(err_msg,'click_link');
            err_msg.addEventListener(
                'click',
                function(copy_ids) {
                    return function(ev) {
                        xulG.new_tab(
                            urls.XUL_COPY_STATUS,
                            {},
                            {
                                'copy_ids' : copy_ids
                            }
                        );
                    }
                }(failures[k]),
                false
            );
            var retry_btn = document.createElement('button');
            retry_btn.setAttribute(
                'label',
                $('patronStrings').getString('staff.item.batch.hold.retry_btn_label')
            );
            err_box.appendChild(retry_btn);

            retry_btn.addEventListener(
                'command',
                function(copy_ids) {
                    return function(ev) {
                        ev.target.disabled = true;
                        ev.target.hidden = true;
                        ev.target.nextSibling.disabled = true;
                        ev.target.nextSibling.hidden = true;
                        make_request(copy_ids,false);
                    }
                }(failures[k]),
                false
            );

            var override_btn = document.createElement('button');
            override_btn.setAttribute(
                'label',
                $('patronStrings').getString('staff.item.batch.hold.override_btn_label')
            );
            err_box.appendChild(override_btn);

            override_btn.addEventListener(
                'command',
                function(copy_ids) {
                    return function(ev) {
                        ev.target.disabled = true;
                        ev.target.hidden = true;
                        ev.target.previousSibling.disabled = true;
                        ev.target.previousSibling.hidden = true;
                        make_request(copy_ids,true);
                    }
                }(failures[k]),
                false
            );

        }
    } catch(E) {
        alert('Error in place_hold.js, handle_failures(): ' + E);
    }
}

function set_remaining_event_listeners() {
    try {

        $('hold_type_menu').addEventListener(
            'command',
            function(ev) { oils_lock_page(); },
            false
        );

        $('cancel_btn').addEventListener(
            'command',
            function(ev) { xulG.close_tab(); },
            false
        );

    } catch(E) {
        alert('Error in place_hold.js, set_remaining_event_listeners(): ' + E);
    } 
}

function populate_hold_usr_textbox() {
    JSAN.use('patron.util');
    hold_usr = ses('staff_id');
    var au_obj = patron.util.retrieve_fleshed_au_via_id(
        ses(),
        hold_usr,
        ["card"]);
    $('hold_usr_textbox').value = au_obj.card().barcode();
    $('hold_usr_textbox').select();
    $('hold_usr_textbox').focus();
    $('hold_usr_name').setAttribute(
        'value',
        patron.util.format_name(au_obj)
    );
    $('hold_usr_textbox').addEventListener(
        'change',
        function(ev) {
            try {
                oils_lock_page();
                var au_obj = patron.util.retrieve_fleshed_au_via_barcode(
                    ses(),
                    ev.target.value
                );
                if (typeof au_obj.textcode == 'undefined') {
                    hold_usr = au_obj.id();
                    $('hold_usr_name').setAttribute(
                        'value',
                        patron.util.format_name(au_obj)
                    );
                    removeCSSClass($('hold_usr_name'),'failure_text');
                } else {
                    hold_usr = null;
                    $('hold_usr_name').setAttribute(
                        'value',
                        $('patronStrings').getString('staff.item.batch.hold.user_not_found')
                    );
                    addCSSClass($('hold_usr_name'),'failure_text');
                }
            } catch(E) {
                alert('Error in place_hold.js, hold_usr handler: ' + E);
            }
        },
        false
    );
}

function populate_pickup_lib_menu() {
    try {
        JSAN.use('util.widgets');
        JSAN.use('util.functional');

        util.widgets.remove_children('pickup_lib_menu_placeholder');

        var list = util.functional.map_list(
            data.list.aou,
            function(o) {
                var sname = o.shortname();
                for (i = sname.length; i < 20; i++) sname += ' ';
                return [
                    o.name() ? sname + ' ' + o.name() : o.shortname(),
                    o.id(),
                    ( !isTrue(data.hash.aout[ o.ou_type() ].can_have_users()) ),
                    ( data.hash.aout[ o.ou_type() ].depth() * 2),
                ];
            }
        );
        ml = util.widgets.make_menulist( list, data.list.au[0].ws_ou() );
        ml.setAttribute('id','pickup_lib_menu');

        $('pickup_lib_menu_placeholder').appendChild(ml);

        ml.addEventListener(
            'command',
            function(ev) { oils_lock_page(); },
            false
        );

    } catch(E) {
        alert('Error in place_hold.js, populate_pickup_lib_menu(): ' + E);
    } 
}

function ui_setup() {
    if (typeof JSAN == 'undefined') {
        throw( "The JSAN library object is missing.");
    }
    JSAN.errorLevel = "die"; // none, warn, or die
    JSAN.addRepository('/xul/server/');
    JSAN.use('util.error');
    error = new util.error();

    if (typeof xulG == 'object' && typeof xulG.set_tab_name == 'function') {
        try {
            xulG.set_tab_name(
                $('patronStrings').getString('staff.item.batch.hold.tab_name')
            );
        } catch(E) {
            alert(E);
        }
    }

}
