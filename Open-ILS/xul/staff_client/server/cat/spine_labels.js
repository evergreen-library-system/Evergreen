        function my_init() {
            try {
                if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
                JSAN.errorLevel = "die"; // none, warn, or die
                JSAN.addRepository('/xul/server/');
                JSAN.use('util.error'); g.error = new util.error();
                g.error.sdump('D_TRACE','my_init() for spine_labels.xul');

                JSAN.use('util.network'); g.network = new util.network();

                g.cgi = new CGI();

                g.barcodes = [];
                if (g.cgi.param('barcodes')) {
                    g.barcodes = g.barcodes.concat( JSON2js(g.cgi.param('barcodes')) );
                }
                JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.stash_retrieve();
                if (g.data.temp_barcodes_for_labels) {
                    g.barcodes = g.barcodes.concat( g.data.temp_barcodes_for_labels );
                    g.data.temp_barcodes_for_labels = null; g.data.stash('temp_barcodes_for_labels');
                }
                if (xulG.barcodes) {
                    g.barcodes = g.barcodes.concat( xulG.barcodes );
                }

                JSAN.use('circ.util');
                g.cols = circ.util.columns( {} );
                g.col_map = {};
                for (var i = 0; i < g.cols.length; i++) {
                    g.col_map[ g.cols[i].id ] = { 'regex' : new RegExp('%' + g.cols[i].id + '%',"g"), 'render' : g.cols[i].render };
                }

                g.volumes = {};

                for (var i = 0; i < g.barcodes.length; i++) {
                    var copy = g.network.simple_request( 'FM_ACP_RETRIEVE_VIA_BARCODE.authoritative', [ g.barcodes[i] ] );
                    if (typeof copy.ilsevent != 'undefined') throw(copy);
                    var label_prefix = copy.location().label_prefix() || '';
                    var label_suffix = copy.location().label_suffix() || '';
                    if (!g.volumes[ copy.call_number() ]) {
                        var volume = g.network.simple_request( 'FM_ACN_RETRIEVE.authoritative', [ copy.call_number() ] );
                        if (typeof volume.ilsevent != 'undefined') throw(volume);
                        var record = g.network.simple_request('MODS_SLIM_RECORD_RETRIEVE.authoritative', [ volume.record() ]);
                        volume.record( record );

                        /* The volume object has native prefix and suffixes now, so affix the ones coming from copy locations */
                        var temp_prefix = label_prefix + ' ' + (typeof volume.prefix() == 'object' ? volume.prefix().label() : volume.prefix());
                        var temp_suffix = (typeof volume.suffix() == 'object' ? volume.suffix().label() : volume.suffix()) + ' ' + label_suffix;

                        /* And assume that leading and trailing spaces can be trimmed */
                        temp_prefix = temp_prefix.replace(/\s+$/,'').replace(/^\s+/,'');
                        temp_suffix = temp_suffix.replace(/\s+$/,'').replace(/^\s+/,'');

                        volume.prefix( temp_prefix );
                        volume.suffix( temp_suffix );

                        g.volumes[ volume.id() ] = volume;
                    }
                    if (g.volumes[ copy.call_number() ].copies()) {
                        var copies = g.volumes[ copy.call_number() ].copies();
                        copies.push( copy );
                        g.volumes[ copy.call_number() ].copies( copies );
                    } else {
                        g.volumes[ copy.call_number() ].copies( [ copy ] );
                    }
                }

                generate();

                if (typeof xulG != 'undefined') $('close').hidden = true;

            } catch(E) {
                try {
                    g.error.standard_unexpected_error_alert('/xul/server/cat/spine_labels.xul',E);
                } catch(F) {
                    alert('FIXME: ' + js2JSON(E));
                }
            }
        }

        function show_macros() {
            JSAN.use('util.functional');
            alert( util.functional.map_list( g.cols, function(o) { return '%' + o.id + '%'; } ).join(" ") );
        }

        function $(id) { return dojo.byId(id); }

        function generate(override) {
            try {
                var idx = 0;
                JSAN.use('util.text');
                JSAN.use('util.money');
                JSAN.use('util.widgets');
                var pn = $('panel');
                $('preview').disabled = false;

                /* Grab from OU settings, then fall back to hardcoded defaults */
                var label_cfg = {};
                label_cfg.spine_width = Number($('lw').value); /* spine label width */
                if (!label_cfg.spine_width) {
                    label_cfg.spine_width = g.data.hash.aous['cat.spine.line.width'] || 8;
                    $('lw').value = label_cfg.spine_width;
                }
                label_cfg.spine_length = Number($('ll').value); /* spine label length */
                if (!label_cfg.spine_length) {
                    label_cfg.spine_length = g.data.hash.aous['cat.spine.line.height'] || 9;
                    $('ll').value = label_cfg.spine_length;
                }
                label_cfg.spine_left_margin = Number($('lm').value); /* left margin */
                if (!label_cfg.spine_left_margin) {
                    label_cfg.spine_left_margin = g.data.hash.aous['cat.spine.line.margin'] || 0;
                    $('lm').value = label_cfg.spine_left_margin;
                }
                label_cfg.font_size = Number( $('pt').value );  /* font size */
                if (!label_cfg.font_size) {
                    label_cfg.font_size = g.data.hash.aous['cat.label.font.size'] || 10;
                    $('pt').value = label_cfg.font_size;
                }
                label_cfg.font_weight = $('font_weight').value;  /* font weight */
                if (!label_cfg.font_weight) {
                    label_cfg.font_weight = g.data.hash.aous['cat.label.font.weight'] || 'normal';
                    $('font_weight').value = label_cfg.font_weight;
                }
                label_cfg.font_family = g.data.hash.aous['cat.label.font.family'] || 'monospace';
                label_cfg.pocket_width = Number($('plw').value) || 28; /* pocket label width */
                label_cfg.pocket_length = Number($('pll').value) || 9; /* pocket label length */

                if (override) {
                    var gb = $('acn_' + g.volumes[override.acn].id());
                    util.widgets.remove_children('acn_' + g.volumes[override.acn].id());
                    generate_labels(g.volumes[override.acn], gb, label_cfg, override);
                } else {
                    util.widgets.remove_children('panel');
                    for (var i in g.volumes) {
                        var vb = document.createElement('vbox'); pn.appendChild(vb);
                        vb.setAttribute('name','template');
                        vb.setAttribute('acn_id',g.volumes[i].id());
                        var ds = document.createElement('description'); vb.appendChild(ds);
                        ds.appendChild( document.createTextNode( g.volumes[i].label() ) );
                        var ds2 = document.createElement('description'); vb.appendChild(ds2);
                        ds2.appendChild( document.createTextNode( g.volumes[i].copies().length + ' ' + (
                            g.volumes[i].copies().length == 1 ? $("catStrings").getString('staff.cat.spine_labels.copy') : $("catStrings").getString('staff.cat.spine_labels.copies')) ) );
                        ds2.setAttribute('style','color: green');
                        var hb = document.createElement('hbox'); vb.appendChild(hb);

                        var gb = document.createElement('groupbox');
                        hb.appendChild(gb); 
                        gb.setAttribute('id','acn_' + g.volumes[i].id());
                        gb.setAttribute('style','border: solid black 2px');

                        generate_labels(g.volumes[i], gb, label_cfg, override);

                        idx++;
                    }
                }
            } catch(E) {
                g.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.spine_labels.generate.std_unexpeceted_err'),E);
            }
        }

        function generate_labels(volume, label_node, label_cfg, override) {
            var names;
            var callnum;

            if (override && volume.id() == override.acn) {
                /* If we're calling ourself, we'll have an altered label */
                callnum = String(override.label);
            } else {
                /* take the call number and split it on whitespace */
                callnum = String(volume.label());
            }
            /* handle spine labels differently if using LC */
            if (volume.label_class() == 3) {
                /* for LC, split between classification subclass letters and numbers */
                var lc_class_re = /^([A-Z]{1,3})([0-9]+.*?)$/i;
                var lc_class_match = lc_class_re.exec(callnum);
                if (lc_class_match && lc_class_match.length > 1) {
                    callnum = lc_class_match[1] + ' ' + lc_class_match[2];
                }

                /* for LC, split between Cutter numbers */
                var lc_cutter_re = /^(.*)(\.[A-Z]{1}[0-9]+.*?)$/ig;
                var lc_cutter_match = lc_cutter_re.exec(callnum);
                if (lc_cutter_match && lc_cutter_match.length > 1) {
                    callnum = '';
                    for (var i = 1; i < lc_cutter_match.length; i++) {
                        callnum += lc_cutter_match[i] + ' ';
                    }
                }
            }

            /* Only add the prefixes and suffixes once */
            if (!override || volume.id() != override.acn) {
                if (volume.prefix()) {
                    callnum = volume.prefix() + ' ' + callnum;
                }
                if (volume.suffix()) {
                    callnum += ' ' + volume.suffix();
                }
            }

            names = callnum.split(/\s+/);
            var j = 0;
            while (j < label_cfg.spine_length || j < label_cfg.pocket_length) {
                var hb2 = document.createElement('hbox'); label_node.appendChild(hb2);
                
                /* spine */
                if (j < label_cfg.spine_length) {
                    var tb = document.createElement('textbox'); hb2.appendChild(tb); 
                    tb.value = '';
                    tb.setAttribute('class','plain');
                    tb.setAttribute('style',
                        'font-family: ' + label_cfg.font_family
                        + '; font-size: ' + label_cfg.font_size
                        + '; font-weight: ' + label_cfg.font_weight
                    );
                    tb.setAttribute('size',label_cfg.spine_width+1);
                    tb.setAttribute('maxlength',label_cfg.spine_width);
                    tb.setAttribute('name','spine');
                    var spine_row_id = 'acn_' + volume.id() + '_spine_' + j;
                    tb.setAttribute('id',spine_row_id);

                    var name = names.shift();
                    if (name) {
                        name = String( name );

                        /* if the name is greater than the label width... */
                        if (name.length > label_cfg.spine_width) {
                            /* then try to split it on periods */
                            var sname = name.split(/\./);
                            if (sname.length > 1) {
                                /* if we can, then put the periods back in on each splitted element */
                                if (name.match(/^\./)) sname[0] = '.' + sname[0];
                                for (var k = 1; k < sname.length; k++) sname[k] = '.' + sname[k];
                                /* and put all but the first one back into the names array */
                                names = sname.slice(1).concat( names );
                                /* if the name fragment is still greater than the label width... */
                                if (sname[0].length > label_cfg.spine_width) {
                                    /* then just truncate and throw the rest back into the names array */
                                    tb.value = sname[0].substr(0,label_cfg.spine_width);
                                    names = [ sname[0].substr(label_cfg.spine_width) ].concat( names );
                                } else {
                                    /* otherwise we're set */
                                    tb.value = sname[0];
                                }
                            } else {
                                /* if we can't split on periods, then just truncate and throw the rest back into the names array */
                                tb.value = name.substr(0,label_cfg.spine_width);
                                names = [ name.substr(label_cfg.spine_width) ].concat( names );
                            }
                        } else {
                            /* otherwise we're set */
                            tb.value = name;
                        }
                    }
                    dojo.connect($(spine_row_id), 'onkeypress', 'spine_label_key_events');
                }

                /* pocket */
                if ($('pl').checked && j < label_cfg.pocket_length) {
                    var tb2 = document.createElement('textbox'); hb2.appendChild(tb2); 
                    tb2.value = '';
                    tb2.setAttribute('class','plain');
                    tb2.setAttribute('style',
                        'font-family: ' + label_cfg.font_family
                        + '; font-size: ' + label_cfg.font_size
                        + '; font-weight: ' + label_cfg.font_weight
                    );
                    tb2.setAttribute('size',label_cfg.pocket_width+1); tb2.setAttribute('maxlength',label_cfg.pocket_width);
                    tb2.setAttribute('name','pocket');
                    if ($('title').checked && $('title_line').value == j + 1 && instanceOf(volume.record(),mvr)) {
                        if (volume.record().title()) {
                            tb2.value = util.text.wrap_on_space( volume.record().title(), label_cfg.pocket_width )[0];
                        } else {
                            tb2.value = '';
                        }
                    }
                    if ($('title_r').checked && $('title_r_line').value == j + 1 && instanceOf(volume.record(),mvr)) {
                        if (volume.record().title()) {
                            tb2.value = ( ($('title_r_indent').checked ? ' ' : '') + util.text.wrap_on_space( volume.record().title(), label_cfg.pocket_width )[1]).substr(0,label_cfg.pocket_width);
                        } else {
                            tb2.value = '';
                        }
                    }
                    if ($('author').checked && $('author_line').value == j + 1 && instanceOf(volume.record(),mvr)) {
                        if (volume.record().author()) {
                            tb2.value = volume.record().author().substr(0,label_cfg.pocket_width);
                        } else {
                            tb2.value = '';
                        }
                    }
                    if ($('call_number').checked && $('call_number_line').value == j + 1) {
                        tb2.value = (
                            (volume.prefix() + ' ' + volume.label() + ' ' + volume.suffix())
                            .replace(/\s+$/,'')
                            .replace(/^\s+/,'')
                            .substr(0,label_cfg.pocket_width)
                        );
                    }
                    if ($('owning_lib_shortname').checked && $('owning_lib_shortname_line').value == j + 1) {
                        var lib = volume.owning_lib();
                        if (!instanceOf(lib,aou)) lib = g.data.hash.aou[ lib ];
                        tb2.value = lib.shortname().substr(0,label_cfg.pocket_width);
                    }
                    if ($('owning_lib').checked && $('owning_lib_line').value == j + 1) {
                        var lib = volume.owning_lib();
                        if (!instanceOf(lib,aou)) lib = g.data.hash.aou[ lib ];
                        tb2.value = lib.name().substr(0,label_cfg.pocket_width);
                    }
                    if ($('shelving_location').checked && $('shelving_location_line').value == j + 1) {
                        tb2.value = '%location%';
                    }
                    if ($('barcode').checked && $('barcode_line').value == j + 1) {
                        tb2.value = '%barcode%';
                    }
                    if ($('custom1').checked && $('custom1_line').value == j + 1) {
                        tb2.value = $('custom1_tb').value;
                    }
                    if ($('custom2').checked && $('custom2_line').value == j + 1) {
                        tb2.value = $('custom2_tb').value;
                    }
                    if ($('custom3').checked && $('custom3_line').value == j + 1) {
                        tb2.value = $('custom3_tb').value;
                    }
                    if ($('custom4').checked && $('custom4_line').value == j + 1) {
                        tb2.value = $('custom4_tb').value;
                    }
                }

                j++;
            }
        }

        function spine_label_key_events (event) {

            /* Current value of the inpux box */
            var line_value = event.target.value;

            /* Cursor positions */
            var sel_start = event.target.selectionStart;
            var sel_end = event.target.selectionEnd;

            /* Identifiers for this row: "acn_ID_spine_ROW" */
            var atts = event.target.id.split('_');
            var row_id = {
                "acn": atts[1],
                "spine": atts[3],
                "prefix": 'acn_' + atts[1] + '_spine_'
            };

            switch (event.charOrCode) {
                case dojo.keys.ENTER : {
                    /* Create a new row by inserting a space at the
                     * current cursor point, then regenerating the
                     * label
                     */
                    if (sel_start == sel_end) {
                        if (sel_start == 0) {
                            /* If the cursor is at the start of the line:
                             * insert new line
                             */
                            line_value = ' ' + line_value;
                        } else if (sel_start == line_value.length) {
                            /* Special case if the cursor is at the end of the line:
                             * move to next line
                             */
                            var next_row = $(row_id.prefix + (parseInt(row_id.spine) + 1));
                            if (next_row) {
                                next_row.focus();
                            }
                            break;
                        } else {
                            line_value = line_value.substr(0, sel_start) + ' ' + line_value.substr(sel_end);
                        }
                    } else {
                        line_value = line_value.substr(0, sel_start) + ' ' + line_value.substr(sel_end);
                    }
                    event.target.value = line_value;

                    /* Recreate the label */
                    var new_label = '';
                    var chunk;
                    var x = 0;
                    while (chunk = $(row_id.prefix + x)) {
                        if (x > 0) {
                            new_label += ' ' + chunk.value;
                        } else {
                            new_label = chunk.value;
                        }
                        x++;
                    }
                    generate({"acn": row_id.acn, "label": new_label});
                    $(row_id.prefix + row_id.spine).focus();
                    break;
                }

                case dojo.keys.BACKSPACE : {
                    /* Delete line if at the start of an input box */
                    if (sel_start == 0 && sel_end == sel_start) {
                        var new_label = '';
                        var chunk;
                        var x = 0;
                        while (x <= (row_id.spine - 1) && (chunk = $(row_id.prefix + x))) {
                            if (x > 0) {
                                new_label += ' ' + chunk.value;
                            } else {
                                new_label = chunk.value;
                            }
                            x++;
                        }

                        if (chunk = $(row_id.prefix + x)) {
                            new_label += chunk.value;
                            x++;
                        }

                        while (chunk = $(row_id.prefix + x)) {
                            new_label += ' ' + chunk.value;
                            x++;
                        }
                        generate({"acn": row_id.acn, "label": new_label});
                        $(row_id.prefix + row_id.spine).focus();
                    }
                    if (sel_start == 0) {
                        /* Move to the previous row */
                        var prev_row = $(row_id.prefix + (parseInt(row_id.spine) - 1));
                        if (prev_row) {
                            prev_row.focus();
                        }
                    }
                    break;
                }

                case dojo.keys.DELETE : {
                    /* Delete line if at the end of an input box */
                    if (sel_start == event.target.textLength) {
                        var new_label = '';
                        var chunk;
                        var x = 0;
                        while (x <= row_id.spine && (chunk = $(row_id.prefix + x))) {
                            if (x > 0) {
                                new_label += ' ' + chunk.value;
                            } else {
                                new_label = chunk.value;
                            }
                            x++;
                        }

                        if (chunk = $(row_id.prefix + x)) {
                            new_label += chunk.value;
                            x++;
                        }

                        while (chunk = $(row_id.prefix + x)) {
                            new_label += ' ' + chunk.value;
                            x++;
                        }
                        generate({"acn": row_id.acn, "label": new_label});
                        $(row_id.prefix + row_id.spine).focus();
                    }
                    break;
                }

                case dojo.keys.UP_ARROW : {
                    /* Move to the previous row */
                    var prev_row = $(row_id.prefix + (parseInt(row_id.spine) - 1));
                    if (prev_row) {
                        prev_row.focus();
                    }
                    break;
                }

                case dojo.keys.DOWN_ARROW : {
                    /* Move to the next row */
                    var next_row = $(row_id.prefix + (parseInt(row_id.spine) + 1));
                    if (next_row) {
                        next_row.focus();
                    }
                    break;
                }

                default : {
                    break;
                }
            }
        }

        function expand_macros(text,copy,volume,record) {
            var my = { 'acp' : copy, 'acn' : volume, 'mvr' : record };
            var obj = { 'data' : g.data };
            for (var i in g.col_map) {
                var re = g.col_map[i].regex;
                if (text.match(re)) {
                    try {
                        text = text.replace(re, (typeof g.col_map[i].render == 'function' ? g.col_map[i].render(my) : eval( g.col_map[i].render ) ) );
                    } catch(E) {
                        g.error.sdump('D_ERROR','spine_labels.js, expand_macros() = ' + E);
                    }
                }
            }
            return text;
        }

        function preview(idx) {
            try {
                    var pt = Number( $('pt').value );  /* font size */
                    if (!pt) {
                        pt = g.data.hash.aous['cat.label.font.size'] || 10;
                        $('pt').value = pt;
                    }
                    var ff = g.data.hash.aous['cat.label.font.family'] || 'monospace';
                    var fw = $('font_weight').value;  /* font weight */
                    if (!fw) {
                        fw = g.data.hash.aous['cat.label.font.weight'] || 'normal';
                    }
                    var lm = Number($('lm').value); /* left margin */
                    if (!lm) {
                        lm = g.data.hash.aous['cat.spine.line.margin'] || 0;
                    }
                    var mm = Number($('mm').value); if (isNaN(mm)) mm = 2; /* middle margin */
                    var lw = Number($('lw').value); /* spine label width */
                    if (!lw) {
                        lw = g.data.hash.aous['cat.spine.line.width'] || 8;
                        $('lw').value = lw;
                    }
                    var ll = Number($('ll').value); /* spine label length */
                    if (!ll) {
                        ll = g.data.hash.aous['cat.spine.line.height'] || 9;
                        $('ll').value = ll;
                    }
                    var plw = Number($('plw').value) || 28; var pll = Number($('pll').value) || 9; /* pocket label width and length */
                    var html = "<html><head>";
                    html += "<link type='text/css' rel='stylesheet' href='" + xulG.url_prefix('/xul/server/skin/print.css') + "'></link>"
                    html += "<link type='text/css' rel='stylesheet' href='data:text/css,pre{font-family:" + ff + ";font-size:" + pt + "pt; font-weight: " + fw + ";}'></link>";
                    html += "<title>Spine Labels</title></head><body>\n";
                    var nl = document.getElementsByAttribute('name','template');
                    for (var i = 0; i < nl.length; i++) {
                        if (typeof idx == 'undefined' || idx == null) { } else {
                            if (idx != i) continue;
                        }
                        var volume = g.volumes[ nl[i].getAttribute('acn_id') ];

                        for (var j = 0; j < volume.copies().length; j++) {
                            var copy = volume.copies()[j];
                            if (i == 0 && j == 0) {
                                html += '<pre class="first_pre">\n';
                            } else {
                                html += '<pre class="not_first_pre">\n';
                            }
                            var gb = nl[i].getElementsByTagName('groupbox')[0];
                            var nl2 = gb.getElementsByAttribute('name','spine');
                            for (var k = 0; k < nl2.length; k++) {
                                for (var m = 0; m < lm; m++) html += ' ';
                                html += util.text.preserve_string_in_html(expand_macros( nl2[k].value, copy, volume, volume.record() ).substr(0,lw));
                                if ($('pl').checked) {
                                    var sib = nl2[k].nextSibling;
                                    if (sib) {
                                        for (var m = 0; m < lw - nl2[k].value.length; m++) html += ' ';
                                        for (var m = 0; m < mm; m++) html += ' ';
                                        html += util.text.preserve_string_in_html(expand_macros( sib.value, copy, volume, volume.record() ).substr(0,plw));
                                    }
                                }
                                html += '\n';
                            }
                            html += '</pre hex="0C">\n';
                        }
                    }
                    html += '</body></html>';

                    /* From https://developer.mozilla.org/en/Using_nsIXULAppInfo */
                    var appInfo = Components.classes["@mozilla.org/xre/app-info;1"]
                                            .getService(Components.interfaces.nsIXULAppInfo);
                    var platformVer = appInfo.platformVersion;

                    /* We need to use different print strategies for different
                     * XUL versions, apparently
                     */
                    if (platformVer.substr(0, 5) == '1.9.0') {
                        preview_xul_190(html);
                    } else {
                        preview_xul_192(html);
                    }


            } catch(E) {
                g.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.spine_labels.preview.std_unexpected_err'),E);
            }
        }

        function preview_xul_190(html) {
            JSAN.use('util.window'); var win = new util.window();
            var loc = ( urls.XUL_REMOTE_BROWSER );
            //+ '?url=' + window.escape('about:blank') + '&show_print_button=1&alternate_print=1&no_xulG=1&title=' + window.escape('Spine Labels');
            var w = win.open( loc, 'spine_preview', 'chrome,resizable,width=750,height=550');
            w.xulG = { 
                'url' : 'about:blank',
                'url_prefix' : function (u,s) { return xulG.url_prefix(u,s); },
                'show_print_button' : 1,
                'printer_context' : 'label',
                'alternate_print' : 1,
                'no_xulG' : 1,
                'title' : $("catStrings").getString('staff.cat.spine_labels.preview.title'),
                'on_url_load' : function(b) { 
                    try { 
                        if (typeof w.xulG.written == 'undefined') {
                            w.xulG.written = true;
                            w.g.browser.get_content().document.write(html);
                            w.g.browser.get_content().document.close();
                        }
                    } catch(E) {
                        alert(E);
                    }
                }
            };
        }

        function preview_xul_192(html) {
            var loc = ( urls.XUL_BROWSER );
            xulG.new_tab(
                loc,
                {
                    'tab_name' : $("catStrings").getString('staff.cat.spine_labels.preview.title')
                },
                { 
                    'url' : 'data:text/html;charset=utf-8,' + encodeURIComponent(html),
                    'html_source' : html,
                    'show_print_button' : 1,
                    'printer_context' : 'label',
                    'no_xulG' : 1
                }
            );
        }
