var error;
var network;
var data;
var coust_obj;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for main_test.xul');
        JSAN.use('util.network'); network = new util.network();
        JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();

        dojo.require('openils.PermaCrud');
        coust_obj = new openils.PermaCrud({authtoken:ses()}).search('coust',{'name':'circ.staff_client.do_not_auto_attempt_print'})[0];
        document.getElementById('caption').setAttribute('label',coust_obj.label());
        document.getElementById('caption').setAttribute('tooltiptext',coust_obj.name());
        append_to_vbox('desc',coust_obj.description());

        render_current_setting();

        document.getElementById('apply').addEventListener(
            'command',
            apply_setting,
            false
        );

        var ml = util.widgets.render_perm_org_menu('ADMIN_ORG_UNIT_SETTING_TYPE');
        if (ml) {
            document.getElementById('apply').disabled = false;
            ml.setAttribute('id','lib_menulist');
            var x = document.getElementById('menu');
            util.widgets.remove_children(x);
            x.appendChild(ml);
        }

    } catch(E) {
        try { error.standard_unexpected_error_alert('main/test.xul',E); } catch(F) { alert(E); }
    }
}

function append_to_vbox(id,node) {
    if (typeof node == 'string') { var text = document.createTextNode(node); node = document.createElement('description'); node.appendChild(text); }
    document.getElementById(id).appendChild(node);
}

function admin_string(s,p) {
    var mc = document.getElementById('adminStrings');
    if (p) {
        return mc.getFormattedString(s,p);
    } else {
        return mc.getString(s);
    }
}

function apply_setting(ev) {
    var values = [];
    if (document.getElementById('checkout').checked) { values.push('Checkout'); }
    if (document.getElementById('bill_pay').checked) { values.push('Bill Pay'); }
    if (document.getElementById('hold_slip').checked) { values.push('Hold Slip'); }
    if (document.getElementById('transit_slip').checked) { values.push('Transit Slip'); }
    if (document.getElementById('hold_transit_slip').checked) { values.push('Hold/Transit Slip'); }
    var org = document.getElementById('lib_menulist').value;
    var result = network.simple_request('FM_AOUS_UPDATE',[ ses(), org, { 'circ.staff_client.do_not_auto_attempt_print' : values } ]);
    if (result == 1) {
        alert(admin_string('staff.admin.staff.do_not_auto_attempt_print_setting.update_success'));
        render_current_setting();
    } else {
        error.standard_unexpected_error_alert(admin_string('staff.admin.staff.do_not_auto_attempt_print_setting.update_failure'),result);
    }
}

function render_current_setting() {
    JSAN.use('util.widgets');

    util.widgets.remove_children('current');

    /* FIXME: would be good to have an .authoritative version of FM_AOUS_SPECIFIC_RETRIEVE */
    var aous_req = network.simple_request('FM_AOUS_SPECIFIC_RETRIEVE',[ ses('ws_ou'), 'circ.staff_client.do_not_auto_attempt_print', ses() ]);
    if (aous_req) {
        append_to_vbox(
            'current',
            admin_string(
                'staff.admin.staff.do_not_auto_attempt_print_setting.current_setting_preamble',
                [ ses('ws_ou_shortname'), data.hash.aou[ aous_req.org ].shortname() ]
            )
        );

        for (var i in aous_req.value) {
            var label = document.createElement('label');
            label.setAttribute('value', '   ' + aous_req.value[i]);
            append_to_vbox('current',label);
        }

        /* update data.hash.aous while we have fresh data */

        data.hash.aous['circ.staff_client.do_not_auto_attempt_print'] = aous_req.value;
        data.stash('hash');

    } else {
        append_to_vbox(
            'current',
            admin_string(
                'staff.admin.staff.do_not_auto_attempt_print_setting.current_setting_nonexistent',
                [ ses('ws_ou_shortname') ]
            )
        );
    }
}



