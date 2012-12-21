var error;
var g = { 'addons_ui' : true };
var prefs;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') {
            throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for addon/addon.xul');

        if (typeof window.xulG == 'object'
            && typeof window.xulG.set_tab_name == 'function') {
            try {
                window.xulG.set_tab_name(
                    $('addonStrings').getString('addons.tab.label')
                );
            } catch(E) {
                alert(E);
            }
        }

        const Cc = Components.classes;
        const Ci = Components.interfaces;
        const prefs_Cc = '@mozilla.org/preferences-service;1';
        prefs = Cc[prefs_Cc].getService(Ci['nsIPrefBranch']);

        var addons = JSON2js(
            pref.prefHasUserValue('oils.addon.autoload.list')
            ? pref.getCharPref('oils.addon.autoload.list')
            : '[]'
        );

        $('addonlist_tb').value = addons.join("\n");

        $('addonlist_desc').textContent = $('addonStrings').getString(
            'addons.list.desc');
        // Why messagecat instead of lang.dtd here? Mostly as an example for add-ons
        // that won't have access to lang.dtd

        $('addonlist_caption').setAttribute('label',$('addonStrings').getString(
            'addons.list.caption'));

        $('addonlist_save_btn').setAttribute(
            'label', $('addonStrings').getString(
                'addons.list.update_btn.label'));

        $('addonlist_save_btn').setAttribute(
            'accesskey', $('addonStrings').getString(
                'addons.list.update_btn.accesskey'));

        $('addonpref_caption').setAttribute('label',$('addonStrings').getString(
            'addons.pref.caption'));

    } catch(E) {
        alert('Error in addons.js, my_init(): ' + E);
    }
}

function update() {
    try {
        JSAN.use('util.functional');
        var addon_string = $('addonlist_tb').value.replace(' ','','g');
        var addons = util.functional.filter_list(
            addon_string.split("\n"),
            function(s) {
                return s != ''; // filtering out empty lines
            }
        );

        pref.setCharPref(
            'oils.addon.autoload.list',
            js2JSON(addons)
        );

        location.href = location.href;

    } catch(E) {
        alert('Error in addons.js, update(): ' + E);
    }
}
