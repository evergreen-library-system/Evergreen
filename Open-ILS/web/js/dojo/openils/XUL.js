if(!dojo._hasResource["openils.XUL"]) {

    dojo.provide("openils.XUL");
    dojo.declare('openils.XUL', null, {});

    openils.XUL.Component_copy;
    if (!window.IAMBROWSER) {
        // looks like Firefox also exposes 'Components', so its
        // existence is not sufficient check of XUL-ness
        try {
            if (Components.classes)
                openils.XUL.Component_copy = Components;
        } catch (e) {
            openils.XUL.Component_copy = null;
        };
    }

    openils.XUL.isXUL = function() {
        if(location.protocol == 'chrome:' || location.protocol == 'oils:') return true;
        return Boolean(window.IAMXUL);
    }

 try {
    openils.XUL.buildId = function() {
        return window.XUL_BUILD_ID || '';
    }
    
    openils.XUL.getStash = function() {
        if(openils.XUL.Component_copy) {
            try {
                var CacheClass = openils.XUL.Component_copy.classes["@open-ils.org/openils_data_cache;1"].getService();
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
            loc = urls.XUL_BROWSER + "?url=" + window.encodeURIComponent(loc);
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
    try {
        openils.XUL.SimpleXPCOM.prototype = {
            "FP": {
                "iface": openils.XUL.Component_copy.interfaces.nsIFilePicker,
                "cls": "@mozilla.org/filepicker;1"
            },
            "FIS": {
                "iface": openils.XUL.Component_copy.interfaces.nsIFileInputStream,
                "cls": "@mozilla.org/network/file-input-stream;1"
            },
            "SIS": {
                "iface": openils.XUL.Component_copy.interfaces.nsIScriptableInputStream,
                "cls": "@mozilla.org/scriptableinputstream;1"
            },
            "FOS": {
                "iface": openils.XUL.Component_copy.interfaces.nsIFileOutputStream,
                "cls": "@mozilla.org/network/file-output-stream;1"
            },
            "COS": {
                "iface": openils.XUL.Component_copy.interfaces.nsIConverterOutputStream,
                "cls": "@mozilla.org/intl/converter-output-stream;1"
            },
            "create": function(key) {
                return openils.XUL.Component_copy.classes[this[key].cls].
                    createInstance(this[key].iface);
            }
        };
    } catch (e) { /* not XUL */ };

    openils.XUL.contentFromFileOpenDialog = function(windowTitle, sizeLimit) {
        if (!openils.XUL.Component_copy) return null;

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
        if (!openils.XUL.Component_copy) return null;

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

            var cos = api.create("COS");
            cos.init(fos, "UTF-8", 0, 0);   /* It's the 21st century. You don't
                                                use ISO-8859-*. */
            cos.writeString(content);
            return cos.close();
        } else {
            return 0;
        }
    };

    // returns a ref to a XUL localStorage interface
    // localStorage is not directly accessible within oils://
    // http://fartersoft.com/blog/2011/03/07/using-localstorage-in-firefox-extensions-for-persistent-data-storage/
    openils.XUL.localStorage = function() {

        // in browser mode, use the standard localStorage interface
        if (!openils.XUL.Component_copy) 
            return window.localStorage;

        var url = location.protocol + '//' + location.hostname;
        var ios = openils.XUL.Component_copy.classes["@mozilla.org/network/io-service;1"]
                  .getService(openils.XUL.Component_copy.interfaces.nsIIOService);
        var ssm = openils.XUL.Component_copy.classes["@mozilla.org/scriptsecuritymanager;1"]
                  .getService(openils.XUL.Component_copy.interfaces.nsIScriptSecurityManager);
        var dsm = openils.XUL.Component_copy.classes["@mozilla.org/dom/storagemanager;1"]
                  .getService(openils.XUL.Component_copy.interfaces.nsIDOMStorageManager);
        var uri = ios.newURI(url, "", null);
        var principal = ssm.getCodebasePrincipal(uri);
        return dsm.getLocalStorageForPrincipal(principal, "");
    };

 }catch (e) { console.log('Failed to load openils.XUL: ' + e) }
}
