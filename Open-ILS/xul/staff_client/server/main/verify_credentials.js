function verify_init() {
    try {
        commonStrings = document.getElementById('commonStrings');
        patronStrings = document.getElementById('patronStrings');

        if (typeof JSAN == 'undefined') {
            throw(
                commonStrings.getString('common.jsan.missing')
            );
        }

        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');

        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
        XML_HTTP_SERVER = data.server_unadorned;

        JSAN.use('util.network'); var net = new util.network();
        document.getElementById('cmd_verify').addEventListener(
            'command',
            function() {
                try {
                    var barcode = document.getElementById('barcode_prompt').value;
                    var name = document.getElementById('name_prompt').value;
                    var password = document.getElementById('password_prompt').value; 
                    var req = net.simple_request(
                        'AUTH_VERIFY_CREDENTIALS',
                        [ 
                            ses(), 
                            barcode,
                            name,
                            hex_md5( password )
                        ]
                    );

                    if (typeof req.ilsevent != 'undefined') { throw(req); }

                    var msg_area = document.getElementById('messages');
                    var hbox = document.createElement('hbox'); msg_area.insertBefore(hbox, msg_area.firstChild);
                    var success_msg = document.createElement('description'); hbox.appendChild(success_msg);
                    success_msg.setAttribute('class', String(req) == '1' ? 'success_text' : 'failure_text');
                    success_msg.appendChild(
                        document.createTextNode( 
                            String(req) == '1' ? 
                                patronStrings.getString('staff.patron.cmd_verify_credentials.correct_credentials') : 
                                patronStrings.getString('staff.patron.cmd_verify_credentials.incorrect_credentials') 
                        )
                    );
                    var name_msg = document.createElement('description'); hbox.appendChild(name_msg);
                    name_msg.appendChild(
                        document.createTextNode(
                            patronStrings.getFormattedString('staff.patron.cmd_verify_credentials.name_feedback',[name]) 
                        )
                    );
                    var barcode_msg = document.createElement('description'); hbox.appendChild(barcode_msg);
                    barcode_msg.appendChild(
                        document.createTextNode(
                            patronStrings.getFormattedString('staff.patron.cmd_verify_credentials.barcode_feedback',[barcode]) 
                        )
                    );
                    var date_msg = document.createElement('description'); hbox.appendChild(date_msg);
                    date_msg.appendChild(
                        document.createTextNode(
                            new Date()
                        )
                    );

                } catch(E) {
                    alert(E);
                }
                if (document.getElementById('name_prompt').disabled) {
                    document.getElementById('password_prompt').focus();
                } else {
                    document.getElementById('name_prompt').focus();
                }
                document.getElementById('password_prompt').value = '';
            },
            false
        );
        document.getElementById('cmd_retrieve').addEventListener(
            'command',
            function() {
                var barcode = document.getElementById('barcode_prompt').value;
                var name = document.getElementById('name_prompt').value;
                var req = net.simple_request(
                    'FM_AU_ID_RETRIEVE_VIA_BARCODE_OR_USERNAME',
                    [
                        ses(),
                        barcode,
                        name
                    ]
                );
                if (typeof req.ilsevent != 'undefined') { 
                    alert (req.desc);
                    document.getElementById('name_prompt').focus();
                } else {
                    xulG.set_patron_tab( {}, { 'id' : req } );
                }
            },
            false
        );

        if (xulG.barcode) {
            document.getElementById('name_prompt').disabled = true;
            document.getElementById('name_prompt').value = xulG.usrname;
            document.getElementById('barcode_prompt').disabled = true;
            document.getElementById('barcode_prompt').value = xulG.barcode;
            document.getElementById('cmd_retrieve').setAttribute('disabled','true');
            document.getElementById('password_prompt').focus();
        } else {
            document.getElementById('name_prompt').focus();
        }

        document.getElementById('password_prompt').addEventListener('keypress',function(e) {
            if ( e.keyCode && (e.keyCode == 13 || e.keyCode == 77)) {
                var x = document.createEvent('Event');
                x.initEvent('command',true,false);
                document.getElementById('cmd_verify').dispatchEvent(x);
            }
        });

    } catch(E) {
        alert(E);
    }
}
