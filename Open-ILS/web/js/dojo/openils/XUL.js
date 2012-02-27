if(!dojo._hasResource["openils.XUL"]) {

    dojo.provide("openils.XUL");
    dojo.require('dojo.cookie');
    dojo.declare('openils.XUL', null, {});

    openils.XUL.isXUL = function() {
        if(location.protocol == 'chrome:' || location.protocol == 'oils:') return true;
        return Boolean(window.IAMXUL);
    }

 try {
    openils.XUL.buildId = function() {
        return window.XUL_BUILD_ID || '';
    }
    
    openils.XUL.getStash = function() {
        if(openils.XUL.isXUL()) {
            try {
                var CacheClass = Components.classes["@open-ils.org/openils_data_cache;1"].getService();
                return CacheClass.wrappedJSObject.data;
            } catch(e) {
                console.log("Error loading XUL stash: " + e);
                return { 'error' : e };
            }
        }

        return { 'error' : 'openils.XUL.isXUL() == false' };
    }

    openils.XUL.newTab = function(path, tabInfo, options) {
        if(xulG == undefined) 
            throw new Error('xulG is not defined.  Cannot open tab');
        xulG.new_tab(path, tabInfo, options);
    }

    openils.XUL.newTabEasy = function(
        url, tab_name, extra_content_params, wrap_in_browser
    ) {
        var content_params = {
            "session": openils.User.authtoken,
            "authtime": openils.User.authtime
        };

        ["url_prefix", "new_tab", "set_tab", "close_tab", "new_patron_tab",
            "set_patron_tab", "volume_item_creator", "get_new_session",
            "holdings_maintenance_tab", "set_tab_name", "open_chrome_window",
            "url_prefix", "network_meter", "page_meter", "set_statusbar",
            "set_help_context"
        ].forEach(function(k) { content_params[k] = xulG[k]; });

        if (extra_content_params)
            dojo.mixin(content_params, extra_content_params);

        var loc = xulG.url_prefix(url);

        if (wrap_in_browser) {
            var urls = xulG.urls || window.urls;
            loc = urls.XUL_BROWSER + "?url=" + window.escape(loc);
            content_params = dojo.mixin(
                {
                    "no_xulG": false, "show_print_button": true,
                    "show_nav_buttons": true,
                    "passthru_content_params": extra_content_params
                }, content_params
            );
        }

        xulG.new_tab(loc, {"tab_name": tab_name}, content_params);
    };

    /**
     * @return bool True if a new session was successfully created, false otherwise.
     */
    openils.XUL.getNewSession = function(callback) {
        return xulG.get_new_session({callback : callback});
    }

    /* This class cuts down on the obscenely long incantations needed to
     * use XPCOM components. */
    openils.XUL.SimpleXPCOM = function() {};
    openils.XUL.SimpleXPCOM.prototype = {
        "FP": {
            "iface": Components.interfaces.nsIFilePicker,
            "cls": "@mozilla.org/filepicker;1"
        },
        "FIS": {
            "iface": Components.interfaces.nsIFileInputStream,
            "cls": "@mozilla.org/network/file-input-stream;1"
        },
        "SIS": {
            "iface": Components.interfaces.nsIScriptableInputStream,
            "cls": "@mozilla.org/scriptableinputstream;1"
        },
        "FOS": {
            "iface": Components.interfaces.nsIFileOutputStream,
            "cls": "@mozilla.org/network/file-output-stream;1"
        },
        "create": function(key) {
            return Components.classes[this[key].cls].
                createInstance(this[key].iface);
        }
    };

    openils.XUL.contentFromFileOpenDialog = function(windowTitle, sizeLimit) {
        var api = new openils.XUL.SimpleXPCOM();

        var picker = api.create("FP");
        picker.init(
            window, windowTitle || "Upload File", api.FP.iface.modeOpen
        );
        if (picker.show() == api.FP.iface.returnOK && picker.file) {
            var fis = api.create("FIS");
            var sis = api.create("SIS");

            fis.init(picker.file, 1 /* MODE_RDONLY */, 0, 0);
            sis.init(fis);

            return sis.read(sizeLimit || -1);
        } else {
            return null;
        }
    };

    openils.XUL.contentToFileSaveDialog = function(content, windowTitle, dispositionArgs) {
        var api = new openils.XUL.SimpleXPCOM();

        var picker = api.create("FP");
        picker.init(
            window, windowTitle || "Save File", api.FP.iface.modeSave
        );

        if (dispositionArgs) {
            /**
             * https://developer.mozilla.org/En/NsIFilePicker
             * Example: 
             * { defaultString : 'MyExport.csv',
                 defaultExtension : '.csv',
                 filterName : 'CSV',
                 filterExtension : '*.csv',
                 filterAll : true } */

            picker.defaultString = dispositionArgs.defaultString;
            picker.defaultExtension = dispositionArgs.defaultExtension;
            if (dispositionArgs.filterName) {
                picker.appendFilter(
                    dispositionArgs.filterName,
                    dispositionArgs.filterExtension
                );
            }
            if (dispositionArgs.filterAll) 
                picker.appendFilters(picker.filterAll)
        }

        var result = picker.show();
        if (picker.file &&
                (result == api.FP.iface.returnOK ||
                    result == api.FP.iface.returnReplace)) {
            if (!picker.file.exists())
                picker.file.create(0, 0644); /* XXX hardcoded = bad */
            var fos = api.create("FOS");
            fos.init(picker.file, 42 /* WRONLY | CREAT | TRUNCATE */, 0644, 0);
            return fos.write(content, content.length);
        } else {
            return 0;
        }
    };
 }catch (e) {/*meh*/}
}
