function verify_init() {
    try {
        offlineStrings = document.getElementById('offlineStrings');

        if (typeof JSAN == 'undefined') {
            throw(
                offlineStrings.getString('common.jsan.missing')
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
                    var req = net.simple_request(
                        'AUTH_VERIFY_CREDENTIALS',
                        [ 
                            ses(), 
                            document.getElementById('barcode_prompt').value,
                            document.getElementById('name_prompt').value,
                            hex_md5( document.getElementById('password_prompt').value )
                        ]
                    );

                    if (typeof req.ilsevent != 'undefined') { throw(req); }

                    var msg_area = document.getElementById('messages');
                    var desc = document.createElement('description'); msg_area.insertBefore(desc, msg_area.firstChild);
                    desc.setAttribute('class', String(req) == '1' ? 'success_text' : 'failure_text');
                    var text = document.createTextNode( 
                        String(req) == '1' ? 
                            offlineStrings.getString('menu.cmd_verify_credentials.correct_credentials') : 
                            offlineStrings.getString('menu.cmd_verify_credentials.incorrect_credentials') 
                    );
                    desc.appendChild(text);

                } catch(E) {
                    alert(E);
                }
                document.getElementById('name_prompt').focus();
            },
            false
        );

        document.getElementById('name_prompt').focus();

    } catch(E) {
        alert(E);
    }
}
