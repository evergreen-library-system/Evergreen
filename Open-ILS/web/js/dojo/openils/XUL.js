if(!dojo._hasResource["openils.XUL"]) {

    dojo.provide("openils.XUL");
    dojo.declare('openils.XUL', null, {});

    openils.XUL.isXUL = function() {
        return window.IAMXUL;
    }
    
    openils.XUL.getStash = function() {
        if(openils.XUL.isXUL()) {
            try {
			    netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			    var CacheClass = new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
			    return new CacheClass().wrappedJSObject.OpenILS.prototype.data;
            } catch(e) {
                console.log("Error loading XUL stash: " + e);
            }
        }

        return {};
    };
}


