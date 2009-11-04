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

        $('datepicker').value = xul_param('default_date',{'modal_xulG':true}) || util.date.formatted_date(new Date(),'%F');

        if (xul_param('title',{'modal_xulG':true})) { $('dialogheader').setAttribute('title',xul_param('title',{'modal_xulG':true})); }
        if (xul_param('description',{'modal_xulG':true})) { $('dialogheader').setAttribute('description',xul_param('description',{'modal_xulG':true})); }

        var x = $('msg_area');
        if (x && xul_param('msg',{'modal_xulG':true})) {
            var d = document.createElement('description');
            var t = document.createTextNode( xul_param('msg',{'modal_xulG':true}) );
            x.appendChild( d );
            d.appendChild( t );
        }

        if (xul_param('allow_unset',{'modal_xulG':true})) { $('remove_btn').hidden = false; }

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
    if (xul_param('disallow_future_dates',{'modal_xulG':true})) {
        if ( ev.target.dateValue > new Date() ) { return { 'allowed' : false, 'reason' : $('commonStrings').getString('staff.util.timestamp_dialog.future_date_disallowed') }; }
    }
    if (xul_param('disallow_past_dates',{'modal_xulG':true})) {
        if ( util.date.check_past('YYYY-MM-DD', ev.target.value) ) { return { 'allowed' : false, 'reason' : $('commonStrings').getString('staff.util.timestamp_dialog.past_date_disallowed') }; }
    }
    if (xul_param('disallow_today',{'modal_xulG':true})) {
        if ( util.date.formatted_date(new Date(),'%F') == value) { return { 'allowed' : false, 'reason' : $('commonStrings').getString('staff.util.timestamp_dialog.today_disallowed') }; }
    }
    return { 'allowed' : true };
}

function gen_handle_apply(params) {
    return function handle_apply(ev) {
        try {

            if (!params) { params = {}; }
            if (params.remove) {
                update_modal_xulG(
                    {
                        'timestamp' : null,
                        'complete' : 1
                    }
                )
                window.close();
            } else {

                var dp = $('datepicker');
                var tp = $('timepicker');

                var check = check_date( dp.value );
                if ( ! check.allowed ) { alert( check.reason ); $('apply_btn').disabled = true; return; }

                var tp_date = tp.dateValue;
                var dp_date = dp.dateValue;
                tp_date.setFullYear( dp_date.getFullYear() );
                tp_date.setMonth( dp_date.getMonth() );
                tp_date.setDate( dp_date.getDate() );

                update_modal_xulG(
                    {
                        'timestamp' : util.date.formatted_date(tp_date,'%{iso8601}'),
                        'complete' : 1
                    }
                )
                window.close();
            }

        } catch(E) {
            alert('Error in backdate.js, handle_apply(): ' + E);
        }
    };
}
