dump('entering circ.offline.js\n');

if (typeof circ == 'undefined') circ = {};
circ.offline = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
    } catch(E) {
        dump('circ.offline: ' + E + '\n');
    }
}

circ.offline.prototype = {

    'init' : function( params ) {

        try {
            var obj = this;

            JSAN.use('util.deck'); obj.deck = new util.deck('main');

            JSAN.use('util.controller'); obj.controller = new util.controller();
            obj.controller.init(
                {
                    control_map : {
                        'cmd_broken' : [
                            ['command'],
                            function() { alert('Not Yet Implemented'); }
                        ],
                        'cmd_checkout' : [
                            ['command'],
                            function() {
                                obj.deck.set_iframe(
                                    'offline_checkout.xul',
                                    {},
                                    {
                                        'lock' : function() { oils_lock_page({'allow_multiple_locks':true}); },
                                        'unlock' : oils_unlock_page
                                    }
                                );
                            }
                        ],
                        'cmd_renew' : [
                            ['command'],
                            function() {
                                obj.deck.set_iframe(
                                    'offline_renew.xul',
                                    {},
                                    {
                                        'lock' : function() { oils_lock_page({'allow_multiple_locks':true}); },
                                        'unlock' : oils_unlock_page
                                    }
                                );
                            }
                        ],
                        'cmd_in_house_use' : [
                            ['command'],
                            function() {
                                obj.deck.set_iframe(
                                    'offline_in_house_use.xul',
                                    {},
                                    {
                                        'lock' : function() { oils_lock_page({'allow_multiple_locks':true}); },
                                        'unlock' : oils_unlock_page
                                    }
                                );
                            }
                        ],
                        'cmd_checkin' : [
                            ['command'],
                            function() {
                                obj.deck.set_iframe(
                                    'offline_checkin.xul',
                                    {},
                                    {
                                        'lock' : function() { oils_lock_page({'allow_multiple_locks':true}); },
                                        'unlock' : oils_unlock_page
                                    }
                                );
                            }
                        ],
                        'cmd_register_patron' : [
                            ['command'],
                            function() {
                                obj.deck.set_iframe(
                                    'offline_register.xul',
                                    {},
                                    {
                                        'lock' : function() { oils_lock_page({'allow_multiple_locks':true}); },
                                        'unlock' : oils_unlock_page
                                    }
                                );
                            }
                        ],
                        'cmd_print_last_receipt' : [
                            ['command'],
                            function() { 
                                JSAN.use('util.print'); var print = new util.print('offline');
                                print.reprint_last();
                            }
                        ],
                        'cmd_exit' : [
                            ['command'],
                            function() {
                                try {
                                    xulG.close_tab();
                                } catch(E) {
                                    JSAN.use('util.widgets');
                                    util.widgets.dispatch('close',window);
                                }
                            }
                        ],
                    }
                }
            );

            obj.receipt_init();

            obj.patron_init();

        } catch(E) {
            this.error.sdump('D_ERROR','circ.offline.init: ' + E + '\n');
        }
    },

    'receipt_init' : function() {
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
        data.print_list_defaults();
        data.load_saved_print_templates();
        data.fetch_print_strategy();
        JSAN.use('util.print'); (new util.print('offline')).GetPrintSettings();
    },

    'patron_init' : function() {
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
        JSAN.use('util.file'); var file = new util.file('offline_patron_list');
        if (file._file.exists()) {
            var lines = file.get_content().split(/\n/);
            var hash = {};
            for (var i = 0; i < lines.length; i++) {
                hash[ lines[i].split(/\s+/)[0] ] = lines[i].split(/\s+/)[1];
            }
            delete(lines);
            data.bad_patrons = hash;
            data.stash('bad_patrons');
            var file2 = new util.file('offline_patron_list.date');
            if (file2._file.exists()) {
                data.bad_patrons_date = file2.get_content();
                data.stash('bad_patrons_date');
            }
            file2.close();
        } else {
            data.bad_patrons = {};
            data.stash('bad_patrons');
        }
        file.close();
    },

}

dump('exiting circ.offline.js\n');
