var data; var error; 

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

        JSAN.use('util.date');

        $('checkin_effective_datepicker').value = util.date.formatted_date(new Date(),'%F');

        var x = $('circ_brief_area');
        var circ_ids = xul_param('circ_ids',{'modal_xulG':true});
        dojo.forEach(
            circ_ids,
            function(element,idx,list) {
                var iframe = document.createElement('iframe'); x.appendChild(iframe);
                iframe.setAttribute('src', urls.XUL_CIRC_BRIEF);
                get_contentWindow(iframe).xulG = { 'circ_id' : element };
            }
        );

        /* set widget behavior */
        $('cancel_btn').addEventListener(
            'command', function() { window.close(); }, false
        );
        $('apply_btn').addEventListener(
            'command', 
            function() {
                update_modal_xulG(
                    {
                        'backdate' : $('checkin_effective_datepicker').value,
                        'proceed' : 1
                    }
                )
                window.close();
            }, 
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

