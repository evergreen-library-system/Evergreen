var data; var error; var network; var sound;

function $(id) { return document.getElementById(id); }

function default_focus() { $('cancel_btn').focus(); } // parent interfaces often call this

function backdate_post_checkin_init() {
    try {

        commonStrings = $('commonStrings');
        circStrings = $('circStrings');

        if (typeof JSAN == 'undefined') {
            throw(
                commonStrings.getString('common.jsan.missing')
            );
        }

        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');

        JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();

        JSAN.use('util.error'); error = new util.error();

        JSAN.use('util.network'); network = new util.network();

        JSAN.use('util.sound'); sound = new util.sound();

        JSAN.use('util.date'); 

        dojo.require('openils.Util');

        $('checkin_effective_datepicker').value = util.date.formatted_date(new Date(),'%F');

        var x = $('circ_brief_area');
        var circ_ids = xul_param('circ_ids');
        if (x) {
            var d = document.createElement('description');
            var t = document.createTextNode( $('circStrings').getFormattedString('staff.circ.backdate.circ_ids.prompt',[circ_ids.length,circ_ids.join(',')]) ); 
            x.appendChild( d );
            d.appendChild( t );
        }

        /* set widget behavior */
        $('cancel_btn').addEventListener(
            'command', function() { window.close(); }, false
        );
        $('apply_btn').addEventListener(
            'command', 
            gen_handle_apply(circ_ids),
            false
        );

        $('checkin_effective_datepicker').addEventListener(
            'change',
            function(ev) {
                try {
                    if ( ev.target.dateValue > new Date() ) throw($('circStrings').getString('staff.circ.future_date'));
                    if ( ev.target.value == util.date.formatted_date(new Date(),'%F') ) {
                        $('apply_btn').disabled = true;
                    } else {
                        $('apply_btn').disabled = false;
                    }
                } catch(E) {
                    dump('checkin:effective_date: ' + E + '\n');
                    ev.target.disabled = true;
                    ev.target.value = util.date.formatted_date(new Date(),'%F');
                    ev.target.disabled = false;
                    JSAN.use('util.sound'); var sound = new util.sound(); sound.bad();
                    $('apply_btn').disabled = true;
                }
            },
            false
        );

        default_focus();

    } catch(E) {
        var err_prefix = 'backdate_post_checkin.js -> backdate_post_checkin_init() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }

}

function gen_handle_apply(circ_ids) {
    return function handle_apply(ev) {
        try {
            var backdate = $('checkin_effective_datepicker').value;
            var progressmeter = $('progress');

            var idx = -1;
            var bad_circs = [];

            fieldmapper.standardRequest(
                [ api.FM_CIRC_BACKDATE_BATCH.app, api.FM_CIRC_BACKDATE_BATCH.method ],
                {   async: true,
                    params: [ses(), circ_ids, backdate],
                    onresponse: function(r) {
                        idx++; progressmeter.value = Number( progressmeter.value ) + 100/circ_ids.length;
                        var result = r.recv().content();
                        if (result != 1) {
                            bad_circs.push( { 'circ_id' : circ_ids[ idx ], 'result' : result } );
                        }
                    },
                    oncomplete: function() {
                        if (bad_circs.length > 0) {
                            sound.circ_bad(); 
                            alert( $('circStrings').getFormattedString('staff.circ.backdate.circ_ids.failed',[ bad_circs.length, bad_circs.join(',') ]) );
                        } else {
                            sound.circ_good();
                        }

                        xulG['backdate'] = backdate;
                        xulG['bad_circs'] = bad_circs;
                        xulG['complete'] = 1;
                        window.close();
                    }
                }
            );

        } catch(E) {
            alert('Error in backdate.js, handle_apply(): ' + E);
        }
    };
}
