var error;
var g = {};

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for main_test.xul');

        /*if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
            try { window.xulG.set_tab_name('Test'); } catch(E) { alert(E); }
        }*/

        // Both interfaces look for this
        xulG.unified_interface = true;

        // Item Attribute Editor looks for these
        xulG.not_modal = true;
        xulG.edit = true;

        // Volume Creator looks for these
        xulG.no_bib_summary = true;
        xulG.volume_ui_callback_for_unified_interface = function() {
            on_volume_pane_load();
        };

        // Spawn the volume/copy creator
        JSAN.use('util.browser');
        var volume_pane = new util.browser();
        volume_pane.init(
            {
                'url' : urls.XUL_VOLUME_COPY_CREATOR_ORIGINAL,
                'push_xulG' : true,
                'alt_print' : false,
                'browser_id' : 'volume_pane',
                'passthru_content_params' : xulG
            }
        );

        setup_templates();

        // Spawn the item attribute editor
        var item_pane = new util.browser();
        item_pane.init(
            {
                'url' : urls.XUL_COPY_EDITOR,
                'push_xulG' : true,
                'alt_print' : false,
                'browser_id' : 'item_pane',
                'passthru_content_params' : xulG,
                'on_url_load' : g.clone_template_bar // from setup_templates()
            }
        );

    } catch(E) {
        alert('Error in volume_copy_editor.js, my_init(): ' + E);
    }
}

function setup_templates() {
    try {
        JSAN.use('util.widgets'); JSAN.use('util.functional');

        // Once the item attribute editor is loaded, clone and import its template menu to this window with this callback
        g.clone_template_bar = function() {
            var item_editor_template_bar = get_contentWindow( $('item_pane') ).document.getElementById('template_bar');
            $('template_bar_holder').appendChild(
                document.importNode(
                    item_editor_template_bar,
                    true // children
                )
            );
            item_editor_template_bar.hidden = true;
            g.apply_template = function() {
                xulG.update_item_editor_template_selection( $('template_menu').value );
                xulG.item_editor_apply_template();
            };
            g.delete_template = function() {
                xulG.update_item_editor_template_selection( $('template_menu').value );
                xulG.item_editor_delete_template();
            };
            g.save_template = function() { xulG.item_editor_save_template(); };
            g.import_templates = function() { xulG.item_editor_import_templates(); };
            g.export_templates = function() { xulG.item_editor_export_templates(); };
            g.reset = function() { xulG.item_editor_reset(); };

            // just do this once; not sure if on_url_load could fire multiple times
            g.clone_template_bar = function() {};
        }

        // callback for populating the list of templates
        xulG.update_unified_template_list = function(list) {
            try {
                util.widgets.remove_children('template_placeholder');
                g.template_menu = util.widgets.make_menulist( list );
                g.template_menu.setAttribute('id','template_menu');
                $('template_placeholder').appendChild(g.template_menu);
                g.template_menu.addEventListener(
                    'command',
                    function() {
                        xulG.update_item_editor_template_selection( g.template_menu.value );
                    },
                    false
                );
            } catch(E) {
                alert('Error in volume_copy_editor.js, xulG.update_unified_template_list(): ' + E);
            }
        };

        // used for loading default template selection
        xulG.update_unified_template_selection = function(value) {
            g.template_menu.setAttribute('value', value);
            g.template_menu.value = value;
        };

    } catch(E) {
        alert('Error in volume_copy_editor.js, setup_templates(): ' + E);
    }
}

function on_volume_pane_load() {
    try {
        var f_content = get_contentWindow( $('volume_pane' ) );

        // horizontal UI variant has its own create button
        if ($('Create')) {
            var original_btn = f_content.document.getElementById('Create');
            original_btn.hidden = true;
            $('Create').setAttribute(
                'label',
                $('catStrings').getString('staff.cat.volume_copy_creator.create.btn.label')
            );
            $('Create').setAttribute(
                'accesskey',
                $('catStrings').getString('staff.cat.volume_copy_creator.create.btn.accesskey')
            );
            g.stash_and_close = function(p) {
                // Wire up the method for the replacement button
                f_content.g.stash_and_close(p);
            }
        }

        // load the bib summary pane
        var sb = document.getElementById('summary_box');
        while(sb.firstChild) sb.removeChild(sb.lastChild);
        var summary = document.createElement('iframe'); sb.appendChild(summary);
        summary.setAttribute('src',urls.XUL_BIB_BRIEF);
        summary.setAttribute('flex','1');
        get_contentWindow(summary).xulG = { 'docid' : f_content.g.doc_id };
        dump('f_content.g.doc_id = ' + f_content.g.doc_id + '\n');
    } catch(E) {
        alert('Error in volume_copy_editor.js, on_volume_pane_load(): ' + E);
    }
}
