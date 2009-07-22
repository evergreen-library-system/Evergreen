var error;

function my_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for main_test.xul');

        /* these were not working as <script> tags.  Maybe someone else can try? */
        var url="/js/dojo/dojo/dojo.js"; var js = JSAN._loadJSFromUrl( url ); eval(js);
        url="/js/dojo/DojoSRF.js"; js = JSAN._loadJSFromUrl( url ); eval(js);
        url="/js/dojo/fieldmapper/Fieldmapper.js"; js = JSAN._loadJSFromUrl( url ); eval(js);
        url="/js/dojo/fieldmapper/hash.js"; js = JSAN._loadJSFromUrl( url ); eval(js);
        url="/js/dojo/fieldmapper/OrgUtils.js"; js = JSAN._loadJSFromUrl( url ); eval(js);
        url="/js/dojo/openils/Event.js"; js = JSAN._loadJSFromUrl( url ); eval(js);
        url="/js/dojo/openils/Util.js"; js = JSAN._loadJSFromUrl( url ); eval(js);
        url="/js/dojo/openils/User.js"; js = JSAN._loadJSFromUrl( url ); eval(js);
        url="/js/dojo/openils/PermaCrud.js"; js = JSAN._loadJSFromUrl( url ); eval(js);

        var types = new openils.PermaCrud(
            {
                authtoken :ses()
            }
        ).retrieveAll('coust');

        dojo.forEach(types,
            function(type) {
                alert( js2JSON(type) );
            }
        );

        if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
            try { window.xulG.set_tab_name('Test'); } catch(E) { alert(E); }
        }

    } catch(E) {
        try { error.standard_unexpected_error_alert('main/test.xul',E); } catch(F) { alert(E); }
    }
}


