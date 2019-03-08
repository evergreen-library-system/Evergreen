var FM_TABLE_DISPLAY = {
	'acp' : {
		name : 'barcode',	
		fields : [
			'barcode',
			'call_number',
			'circ_modifier',
			'create_date',
			'edit_date',
			'fine_level',
			'holdable',
			'loan_duration',
			'location',
			'notes',
			'stat_cat_entry_copy_maps',
			'status' ],
		},
	'acpn' : {
		name : 'title',
		fields : [
			'pub',
			'title',
			'value'
		]
	},
	'asc' : {
		name : 'name',
		fields : [
			'owner',
			'opac_visible',
			'name'
		]
	},
	'ascecm' : {
		fields : [ 'stat_cat', 'stat_cat_entry' ]
	},
	'ccs' : {
		name : 'name'
	},
	'acpl' : {
		name : 'name',
		fields : [
			'circulate',
			'holdable',
			'owning_lib',
			'opac_visible'
		]
	},
	'au' : {
		name : 'usrname',
		fields : [
			'card',
			'email',
			'first_given_name',
			'family_name',
			'home_ou',
		]
	},
	'aws' : {
		name : 'name'
	},
	'mwps' : {
		fields : [
			'workstation',
			'cash_payment',
			'check_payment',	
			'credit_card_payment',
			'debit_card_payment'
		],
		money : [
			'cash_payment',
			'check_payment',	
			'credit_card_payment',
			'debit_card_payment'
		]
	},

	'mups' : {
		fields : [
			'usr',
			'credit_payment',
			'forgive_payment',
			'work_payment',
			'goods_payment'
		],
		money : [
			'credit_payment',
			'forgive_payment',
			'work_payment',
			'goods_payment'
		]
	},
	'rr' : {
		name : 'name',
		fields : [
			'name',
			'description',
			'template',
			'create_time',
			'recur',
			'recurrence',
			'owner',
            'edit',
		],
		sortdata : [ 'name', 1 ],
        calculate : {
            'edit' : function(r) {
                // DOM pulled from oils_rpt_folder_window.xhtml
                var node = dojo.byId(
                    'oils_rpt_view_edit_report_links').cloneNode(true);
                dojo.removeClass(node, 'hide_me');
                var view = dojo.query('[name=view]', node)[0];
                var edit = dojo.query('[name=edit]', node)[0];
                view.onclick = function() {oilsRptViewReport(r); return false};
                if (PERMS.RUN_REPORTS == -1) {
                    node.removeChild(edit);
                } else {
                    edit.onclick = function() {oilsRptEditReport(r); return false};
                }
                return node;
            }
        }
	},
	'rt' : {
		name : 'name',
		fields : [
			'name',
			'description',
            'docs',
            'ui',
			'create_time',
			'owner',
		],
        calculate : {
            docs : function (t) {
                var d = JSON2js(t.data());
                if (d.version >= 4 && d.doc_url) {
                    var args = {};
                    args.href = d.doc_url;
                    args.target='_blank';
                    return elem('a', args, 'External Documentation')
                }
                return text('');
            },
            ui : function (t) {
                var d = JSON2js(t.data());
                if (d.version >= 5) {
                    return text('WebStaff');
                }
                return text('XUL');
            }
        },
		sortdata : [ 'name', 1 ]
	},
	'rs' : {
		fields : [
			'report',
			'run_time',
			'complete_time',
			'runner',
			'email',
			'folder',
			'error_text',
			'excel_format',
			'html_format',
			'csv_format',
		],
		bold : [
			'error_text',
		],
		sortdata : [ 'run_time', -1 ]
	}
}
