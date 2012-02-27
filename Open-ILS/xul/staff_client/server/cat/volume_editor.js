const rel_vert_pos_call_number_classification = 1;
const rel_vert_pos_call_number_prefix = 2;
const rel_vert_pos_call_number = 3;
const rel_vert_pos_call_number_suffix = 4;

var xulG = {};

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for cat/volume_editor.xul');

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
        JSAN.use('util.network'); g.network = new util.network();

        JSAN.use('util.functional');

        JSAN.use('cat.util');

        g.volumes = xul_param('volumes',{'stash_name':'volumes_temp','clear_xpcom':true,'modal_xulG':true}); //JSON2js( g.data.volumes_temp );
        //g.data.volumes_temp = ''; g.data.stash('volumes_temp');

        var rows = document.getElementById('rows');

        var first_tb;

        for (var i = 0; i < g.volumes.length; i++) {
            var row = document.createElement('row');
                rows.appendChild(row);
            var lib_label = document.createElement('label');
                row.appendChild(lib_label);
            var class_ml = g.render_class_menu(i);
                class_ml.setAttribute('class','cn_class');
                class_ml.setAttribute('rel_vert_pos', rel_vert_pos_call_number_classification);
                row.appendChild(class_ml);
            var prefix_ml = g.render_prefix_menu(i);
                prefix_ml.setAttribute('class','cn_prefix');
                prefix_ml.setAttribute('rel_vert_pos', rel_vert_pos_call_number_prefix);
                row.appendChild(prefix_ml);
            var label_tb = document.createElement('textbox');
                label_tb.setAttribute('rel_vert_pos', rel_vert_pos_call_number);
                row.appendChild(label_tb);
            var suffix_ml = g.render_suffix_menu(i);
                suffix_ml.setAttribute('class','cn_suffix');
                suffix_ml.setAttribute('rel_vert_pos', rel_vert_pos_call_number_suffix);
                row.appendChild(suffix_ml);
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

        // The batch menus
        if (g.volumes.length > 0) {
            JSAN.use('cat.util');
            JSAN.use('util.fm_utils');

            // Get the default callnumber classification scheme from OU settings
            g.label_class = g.data.hash.aous['cat.default_classification_scheme'];

            // Assign a default value if none was returned
            if (!g.label_class) {
                g.label_class = g.data.list.acnc[0].id();
            }

            // Find the pertinent orgs
            var ou_ids = [];
            var seen_ou = {};
            for (var i = 0; i < g.volumes.length; i++) {
                seen_ou[ g.volumes[i].owning_lib() ] = 1;
            }
            for (var i in seen_ou) {
                ou_ids.push(i);
            }
            g.ou_ids = [];
            for (var i = 0; i < ou_ids.length; i++) {
                try {
                    var org = g.data.hash.aou[ ou_ids[i] ];
                    if ( get_bool( g.data.hash.aout[ org.ou_type() ].can_have_vols() ) ) {
                        g.ou_ids.push( ou_ids[i] );
                    }
                } catch(E) {
                    g.error.sdump('D_ERROR',E);
                }
            }
            g.common_ancestor_ou_ids = util.fm_utils.find_common_aou_ancestors( g.ou_ids ).reverse();

            // render the menus
            g.list_classes();
            g.list_prefixes();
            cat.util.render_callnumbers_for_bib_menu('marc_cn',g.volumes[0].record(), g.label_class);
            g.list_suffixes();

            // render the button
            g.render_batch_button();
        }

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
    var ml = cat.util.render_cn_class_menu(
        [],
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

    var menulist = cat.util.render_cn_prefix_menu(
        [ org.id() ],
        [],
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

g.render_suffix_menu = function(vol_idx) {

    var org = typeof g.volumes[vol_idx].owning_lib() == 'object'
        ? g.volumes[vol_idx].owning_lib()
        : g.data.hash.aou[ g.volumes[vol_idx].owning_lib() ];

    var menulist = cat.util.render_cn_suffix_menu(
        [ org.id() ],
        [],
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

g.list_classes = function() {
    var hbox = $('batch_class');
    var ml = cat.util.render_cn_class_menu(
        [
            [ '<No Change>', false ]
        ]
    );
    ml.setAttribute('id','batch_class_menulist');
    hbox.appendChild(ml);
}

g.list_prefixes = function() {
    var hbox = $('batch_prefix');
    var ml = cat.util.render_cn_prefix_menu(
        g.common_ancestor_ou_ids,
        [
            [ '<No Change>', false ]
        ]
    );
    ml.setAttribute('id','batch_prefix_menulist');
    hbox.appendChild(ml);
}

g.list_suffixes = function() {
    var hbox = $('batch_suffix');
    var ml = cat.util.render_cn_suffix_menu(
        g.common_ancestor_ou_ids,
        [
            [ '<No Change>', false ]
        ]
    );
    ml.setAttribute('id','batch_suffix_menulist');
    hbox.appendChild(ml);
}

g.render_batch_button = function() {
    var hbox = $('batch_button_box');
    var btn = document.createElement('button');
    btn.setAttribute('id','batch_button');
    btn.setAttribute('label',$('catStrings').getString('staff.cat.volume_copy_creator.my_init.btn.label'));
    btn.setAttribute('accesskey',$('catStrings').getString('staff.cat.volume_copy_creator.my_init.btn.accesskey'));
    btn.setAttribute('image','/xul/server/skin/media/images/down_arrow.gif');
    hbox.appendChild(btn);
    btn.addEventListener(
        'command',
        function() {
            var nl = document.getElementsByTagName('textbox');
            for (var i = 0; i < nl.length; i++) {
                /* label */
                if (nl[i].getAttribute('rel_vert_pos')==rel_vert_pos_call_number && !nl[i].disabled) {
                    var label =  $('marc_cn').firstChild.value;
                    if (label != '') {
                        nl[i].value = label;
                        util.widgets.dispatch('change',nl[i]);
                    }
                }
            }
            nl = document.getElementsByTagName('menulist');
            for (var i = 0; i < nl.length; i++) {
                /* classification */
                if (nl[i].getAttribute('rel_vert_pos')==rel_vert_pos_call_number_classification && !nl[i].disabled) {
                    var value =  $('batch_class_menulist').value;
                    if (!isNaN( Number(value) )) {
                        nl[i].value = value;
                        util.widgets.dispatch('command',nl[i]);
                    }
                }
                /* prefix */
                if (nl[i].getAttribute('rel_vert_pos')==rel_vert_pos_call_number_prefix && !nl[i].disabled) {
                    var value =  $('batch_prefix_menulist').value;
                    if (!isNaN( Number(value) )) {
                        nl[i].value = value;
                        util.widgets.dispatch('command',nl[i]);
                    }
                }
                /* suffix */
                if (nl[i].getAttribute('rel_vert_pos')==rel_vert_pos_call_number_suffix && !nl[i].disabled) {
                    var value =  $('batch_suffix_menulist').value;
                    if (!isNaN( Number(value) )) {
                        nl[i].value = value;
                        util.widgets.dispatch('command',nl[i]);
                    }
                }
            }
        },
        false
    );
}
