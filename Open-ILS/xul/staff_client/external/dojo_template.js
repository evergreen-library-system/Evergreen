var error;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for main_test.xul');

        dojo.require('openils.PermaCrud');

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


