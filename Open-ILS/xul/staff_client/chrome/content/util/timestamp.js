var data; var error; var network; var sound;

function $(id) { return document.getElementById(id); }

function default_focus() { $('cancel_btn').focus(); } // parent interfaces often call this

function timestamp_init() {
    try {

        commonStrings = $('commonStrings');

        if (typeof JSAN == 'undefined') {
            throw(
                commonStrings.getString('common.jsan.missing')
            );
        }

        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');

        JSAN.use('util.error'); error = new util.error();
        JSAN.use('util.sound'); sound = new util.sound();
        JSAN.use('util.date'); 

        $('datepicker').value = xul_param('default_date') || util.date.formatted_date(new Date(),'%F');
        if (xul_param('default_time')) {
            $('timepicker').value = xul_param('default_time');
        }
        if (xul_param('time_readonly')) {
            $('timepicker').readonly = true; // This isn't working correctly with xulrunner 1.9.2
            $('timepicker').disabled = true; // So, poor man's kludge
        }
        if (xul_param('date_readonly')) {
            $('datepicker').readonly = true; // This isn't working correctly with xulrunner 1.9.2
            $('datepicker').disabled = true; // So, poor man's kludge
        }

        if (xul_param('title')) { $('dialogheader').setAttribute('title',xul_param('title')); }
        if (xul_param('description')) { $('dialogheader').setAttribute('description',xul_param('description')); }

        var x = $('msg_area');
        if (x && xul_param('msg')) {
            var d = document.createElement('description');
            var t = document.createTextNode( xul_param('msg') );
            x.appendChild( d );
            d.appendChild( t );
        }

        if (xul_param('allow_unset')) { $('remove_btn').hidden = false; }

        /* set widget behavior */
        $('cancel_btn').addEventListener(
            'command', function() { window.close(); }, false
        );
        $('apply_btn').addEventListener(
            'command', 
            gen_handle_apply(),
            false
        );
        $('remove_btn').addEventListener(
            'command', 
            gen_handle_apply({'remove':true}),
            false
        );

        $('datepicker').addEventListener(
            'change',
            function(ev) {
                try {
                    var check = check_date( ev.target.value );
                    if ( ! check.allowed ) { throw( check.reason ); }
                    $('apply_btn').disabled = false;
                } catch(E) {
                    JSAN.use('util.sound'); var sound = new util.sound(); sound.bad();
                    var x = $('err_msg');
                    if (x) {
                        x.setAttribute('value', check.reason);
                    }
                    $('apply_btn').disabled = true;
                }
                dump('util.timestamp.js:date: ' + E + '\n');
            },
            false
        );

        default_focus();

    } catch(E) {
        var err_prefix = 'timestamp.js -> timestamp_init() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

function check_date(value) {
    if (xul_param('disallow_future_dates')) {
        if ( value > new Date() ) { return { 'allowed' : false, 'reason' : $('commonStrings').getString('staff.util.timestamp_dialog.future_date_disallowed') }; }
    }
    if (xul_param('disallow_past_dates')) {
        if ( util.date.check_past('YYYY-MM-DD', value) ) { return { 'allowed' : false, 'reason' : $('commonStrings').getString('staff.util.timestamp_dialog.past_date_disallowed') }; }
    }
    if (xul_param('disallow_today')) {
        if ( util.date.formatted_date(new Date(),'%F') == value) { return { 'allowed' : false, 'reason' : $('commonStrings').getString('staff.util.timestamp_dialog.today_disallowed') }; }
    }
    return { 'allowed' : true };
}

function gen_handle_apply(params) {
    return function handle_apply(ev) {
        try {

            if (!params) { params = {}; }
            if (params.remove) {
                xulG.timestamp = null;
                xulG.complete = 1;
                window.close();
            } else {

                var dp = $('datepicker');
                var tp = $('timepicker');

                var check = check_date( dp.value );
                if ( ! check.allowed ) { alert( check.reason ); $('apply_btn').disabled = true; return; }

                var tp_date = tp.dateValue;
                var dp_date = dp.dateValue;
                dp_date.setHours( tp_date.getHours() );
                dp_date.setMinutes( tp_date.getMinutes() );

                xulG.timestamp = util.date.formatted_date(dp_date,'%{iso8601}');
                xulG.complete = 1;
                window.close();
            }

        } catch(E) {
            alert('Error in timestamp.js, handle_apply(): ' + E);
        }
    };
}
