var myPackageDir = 'open_ils_staff_client'; var IAMXUL = true; var g = {};

function my_init() {
    try {
                if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for printer_settings.xul');

        g.set_printer_context();

        g.prefs = Components.classes['@mozilla.org/preferences-service;1'].getService(Components.interfaces['nsIPrefBranch']);

        var print_silent_pref = false;
        if (g.prefs.prefHasUserValue('print.always_print_silent')) {
            print_silent_pref = g.prefs.getBoolPref('print.always_print_silent');
        }
        var x = document.getElementById('print_silent');
        x.checked = print_silent_pref;

        /*
        g.PSSVC = Components.classes["@mozilla.org/gfx/printsettings-service;1"].getService(Components.interfaces.nsIPrintSettingsService);
        g.PO = Components.classes["@mozilla.org/gfx/printsettings-service;1"].getService(Components.interfaces.nsIPrintOptions);
        g.PPSVC = Components.classes["@mozilla.org/embedcomp/printingprompt-service;1"].getService(Components.interfaces.nsIPrintingPromptService);
        g.settings = g.PSSVC.globalPrintSettings;
        */

    } catch(E) {
        try { g.error.standard_unexpected_error_dialog('admin/printer_settings.xul',E); } catch(F) { alert(E); }
    }
}

g.toggle_silent_print = function() {
    var x = document.getElementById('print_silent');
    if (x.checked) {
        g.prefs.setBoolPref('print.always_print_silent', true);
        dump('Setting print.always_print_silent to true\n');
    } else {
        // Setting print.always_print_silent to false is not the same as clearing it, since a false here will prevent
        // gPrintSettings.printSilent = true from working when fed to webBrowserPrint
        if (g.prefs.prefHasUserValue('print.always_print_silent')) {
            g.prefs.clearUserPref('print.always_print_silent');
        }
        dump('Clearing print.always_print_silent\n');
    }
}

g.set_printer_context = function(context) {
    g.context = context || 'default';
    JSAN.use('util.print'); g.print = new util.print(g.context);
}

g.page_settings = function() {
    g.print.page_settings();
    g.print.save_settings();
}

g.printer_settings = function() {
    var print_silent_pref = false;
    if (g.prefs.prefHasUserValue('print.always_print_silent')) {
        print_silent_pref = g.prefs.getBoolPref('print.always_print_silent');
    }
    g.prefs.setBoolPref('print.always_print_silent', false);
    g.prefs.clearUserPref('print.always_print_silent');
    var w = get_contentWindow(document.getElementById('sample'));
    g.print.NSPrint(w ? w : window, false, {});
    g.print.save_settings();
    if (print_silent_pref) {
        g.prefs.setBoolPref('print.always_print_silent', true);
    }
}

g.set_print_strategy = function(which) {
    if (which == 'custom.print') {
        var key = 'oils.printer.external.cmd.' + g.context;
        var has_key = g.prefs.prefHasUserValue(key);
        var value = has_key ? g.prefs.getCharPref(key) : '';
        var cmd = window.prompt(
            document.getElementById('offlineStrings').getString('printing.prompt_for_external_print_cmd'),
            value
        );
        if (!cmd) { return; }
        g.prefs.setCharPref(key,cmd);
    }
    JSAN.use('util.file'); var file = new util.file('print_strategy.' + g.context);
    file.write_content( 'truncate', String( which ) );
    file.close();
    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
    if (!data.print_strategy) {
        data.print_strategy = {};
    }
    data.print_strategy[g.context] = which;
    data.stash('print_strategy');
    alert(
        document.getElementById('offlineStrings').getFormattedString('printing.print_strategy_saved',[which,g.context])
    );
}

g.save_settings = function() { g.print.save_settings(); }
