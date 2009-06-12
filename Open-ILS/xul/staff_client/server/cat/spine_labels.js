		function my_init() {
			try {
				netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
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
					if (!g.volumes[ copy.call_number() ]) {
						var volume = g.network.simple_request( 'FM_ACN_RETRIEVE.authoritative', [ copy.call_number() ] );
						if (typeof volume.ilsevent != 'undefined') throw(volume);
						var record = g.network.simple_request('MODS_SLIM_RECORD_RETRIEVE.authoritative', [ volume.record() ]);
						volume.record( record );
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

		function $(id) { return document.getElementById(id); }

		function generate() {
			try {
				var idx = 0;
				JSAN.use('util.text'); JSAN.use('util.money');
				JSAN.use('util.widgets'); util.widgets.remove_children('panel'); var pn = $('panel'); $('preview').disabled = false;
				var lw = Number($('lw').value) || 8; /* spine label width */
				var ll = Number($('ll').value) || 9; /* spine label length */
				var plw = Number($('plw').value) || 28; /* pocket label width */
				var pll = Number($('pll').value) || 9; /* pocket label length */
				for (var i in g.volumes) {
					var vb = document.createElement('vbox'); pn.appendChild(vb); vb.setAttribute('name','template'); vb.setAttribute('acn_id',g.volumes[i].id());
					var ds = document.createElement('description'); vb.appendChild(ds);
					ds.appendChild( document.createTextNode( g.volumes[i].label() ) );
					var ds2 = document.createElement('description'); vb.appendChild(ds2);
					ds2.appendChild( document.createTextNode( g.volumes[i].copies().length + (
						g.volumes[i].copies().length == 1 ? $("catStrings").getString('staff.cat.spine_labels.copy') : $("catStrings").getString('staff.cat.spine_labels.copies')) ) );
					ds2.setAttribute('style','color: green');
					var hb = document.createElement('hbox'); vb.appendChild(hb);

					var gb = document.createElement('groupbox'); hb.appendChild(gb); 
					/* take the call number and split it on whitespace */
					var names = String(g.volumes[i].label()).split(/\s+/);
					var j = 0;
					while (j < ll || j < pll) {
						var hb2 = document.createElement('hbox'); gb.appendChild(hb2);
						
						/* spine */
						if (j < ll) {
							var tb = document.createElement('textbox'); hb2.appendChild(tb); 
							tb.value = '';
							tb.setAttribute('class','plain'); tb.setAttribute('style','font-family: monospace');
							tb.setAttribute('size',lw+1); tb.setAttribute('maxlength',lw);
							tb.setAttribute('name','spine');
							var name = names.shift(); if (name) {
								name = String( name );
								/* if the name is greater than the label width... */
								if (name.length > lw) {
									/* then try to split it on periods */
									var sname = name.split(/\./);
									if (sname.length > 1) {
										/* if we can, then put the periods back in on each splitted element */
										if (name.match(/^\./)) sname[0] = '.' + sname[0];
										for (var k = 1; k < sname.length; k++) sname[k] = '.' + sname[k];
										/* and put all but the first one back into the names array */
										names = sname.slice(1).concat( names );
										/* if the name fragment is still greater than the label width... */
										if (sname[0].length > lw) {
											/* then just truncate and throw the rest back into the names array */
											tb.value = sname[0].substr(0,lw);
											names = [ sname[0].substr(lw) ].concat( names );
										} else {
											/* otherwise we're set */
											tb.value = sname[0];
										}
									} else {
										/* if we can't split on periods, then just truncate and throw the rest back into the names array */
										tb.value = name.substr(0,lw);
										names = [ name.substr(lw) ].concat( names );
									}
								} else {
									/* otherwise we're set */
									tb.value = name;
								}
							}
						}

						/* pocket */
						if ($('pl').checked && j < pll) {
							var tb2 = document.createElement('textbox'); hb2.appendChild(tb2); 
							tb2.value = '';
							tb2.setAttribute('class','plain'); tb2.setAttribute('style','font-family: monospace');
							tb2.setAttribute('size',plw+1); tb2.setAttribute('maxlength',plw);
							tb2.setAttribute('name','pocket');
							if ($('title').checked && $('title_line').value == j + 1 && instanceOf(g.volumes[i].record(),mvr)) {
								if (g.volumes[i].record().title()) {
									tb2.value = util.text.wrap_on_space( g.volumes[i].record().title(), plw )[0];
								} else {
									tb2.value = '';
								}
							}
							if ($('title_r').checked && $('title_r_line').value == j + 1 && instanceOf(g.volumes[i].record(),mvr)) {
								if (g.volumes[i].record().title()) {
									tb2.value = ( ($('title_r_indent').checked ? ' ' : '') + util.text.wrap_on_space( g.volumes[i].record().title(), plw )[1]).substr(0,plw);
								} else {
									tb2.value = '';
								}
							}
							if ($('author').checked && $('author_line').value == j + 1 && instanceOf(g.volumes[i].record(),mvr)) {
								if (g.volumes[i].record().author()) {
									tb2.value = g.volumes[i].record().author().substr(0,plw);
								} else {
									tb2.value = '';
								}
							}
							if ($('call_number').checked && $('call_number_line').value == j + 1) {
								tb2.value = g.volumes[i].label().substr(0,plw);
							}
							if ($('owning_lib_shortname').checked && $('owning_lib_shortname_line').value == j + 1) {
								var lib = g.volumes[i].owning_lib();
								if (!instanceOf(lib,aou)) lib = g.data.hash.aou[ lib ];
								tb2.value = lib.shortname().substr(0,plw);
							}
							if ($('owning_lib').checked && $('owning_lib_line').value == j + 1) {
								var lib = g.volumes[i].owning_lib();
								if (!instanceOf(lib,aou)) lib = g.data.hash.aou[ lib ];
								tb2.value = lib.name().substr(0,plw);
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

					idx++;
				}
			} catch(E) {
				g.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.spine_labels.generate.std_unexpeceted_err'),E);
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
					netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
					var pt = Number( $('pt').value ) || 10;  /* font size */
					var lm = Number($('lm').value); if (lm == NaN) lm = 11; /* left margin */
					var mm = Number($('mm').value); if (mm == NaN) mm = 2; /* middle margin */
					var lw = Number($('lw').value) || 8; var ll = Number($('ll').value) || 9; /* spine label width and length */
					var plw = Number($('plw').value) || 28; var pll = Number($('pll').value) || 9; /* pocket label width and length */
					var html = "<html><head>";
                    html += "<link type='text/css' rel='stylesheet' href='/xul/server/skin/print.css'></link>"
                    html += "<link type='text/css' rel='stylesheet' href='data:text/css,pre{font-size:" + pt + "pt;}'></link>";
                    html += "<title>Spine Labels</title></head><body>\n";
					var nl = document.getElementsByAttribute('name','template');
					for (var i = 0; i < nl.length; i++) {
						if (typeof idx == 'undefined' || idx == null) { } else {
							if (idx != i) continue;
						}
						var volume = g.volumes[ nl[i].getAttribute('acn_id') ];

						for (var j = 0; j < volume.copies().length; j++) {
							var copy = volume.copies()[j];
                            if (i == 0) {
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
							html += '</pre>\n';
						}
					}
					html += '</body></html>';
					JSAN.use('util.window'); var win = new util.window();
					var loc = ( urls.XUL_REMOTE_BROWSER );
					//+ '?url=' + window.escape('about:blank') + '&show_print_button=1&alternate_print=1&no_xulG=1&title=' + window.escape('Spine Labels');
					var w = win.open( loc, 'spine_preview', 'chrome,resizable,width=750,height=550');
					w.xulG = { 
						'url' : 'about:blank',
						'show_print_button' : 1,
						'alternate_print' : 1,
						'no_xulG' : 1,
						'title' : $("catStrings").getString('staff.cat.spine_labels.preview.title'),
						'on_url_load' : function(b) { 
							try { 
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
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
			} catch(E) {
				g.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.spine_labels.preview.std_unexpected_err'),E);
			}
		}


