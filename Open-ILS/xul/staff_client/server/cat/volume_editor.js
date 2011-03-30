var xulG = {};

function my_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for cat/volume_editor.xul');

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
        JSAN.use('util.network'); g.network = new util.network();

        JSAN.use('util.functional');

        g.volumes = xul_param('volumes',{'stash_name':'volumes_temp','clear_xpcom':true,'modal_xulG':true}); //JSON2js( g.data.volumes_temp );
        //g.data.volumes_temp = ''; g.data.stash('volumes_temp');

        var rows = document.getElementById('rows');

        var first_tb;

        for (var i = 0; i < g.volumes.length; i++) {
            var row = document.createElement('row'); rows.appendChild(row);
            var lib_label = document.createElement('label'); row.appendChild(lib_label);
            var class_ml = g.render_class_menu(i); row.appendChild(class_ml);
            var prefix_ml = g.render_prefix_menu(i); row.appendChild(prefix_ml);
            var label_tb = document.createElement('textbox'); row.appendChild(label_tb);
            var suffix_ml = g.render_suffix_menu(i); row.appendChild(suffix_ml);
            if (!first_tb) { first_tb = label_tb; }

            var lib_id = g.volumes[i].owning_lib();
            var last_lib_seen;

            if (last_lib_seen != lib_id ) {
                lib_label.setAttribute('value',g.data.hash.aou[ lib_id ].shortname() );
                last_lib_seen = lib_id;
            }

            label_tb.setAttribute('value',g.volumes[i].label());
            label_tb.setAttribute('onchange','try { var v = g.volumes['+i+']; v.ischanged("1"); v.label( this.value ); } catch(E) { alert(E); }');
        }

        first_tb.select(); first_tb.focus();

    } catch(E) {
        var err_msg = $("commonStrings").getFormattedString('common.exception', ['cat/volume_editor.xul', E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); dump(js2JSON(E)); }
        alert(err_msg);
    }
}

g.stash_and_close = function() {
    try {
        //g.data.volumes_temp = js2JSON( g.volumes );
        //g.error.sdump('D_CAT','in modal window, g.data.volumes_temp = \n' + g.data.volumes_temp + '\n');
        //g.data.stash('volumes_temp');
        xulG.volumes = g.volumes;
        xulG.update_these_volumes = 1;
        xulG.auto_merge = document.getElementById('auto_merge').checked;
        update_modal_xulG(xulG);
        window.close();
    } catch(E) {
        alert('FIXME: volume editor -> ' + E);
    }
}

g.render_class_menu = function(vol_idx) {
    var ml = util.widgets.make_menulist(
        util.functional.map_list(
            g.data.list.acnc,
            function(o) {
                return [ o.name(), o.id() ];
            }
        ),
        typeof g.volumes[vol_idx].label_class() == 'object'
            ? g.volumes[vol_idx].label_class().id()
            : g.volumes[vol_idx].label_class()
    );
    ml.addEventListener(
        'command',
        function(ev) {
            g.volumes[vol_idx].ischanged(1);
            g.volumes[vol_idx].label_class(ml.value);
        },
        false
    );
    return ml;
}

g.render_prefix_menu = function(vol_idx) {
    var org = typeof g.volumes[vol_idx].owning_lib() == 'object'
        ? g.volumes[vol_idx].owning_lib()
        : g.data.hash.aou[ g.volumes[vol_idx].owning_lib() ];
    var menulist = document.createElement('menulist');
        var menupopup = document.createElement('menupopup');
        menulist.appendChild(menupopup);
        var org_list = []; // order from top of consortium to owning lib
        while(org) {
            org_list.unshift(org.id());
            org = org.parent_ou();
            if (org && typeof org != 'object') {
                org = g.data.hash.aou[ org ];
            }
        }
        for (var i = 0; i < org_list.length; i++) {
            g.render_prefix_menu_items(menupopup,org_list[i]);
        }
        menulist.setAttribute('value',
            typeof g.volumes[vol_idx].prefix() == 'object'
                ? g.volumes[vol_idx].prefix().id()
                : g.volumes[vol_idx].prefix()
        );

    menulist.addEventListener(
        'command',
        function() {
            g.volumes[vol_idx].ischanged(1);
            g.volumes[vol_idx].prefix(menulist.value);
        },
        false
    );
    return menulist;
}

g.render_prefix_menu_items = function(menupopup,ou_id) {
    if (typeof g.data.list['acnp_for_lib_'+ou_id] == 'undefined') {
        g.data.list['acnp_for_lib_'+ou_id] = g.network.simple_request(
            'FM_ACNP_RETRIEVE_VIA_PCRUD',
            [ ses(), {"owning_lib":{"=":ou_id}}, {"order_by":{"acnp":"label_sortkey"}} ]
        );
        g.data.stash('list');
    }
    for (var i = 0; i < g.data.list['acnp_for_lib_'+ou_id].length; i++) {
        var my_acnp = g.data.list['acnp_for_lib_'+ou_id][i];
        var menuitem = document.createElement('menuitem');
        menupopup.appendChild(menuitem);
            menuitem.setAttribute(
                'label',
                my_acnp.id() == -1 ? '' :
                $('catStrings').getFormattedString(
                    'staff.cat.volume_copy_creator.call_number_prefix.menuitem_label',
                    [
                        my_acnp.label(),
                        g.data.hash.aou[ ou_id ].shortname()
                    ]
                )
            );
            menuitem.setAttribute('value',my_acnp.id());
    }
}


g.render_suffix_menu = function(vol_idx) {
    var org = typeof g.volumes[vol_idx].owning_lib() == 'object'
        ? g.volumes[vol_idx].owning_lib()
        : g.data.hash.aou[ g.volumes[vol_idx].owning_lib() ];
    var menulist = document.createElement('menulist');
        var menupopup = document.createElement('menupopup');
        menulist.appendChild(menupopup);
        var org_list = []; // order from top of consortium to owning lib
        while(org) {
            org_list.unshift(org.id());
            org = org.parent_ou();
            if (org && typeof org != 'object') {
                org = g.data.hash.aou[ org ];
            }
        }
        for (var i = 0; i < org_list.length; i++) {
            g.render_suffix_menu_items(menupopup,org_list[i]);
        }
        menulist.setAttribute('value',
            typeof g.volumes[vol_idx].suffix() == 'object'
                ? g.volumes[vol_idx].suffix().id()
                : g.volumes[vol_idx].suffix()
        );

    menulist.addEventListener(
        'command',
        function() {
            g.volumes[vol_idx].ischanged(1);
            g.volumes[vol_idx].suffix(menulist.value);
        },
        false
    );
    return menulist;
}

g.render_suffix_menu_items = function(menupopup,ou_id) {
    if (typeof g.data.list['acns_for_lib_'+ou_id] == 'undefined') {
        g.data.list['acns_for_lib_'+ou_id] = g.network.simple_request(
            'FM_ACNS_RETRIEVE_VIA_PCRUD',
            [ ses(), {"owning_lib":{"=":ou_id}}, {"order_by":{"acns":"label_sortkey"}} ]
        );
        g.data.stash('list');
    }
    for (var i = 0; i < g.data.list['acns_for_lib_'+ou_id].length; i++) {
        var my_acns = g.data.list['acns_for_lib_'+ou_id][i];
        var menuitem = document.createElement('menuitem');
        menupopup.appendChild(menuitem);
            menuitem.setAttribute(
                'label',
                my_acns.id() == -1 ? '' :
                $('catStrings').getFormattedString(
                    'staff.cat.volume_copy_creator.call_number_suffix.menuitem_label',
                    [
                        my_acns.label(),
                        g.data.hash.aou[ ou_id ].shortname()
                    ]
                )
            );
            menuitem.setAttribute('value',my_acns.id());
    }
}


