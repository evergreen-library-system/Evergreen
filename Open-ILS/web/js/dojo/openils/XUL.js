if(!dojo._hasResource["openils.XUL"]) {

    dojo.provide("openils.XUL");
    dojo.declare('openils.XUL', null, {});

    openils.XUL.isXUL = function() {
        return Boolean(window.IAMXUL);
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
}


