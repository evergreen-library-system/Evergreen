dump('entering addon/pv_supa.js\n');
// vim:noet:sw=4:ts=4:

/*
    Usage example:

    JSAN.use('addon.pv_supa_goodstuff');
    var goodstuff = new addon.pv_supa_goodstuff();
    goodstuff.onData(
        function(data) {
            alert('Received: ' + data);
        },
        'ACTIVATE'
    );
    goodstuff.request_items();
*/

if (typeof addon == 'undefined') addon = {};
addon.pv_supa_goodstuff = function (params) {
    var obj = this;
    try {
        dump('addon: pv_supa_goodstuff() constructor\n');

        const Cc = Components.classes;
        const Ci = Components.interfaces;
        const prefs_Cc = '@mozilla.org/preferences-service;1';
        this.prefs = Cc[prefs_Cc].getService(Ci['nsIPrefBranch']);

        JSAN.use('OpenILS.data');
        this.data = new OpenILS.data();
        this.data.stash_retrieve();

        JSAN.use('util.error');
        this.error = new util.error();

        this.active = false;
        if (this.prefs.prefHasUserValue('oils.addon.pvsupa.goodstuff.enabled')){
            this.active = this.prefs.getBoolPref(
                'oils.addon.pvsupa.goodstuff.enabled'
            );
        }
        if (this.active) {
            dump('addon: pv_supa goodstuff enabled by preference\n');
        } else {
            dump('addon: pv_supa goodstuff not enabled by preference\n');
        }

        if (g) {
            if (g.checkin && this.active) {
                this.common_ui_init();
                this.socket_init();
                setTimeout(
                    function() {
                        obj.checkin_init();
                    }, 1000
                );
            }
            if (g.checkout && this.active) {
                this.common_ui_init();
                this.socket_init();
                setTimeout(
                    function() {
                        obj.checkout_init();
                    }, 1000
                );
            }
            if (String(location.href).match('/patron/barcode_entry.xul') && this.active) {
                this.common_ui_init();
                this.socket_init();
                setTimeout(
                    function() {
                        obj.patron_for_checkout_init();
                    }, 1000
                );
            }
            if (g.addons_ui) {
                this.common_ui_init();
                this.prefs_init();
            }
        }
        return this;

    } catch(E) {
        dump('addon: Error in pv_supa_goodstuff(): ' + E + '\n');
    }
}

addon.pv_supa_goodstuff.prototype = {
    'common_ui_init' : function() {
        dump('addon: pv_supa common_ui_init\n');
        var obj = this;
        try {
            var mc = document.createElement('messagecatalog');
            mc.setAttribute('id','addon_pvsupa_goodstuff_strings');
            mc.setAttribute(
                'src',
                '/xul/server/locale/'+LOCALE+'/addon/pv_supa_goodstuff.properties'
            );
            var mc_parent = $('offlineStrings')
                ? $('offlineStrings').parentNode
                : document.getElementsByTagName('window').item(0)
                || document.getElementsByTagName('html').item(0);
            mc_parent.appendChild(mc);

            // We don't really need CSS here, but as an example:
            var sss = Cc['@mozilla.org/content/style-sheet-service;1']
                .getService(Ci.nsIStyleSheetService);
            var ios = Cc['@mozilla.org/network/io-service;1']
                .getService(Ci.nsIIOService);
            var uri = ios.newURI(
                'oils://remote/xul/server/skin/addon/pv_supa_goodstuff.css',
                null,
                null
            );
            if(!sss.sheetRegistered(uri, sss.USER_SHEET)) {
                sss.loadAndRegisterSheet(uri, sss.USER_SHEET);
            }
        } catch(E) {
            dump('addon: pv_supa Error in common_ui_init(): ' + E + '\n');
        }
    },

    'socket_init' : function() {
        dump('addon: pv_supa socket_init on page ' + location.href + '\n');
        var obj = this;
        try {
            if (! this.data.addon) {
                this.data.addon = {};
            }
            if (! this.data.addon.pv_supa) {
                this.data.addon.pv_supa = {};
            }
            if (! this.data.addon.pv_supa.goodstuff) {
                this.data.addon.pv_supa.goodstuff = {};
            }
            if (! this.data.addon.pv_supa.goodstuff.message_log) {
                this.data.addon.pv_supa.goodstuff.message_log = [];
            }
            if (this.data.addon.pv_supa.goodstuff.socket) {
                    // don't know if we want to keep and re-use sockets
                    // Previously I was test .socket.isAlive() and only
                    // recreating if false
                    dump('addon: pv_supa goodstuff destroying old socket\n');
                    this.data.addon.pv_supa.goodstuff.socket.close();
                    this.data.addon.pv_supa.goodstuff.socket = null;
            }
            if (! this.data.addon.pv_supa.goodstuff.socket) {
                JSAN.use('util.socket');
                this.data.addon.pv_supa.goodstuff.socket = new util.socket(

                    this.prefs.prefHasUserValue('oils.addon.pvsupa.goodstuff.host')
                    ? this.prefs.getCharPref('oils.addon.pvsupa.goodstuff.host')
                    : '127.0.0.1',

                    this.prefs.prefHasUserValue('oils.addon.pvsupa.goodstuff.port')
                    ? this.prefs.getIntPref('oils.addon.pvsupa.goodstuff.port')
                    : 5000 /* FIXME find out actual default port */
                );
                this.data.addon.pv_supa.goodstuff.socket.onStopRequest(
                    function(request,context,result) {
                        dump('addon: pv_supa goodstuff lost connection on page ' + location.href + '\n');
                        obj.updateStatusBar('!lost connection\n');
                        obj.data.addon.pv_supa.goodstuff.last_start_end_msg = null;
                    }
                );
                dump('addon: pv_supa goodstuff socket opened\n');
                this.updateStatusBar('!new connection\n');
                obj.data.addon.pv_supa.goodstuff.last_start_end_msg = null;
            } else {
                dump('addon: pv_supa goodstuff socket already opened\n');
            }
            this.socket = this.data.addon.pv_supa.goodstuff.socket;
            this.token = location.href + ' : ' + new Date();
            this.data.addon.pv_supa.goodstuff.token = this.token;
            var obj = this;
            setTimeout(
                function() {
                    dump(
                        'addon: pv_supa goodstuff socket\n\t' +
                        'host: ' + obj.socket.host + '\n\t' +
                        'port: ' + obj.socket.port + '\n\t' +
                        'token: '+ obj.token
                         + '\n'
                    );
                },
                0
            );
        } catch(E) {
            dump('addon: pv_supa Error in socket_init(): ' + E + '\n');
        }
    },
    'updateStatusBar' : function(d) {
        try {
            var obj = this;
            if (xulG && xulG.set_statusbar) {
                if (obj.data.addon.pv_supa.goodstuff.message_log.length > 16) {
                    obj.data.addon.pv_supa.goodstuff.message_log.shift();
                }
                obj.data.addon.pv_supa.goodstuff.message_log.push(d);
                xulG.set_statusbar(
                    5,
                    'GoodStuff: ' + d,
                    obj.data.addon.pv_supa.goodstuff.message_log.join(""),
                    function(ev) {
                        alert(
                            obj.data.addon.pv_supa.goodstuff.message_log.join("")
                        );
                    }
                );
            }
        } catch(E) {
            dump('addon: pv_supa Error in updateStatusBar('+d+'): ' + E + '\n');
        }
    },
    'onData' : function(f,security) {
        dump('addon: setting pv_supa goodstuff onData callback, on page '
            + location.href + ' with token ' + this.token + '\n');
        var obj = this;
        this.socket.dataCallback(
            function(d) {
                try {
                    dump('addon: dataCallback func at page '
                        + location.href + ' with token ' + obj.token + '\n');
                    obj.updateStatusBar('>' + d);
                    if (obj.token != obj.data.addon.pv_supa.goodstuff.token) {
                        var e = 'addon error: pv supa: reading data out of turn\n';
                        dump(e);
                        obj.updateStatusBar('!' + e);
                    }
                    d= d.replace("\n","","g").replace("\r","","g").replace(" ","","g");
                    var p = d.split("|");
                    if (p.length == 1) {
                        if (f) {
                            f(p[0]); // hopefully a patron barcode
                        }
                    } else if (p[0] == 'START') {
                        obj.data.addon.pv_supa.goodstuff.last_start_end_msg = p[0];
                    } else if (p[0] == 'END') {
                        obj.data.addon.pv_supa.goodstuff.last_start_end_msg = p[0];
                    } else if (p[1] == 'NOK') {
                        if (security) {
                            var msg = $('addon_pvsupa_goodstuff_strings').getFormattedString(
                                security == 'ACTIVATE'
                                ? 'rfid.set_security_failure.prompt.message.activate_failure'
                                : 'rfid.set_security_failure.prompt.message.deactivate_failure',
                                [ p[0] ]
                            );
                            var choice = obj.error.yns_alert(
                                msg,
                                $('addon_pvsupa_goodstuff_strings').getString(
                                    'rfid.set_security_failure.prompt.title'
                                ),
                                $('addon_pvsupa_goodstuff_strings').getString(
                                    'rfid.set_security_failure.prompt.button.activate_security'
                                ),
                                $('addon_pvsupa_goodstuff_strings').getString(
                                    'rfid.set_security_failure.prompt.button.deactivate_security'
                                ),
                                $('addon_pvsupa_goodstuff_strings').getString(
                                    'rfid.set_security_failure.prompt.button.do_nothing_with_security'
                                ),
                                ''
                            );
                            if (choice == 0) {
                                obj.write(p[0]+'|ACTIVATE\n');
                            } else if (choice == 1) {
                                obj.write(p[0]+'|DEACTIVATE\n');
                            } else {
                                obj.write(p[0]+'\n');
                            }
                        } else {
                            dump('addon: unknown error\n');
                        }
                    } else if (p[1] == 'OK') {
                        // ignore
                    } else if (p[1].match('/')) {
                        var counts = p[1].split('/');
                        var read = counts[0];
                        var set = counts[1];
                        if (read != set) {
                            var msg = $('addon_pvsupa_goodstuff_strings').getFormattedString(
                                'rfid.partial_scan.prompt.message',
                                [ read, set, p[0] ]
                            );
                            var choice = obj.error.yns_alert(
                                msg,
                                $('addon_pvsupa_goodstuff_strings').getString(
                                    'rfid.partial_scan.prompt.title'
                                ),
                                $('addon_pvsupa_goodstuff_strings').getString(
                                    'rfid.partial_scan.prompt.button.rescan'
                                ),
                                $('addon_pvsupa_goodstuff_strings').getString(
                                    'rfid.partial_scan.prompt.button.skip'
                                ),
                                $('addon_pvsupa_goodstuff_strings').getString(
                                    'rfid.partial_scan.prompt.button.proceed'
                                ),
                                ''
                            );
                            if (!choice || choice == 0) {
                                obj.write(p[0]+'|REREAD\n');
                            } else if (choice == 1) {
                                obj.write(p[0]+'\n'); // do nothing, skip
                            } else if (choice == 2) {
                                if (f) {
                                    f(p[0]); // hopefully an item barcode
                                }
                            }
                        } else {
                            if (f) {
                                f(p[0]); // hopefully an item barcode
                            }
                        }
                    } else {
                        if (f) {
                            f(p[0]); // no idea; shouldn't get here
                        }
                    }
                } catch(E) {
                    dump('addon: error in onData callback: ' + E + '\n');
                }
            }
        );
    },
    'write' : function(s,ignore_token) {
        dump('addon: write "' + s + '", on page ' + location.href + ' with token ' + this.token + '\n');
        if ((this.token != this.data.addon.pv_supa.goodstuff.token) && !ignore_token) {
            var e = 'addon error: pv supa: sending data out of turn\n';
            dump(e);
            this.updateStatusBar('!' + e);
        }
        if (!this.socket.socket.isAlive()) {
            dump('addon error: pv supa: writing to not alive socket\n');
        }
        this.updateStatusBar('<' + s);
        this.socket.write(s);
    },
    'request_items' : function() {
        dump('addon: request_items on page ' + location.href + '\n');
        if (this.data.addon.pv_supa.goodstuff.last_start_end_msg == 'START') {
            this.write('END\n');
        }
        this.write('START|ITEM\n'); // we expect START|OK
    },
    'request_patrons' : function() {
        dump('addon: request_patrons on page ' + location.href + '\n');
        if (this.data.addon.pv_supa.goodstuff.last_start_end_msg == 'START') {
            this.write('END\n');
        }
        this.write('START|PATRON\n'); // we expect START|OK
    },
    'end_session' : function() {
        dump('addon: end_session on page ' + location.href + '\n');
        if (this.token == this.data.addon.pv_supa.goodstuff.token) {
            if (this.data.addon.pv_supa.goodstuff.last_start_end_msg == 'START') {
                this.write('END\n');
            }
            this.data.addon.pv_supa.goodstuff.socket.close();
            this.data.addon.pv_supa.goodstuff.socket = null;
        }
    },

    'prefs_init' : function() {
        dump('addon: pv_supa prefs_init\n');
        var obj = this;

        try {
            if (! (g && g.addons_ui)) { return; }

            const Cc = Components.classes;
            const Ci = Components.interfaces;

            function post_overlay() {
                var tab = $('pv_supa_goodstuff_tab');
                tab.setAttribute(
                    'label',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.tab.label')
                );
                tab.setAttribute(
                    'accesskey',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.tab.accesskey')
                );

                var enabled_label = $('pv_supa_goodstuff_enabled_label');
                enabled_label.setAttribute(
                    'value',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.checkbox.label')
                );
                enabled_label.setAttribute(
                    'accesskey',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.checkbox.accesskey')
                );

                var host_label = $('pv_supa_goodstuff_hostname_label');
                host_label.setAttribute(
                    'value',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.host.label')
                );
                host_label.setAttribute(
                    'accesskey',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.host.accesskey')
                );

                var port_label = $('pv_supa_goodstuff_port_label');
                port_label.setAttribute(
                    'value',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.port.label')
                );
                port_label.setAttribute(
                    'accesskey',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.port.accesskey')
                );

                var save_btn = $('pv_supa_goodstuff_save_btn');
                save_btn.setAttribute(
                    'label',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.update.label')
                );
                save_btn.setAttribute(
                    'accesskey',
                    $('addon_pvsupa_goodstuff_strings').getString('prefs.update.accesskey')
                );
                save_btn.addEventListener(
                    'command',
                    function() {
                        obj.save_prefs();
                    },
                    false
                );
                obj.display_prefs();
            }

            function myObserver() { this.register(); }
            myObserver.prototype = {
                register: function() {
                    var observerService = Cc["@mozilla.org/observer-service;1"].getService(Ci.nsIObserverService);
                    observerService.addObserver(this, "xul-overlay-merged", false);
                },
                unregister: function() {
                    var observerService = Cc["@mozilla.org/observer-service;1"].getService(Ci.nsIObserverService);
                    observerService.removeObserver(this, "xul-overlay-merged");
                },
                observe: function(subject,topic,data) {
                    dump('observe: <'+subject+','+topic+','+data+'>\n');
                    // setTimeout is needed here for xulrunner 1.8
                    setTimeout( function() { try { post_overlay(); } catch(E) { alert(E); } }, 0 );
                }
            }

            var observer = new myObserver();
            var url = '/xul/server/addon/pv_supa_goodstuff_config_overlay.xul';
            document.loadOverlay(location.protocol + '//' + location.hostname + url,observer)

        } catch(E) {
            dump('addon: pv_supa Error in prefs_init(): ' + E + '\n');
        }
    },

    'display_prefs' : function() {
        var obj = this;
        try {
            $('pv_supa_goodstuff_enabled_cb').checked = obj.active;
            $('pv_supa_goodstuff_hostname_tb').value =
                obj.prefs.prefHasUserValue('oils.addon.pvsupa.goodstuff.host')
                ? obj.prefs.getCharPref('oils.addon.pvsupa.goodstuff.host')
                : '127.0.0.1';

            $('pv_supa_goodstuff_port_tb').value =
                obj.prefs.prefHasUserValue('oils.addon.pvsupa.goodstuff.port')
                ? obj.prefs.getIntPref('oils.addon.pvsupa.goodstuff.port')
                : 5000; /* FIXME find out actual default port */

        } catch(E) {
            dump('addon: pv_supa Error in display_prefs(): ' + E + '\n');
        }
    },

    'save_prefs' : function() {
        var obj = this;
        try {
            obj.prefs.setBoolPref(
                'oils.addon.pvsupa.goodstuff.enabled',
                $('pv_supa_goodstuff_enabled_cb').checked
            );
            obj.prefs.setCharPref(
                'oils.addon.pvsupa.goodstuff.host',
                $('pv_supa_goodstuff_hostname_tb').value
            );
            obj.prefs.setIntPref(
                'oils.addon.pvsupa.goodstuff.port',
                $('pv_supa_goodstuff_port_tb').value
            );
            location.href = location.href;
        } catch(E) {
            dump('addon: pv_supa Error in save_prefs(): ' + E + '\n');
        }
    },

    'checkin_init' : function() {
        dump('addon: pv_supa checkin_init\n');
        var obj = this;

        try {

            if (! (g && g.checkin)) { return; }

            function setOnData() {
                obj.onData(
                    function(barcode) {
                        g.checkin.controller.view.checkin_barcode_entry_textbox.value = barcode;
                        g.checkin.checkin();
                        // unlike checkout, I don't really care whether the checkin
                        // succeeds or not; I think we should activate security on
                        // the item and move on.  Errored items are still listed in
                        // the interface and can be handled separately.
                        obj.write(barcode+'|ACTIVATE\n');
                    },
                    'ACTIVATE'
                );
            }
            setOnData();

            var spacer = $('pcii3s');
            var rfid_cb = document.createElement('checkbox');
            rfid_cb.setAttribute('id','addon_rfid_cb');
            rfid_cb.setAttribute(
                'label',
                $('addon_pvsupa_goodstuff_strings').getString(
                    'rfid.checkbox.label'
                )
            );
            rfid_cb.setAttribute(
                'accesskey',
                $('addon_pvsupa_goodstuff_strings').getString(
                    'rfid.checkbox.accesskey'
                )
            );
            spacer.parentNode.insertBefore(rfid_cb,spacer);
            if (obj.prefs.prefHasUserValue(
                    'oils.addon.pvsupa.goodstuff.checkin.rfid_checkbox.checked'
            )){
                rfid_cb.checked = obj.prefs.getBoolPref(
                    'oils.addon.pvsupa.goodstuff.checkin.rfid_checkbox.checked'
                );
            }

            if (rfid_cb.checked) {
                obj.request_items();
            }

            rfid_cb.addEventListener(
                'command',
                function(ev) {
                    if (ev.target.checked) {
                        obj.socket_init();
                        setTimeout(
                            function() {
                                setOnData();
                                obj.request_items();
                            }, 1000
                        );
                    } else {
                        obj.end_session();
                    }
                    obj.prefs.setBoolPref(
                        'oils.addon.pvsupa.goodstuff.checkin.rfid_checkbox.checked',
                        ev.target.checked
                    );
                }
            );

            window.addEventListener(
                'unload',
                function(ev) {
                    obj.end_session();
                },
                false
            );
            window.addEventListener(
                'tab_focus',
                function(ev) {
                    obj.socket_init();
                    if (rfid_cb.checked) {
                        setTimeout(
                            function() {
                                setOnData();
                                obj.request_items();
                            }, 1000
                        );
                    }
                },
                false
            );

        } catch(E) {
            dump('addon: pv_supa Error in checkin_init(): ' + E + '\n');
        }
    },
    'checkout_init' : function() {
        dump('addon: pv_supa checkout_init\n');
        var obj = this;

        try {

            if (! (g && g.checkout)) { return; }

            function setOnData() {
                obj.onData(
                    function(barcode) {
                        g.checkout.controller.view.checkout_barcode_entry_textbox.value = barcode;
                        var pre_list_count = g.checkout.list.row_count.total;
                        g.checkout.checkout({'barcode':barcode});
                        var post_list_count = g.checkout.list.row_count.total;
                        if (pre_list_count != post_list_count) {
                            obj.write(barcode+'|DEACTIVATE\n'); // checkout success
                        } else {
                            obj.write(barcode+'|ACTIVATE\n'); // checkout failure
                        }
                    },
                    'DEACTIVATE'
                );
            }
            setOnData();

            var spacer = $('pcii3s');
            var rfid_cb = document.createElement('checkbox');
            rfid_cb.setAttribute('id','addon_rfid_cb');
            rfid_cb.setAttribute(
                'label',
                $('addon_pvsupa_goodstuff_strings').getString(
                    'rfid.checkbox.label'
                )
            );
            rfid_cb.setAttribute(
                'accesskey',
                $('addon_pvsupa_goodstuff_strings').getString(
                    'rfid.checkbox.accesskey'
                )
            );
            spacer.parentNode.insertBefore(rfid_cb,spacer);
            if (obj.prefs.prefHasUserValue(
                    'oils.addon.pvsupa.goodstuff.checkout.rfid_checkbox.checked'
            )){
                rfid_cb.checked = obj.prefs.getBoolPref(
                    'oils.addon.pvsupa.goodstuff.checkout.rfid_checkbox.checked'
                );
            }

            if (rfid_cb.checked) {
                obj.request_items();
            }

            rfid_cb.addEventListener(
                'command',
                function(ev) {
                    if (ev.target.checked) {
                        obj.socket_init();
                        setTimeout(
                            function() {
                                setOnData();
                                obj.request_items();
                            }, 1000
                        );
                    } else {
                        obj.end_session();
                    }
                    obj.prefs.setBoolPref(
                        'oils.addon.pvsupa.goodstuff.checkout.rfid_checkbox.checked',
                        ev.target.checked
                    );
                }
            );

            window.addEventListener(
                'unload',
                function(ev) {
                    obj.end_session();
                },
                false
            );
            window.addEventListener(
                'tab_focus',
                function(ev) {
                    obj.socket_init();
                    if (rfid_cb.checked) {
                        setTimeout(
                            function() {
                                setOnData();
                                obj.request_items();
                            }, 1000
                        );
                    }
                },
                false
            );

        } catch(E) {
            dump('addon: pv_supa Error in checkout_init(): ' + E + '\n');
        }
    },
    'patron_for_checkout_init' : function() {
        dump('addon: pv_supa patron_for_checkout_init\n');
        var obj = this;

        try {

            if (! String(location.href).match('/patron/barcode_entry.xul')) { return; }

            function setOnData() {
                obj.onData(
                    function(barcode) {
                        obj.write(barcode+'\n');
                        $('barcode_tb').value = barcode;
                        window.submit();
                    },
                    'DEACTIVATE'
                );
            }
            setOnData();

            var hbox = $('barcode_tb').parentNode;
            var rfid_cb = document.createElement('checkbox');
            rfid_cb.setAttribute('id','addon_rfid_cb');
            rfid_cb.setAttribute(
                'label',
                $('addon_pvsupa_goodstuff_strings').getString(
                    'rfid.checkbox.label'
                )
            );
            rfid_cb.setAttribute(
                'accesskey',
                $('addon_pvsupa_goodstuff_strings').getString(
                    'rfid.checkbox.accesskey'
                )
            );
            hbox.appendChild(rfid_cb);
            if (obj.prefs.prefHasUserValue(
                    'oils.addon.pvsupa.goodstuff.patron_for_checkout.rfid_checkbox.checked'
            )){
                rfid_cb.checked = obj.prefs.getBoolPref(
                    'oils.addon.pvsupa.goodstuff.patron_for_checkout.rfid_checkbox.checked'
                );
            }

            if (rfid_cb.checked) {
                obj.request_patrons();
            }

            rfid_cb.addEventListener(
                'command',
                function(ev) {
                    if (ev.target.checked) {
                        obj.socket_init();
                        setTimeout(
                            function() {
                                setOnData();
                                obj.request_patrons();
                            }, 1000
                        );
                    } else {
                        obj.end_session();
                    }
                    obj.prefs.setBoolPref(
                        'oils.addon.pvsupa.goodstuff.patron_for_checkout.rfid_checkbox.checked',
                        ev.target.checked
                    );
                }
            );

            window.addEventListener(
                'unload',
                function(ev) {
                    obj.end_session();
                },
                false
            );
            window.addEventListener(
                'tab_focus',
                function(ev) {
                    obj.socket_init();
                    if (rfid_cb.checked) {
                        setTimeout(
                            function() {
                                setOnData();
                                obj.request_patrons();
                            }, 1000
                        );
                    }
                },
                false
            );

        } catch(E) {
            dump('addon: pv_supa Error in patron_for_checkout_init(): ' + E + '\n');
        }
    }



}

