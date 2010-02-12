if(!dojo._hasResource["openils.XUL"]) {

    dojo.provide("openils.XUL");
    dojo.require('dojo.cookie');
    dojo.declare('openils.XUL', null, {});

    openils.XUL.isXUL = function() {
        return Boolean(dojo.cookie('xul')) || Boolean(window.IAMXUL);
    }

    openils.XUL.buildId = function() {
        return window.XUL_BUILD_ID || '';
    }
    
    openils.XUL.getStash = function() {
        if(openils.XUL.isXUL()) {
            try {
                if(openils.XUL.enableXPConnect()) {
			        var CacheClass = new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
			        return new CacheClass().wrappedJSObject.OpenILS.prototype.data;
                }
            } catch(e) {
                console.log("Error loading XUL stash: " + e);
            }
        }

        return {};
    }

    openils.XUL.newTab = function(path, tabInfo, options) {
        if(xulG == undefined) 
            throw new Error('xulG is not defined.  Cannot open tab');
        xulG.new_tab(path, tabInfo, options);
    }

    /** 
     * This can be used by privileged Firefox in addition to XUL.
     * To use use in Firefox directly, set signed.applets.codebase_principal_support to true in about:config
     */ 
    openils.XUL.enableXPConnect = function() {
        try {
            netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
        } catch (E) {
            if(dojo.isFF) {
                console.error("Unable to enable UniversalXPConnect privileges.  " +
                    "Try setting 'signed.applets.codebase_principal_support' to true in about:config");
            }
            return false;
        }
        return true;
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
        "create": function(key) {
            return Components.classes[this[key].cls].
                createInstance(this[key].iface);
        },
        "getPrivilegeManager": function() {
            return netscape.security.PrivilegeManager;
        }
    };

    openils.XUL.contentFromFileOpenDialog = function(windowTitle) {
        try {
            var api = new openils.XUL.SimpleXPCOM();

            /* The following enablePrivilege() call must happen at this exact
             * level of scope -- not wrapped in another function -- otherwise
             * it doesn't work. */
            api.getPrivilegeManager().enablePrivilege("UniversalXPConnect");

            var picker = api.create("FP");
            picker.init(
                window, windowTitle || "Upload File", api.FP.iface.modeOpen
            );
            if (picker.show() == api.FP.iface.returnOK && picker.file) {
                var fis = api.create("FIS");
                var sis = api.create("SIS");

                fis.init(picker.file, 1 /* MODE_RDONLY */, 0, 0);
                sis.init(fis);

                return sis.read(-1);
            } else {
                return null;
            }
        } catch(E) {
            alert(E);
            return null;
        }
    };
}
