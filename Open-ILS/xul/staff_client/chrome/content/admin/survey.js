dump('Loading survey.js\n');

var SURVEY = {};
var last_answer;
var last_button;

function populate_lib_list_with_branch(menulist,menupopup,defaultlib,branch,id_flag) {
	JSAN.use('util.fm_utils');
	var default_menuitem;
	if (typeof defaultlib == 'object') {
		defaultlib = defaultlib.id();	
	}
	var popup = menupopup;
	if (typeof(popup)!='object') popup = document.getElementById(menupopup);
	if (popup) {
		//empty_widget(popup);
		var padding_flag = true;
		var flat_branch = util.fm_utils.flatten_ou_branch( branch );
		for (var i in flat_branch) {
			var menuitem = document.createElement('menuitem');
			var padding = '';
			var depth = g.OpenILS.data.hash.aout[ flat_branch[i].ou_type() ].depth();
			if (padding_flag) {
				for (var j = 0; j < depth; j++) { 
					padding = padding + '  '; 
				}
			}
			menuitem.setAttribute('label', padding + flat_branch[i].name() );
			menuitem.setAttribute('value', flat_branch[i].id() );
			if (id_flag) menuitem.setAttribute('id', 'libitem' + flat_branch[i].id() );
			if (defaultlib == flat_branch[i].id()) {
				default_menuitem = menuitem;
			}
			popup.appendChild(menuitem);
		}
		var list = menulist;
		if (typeof(list)!='object') { list = document.getElementById(menulist); }
		if (list && defaultlib && default_menuitem) {
			if (list) { list.selectedItem = default_menuitem; }
		}
	} else {
			var err = ('populate_lib_list_with_branch: Could not find ' + menupopup + '\n');
			dump(err);
			alert(err);
	}
}


function survey_init() {
	dump('survey_init()\n');
	var user_ou = g.OpenILS.data.list.au[0].home_ou();
	var user_branch = g.OpenILS.data.hash.aou[ user_ou ];
	populate_lib_list_with_branch('lib_menulist','lib_menupopup',user_ou,user_branch); 
	SURVEY['asv'] = new asv(); SURVEY['asv'].isnew('1');
	SURVEY['num_of_questions'] = 0;
	document.getElementById('survey_name').focus();
}

function save_survey() {
	SURVEY.asv.description(
		document.getElementById('survey_description').value
	);
	SURVEY.asv.name(
		document.getElementById('survey_name').value
	);
	SURVEY.asv.owner(
		document.getElementById('lib_menulist').value
	);
	var survey_start = document.getElementById('survey_start').value;
	if (survey_start) {
		SURVEY.asv.start_date(
			survey_start
		);
	} else {
		SURVEY.asv.start_date(
			null
		);
	}
	var survey_end = document.getElementById('survey_end').value;
	if (survey_end) {
		SURVEY.asv.end_date(
			survey_end
		);
	} else {
		SURVEY.asv.end_date(
			null
		);
	}
	if ( document.getElementById('required_checkbox').checked ) {
		SURVEY.asv.required('1');
	} else {
		SURVEY.asv.required('0');
	}
	if ( document.getElementById('opac_checkbox').checked ) {
		SURVEY.asv.opac('1');
	} else {
		SURVEY.asv.opac('0');
	}
	if ( document.getElementById('poll_checkbox').checked ) {
		SURVEY.asv.poll('1');
	} else {
		SURVEY.asv.poll('0');
	}

	if ( document.getElementById('patron_summary_checkbox').checked ) {
		SURVEY.asv.usr_summary('1');
	} else {
		SURVEY.asv.usr_summary('0');
	}
	g.error.sdump('D_SURVEY', 'before survey = ' + js2JSON( SURVEY.asv ) + '\n');
	try {
		var result = g.network.request(
			api.FM_ASV_CREATE.app,
			api.FM_ASV_CREATE.method,
			[ ses(), SURVEY.asv ]
		);
		if (! (result instanceof asv) ) {
			throw('save_survey: result not an asv');
		} else {
			var surveys_list = g.OpenILS.data.list.asv;
			var surveys_hash = g.OpenILS.data.hash.asv;
			surveys_list.push( result );
			surveys_hash[ result.id() ] = result;
			g.OpenILS.data.stash('list','hash');
		}
	} catch(E) {
		var err = ('Survey failed: ' + js2JSON(E) + '\n');
		g.error.sdump('D_ERROR',err);
		alert(err);
		throw(err);
	}
	g.error.sdump('D_SURVEY', 'after  survey = ' + js2JSON( SURVEY.asv ) + '\n');
}

var original_description;
function setDescription(e,t) {
	var page = document.getElementById(e);
	var desc = page.getAttribute('description');
	if (!original_description) original_description = desc;
	var value = document.getElementById(t).value;
	page.setAttribute('description',original_description + ' ' + value); 
}

var new_id = -1;
function add_answer(e, my_asvq_id) {
	var row = e.target.parentNode;
	var rows = row.parentNode;
	var answer = e.target.previousSibling; answer.select();

	if (! answer.value ) { return; }
	
	/* XUL */
	var n_row = document.createElement('row');
	rows.insertBefore( n_row, row );
	var label_1 = document.createElement('label');
	n_row.appendChild( label_1 );
	var label_2 = document.createElement('label');
		label_2.setAttribute('value', answer.value );
	n_row.appendChild( label_2 );

	/* OBJECT */

	var my_asva = new asva(); my_asva.isnew('1'); my_asva.id( new_id-- );
	my_asva.answer( answer.value );

	JSAN.use('util.functional');
	var my_asvq = util.functional.find_id_object_in_list( SURVEY.asv.questions(), my_asvq_id );
	if (my_asvq.answers() == null) {
		my_asvq.answers( [] );
	}

	my_asvq.answers().push( my_asva );

	var num_of_answers = my_asvq.answers().length;
	var last_number = 96 + num_of_answers;
	var next_number = 97 + num_of_answers;
	var last_letter = String.fromCharCode( last_number );
	var next_letter = String.fromCharCode( next_number );
	label_1.setAttribute('value', last_letter + ')' );
	row.firstChild.setAttribute('value', next_letter + ')' );

	if (num_of_answers == 26) {
		rows.removeChild(row);
	}
}

function add_question() {
	SURVEY.num_of_questions++;
	var question = document.getElementById('new_question');

	if (! question.value ) { return; }

	document.getElementById('survey_add').canAdvance = true;

	var my_asvq = new asvq(); my_asvq.isnew('1'); my_asvq.id( new_id-- );
	my_asvq.question( question.value );

	if ( SURVEY.asv.questions() == null ) {
		SURVEY.asv.questions( [] );
	}

	SURVEY.asv.questions().push( my_asvq );

	add_question_row(my_asvq);

	document.getElementById('new_question_label').setAttribute('value', '#' + (SURVEY.num_of_questions + 1) );
	//question.select();
	if (last_answer) last_answer.focus();
}

function add_question_row(my_asvq) {
	var rows = document.getElementById('page2_grid1_rows');
	var row = document.createElement('row');
	rows.insertBefore(row, document.getElementById('page2_grid1_row1'));

	var label_number = document.createElement('label');
		label_number.setAttribute('value','#' + SURVEY['num_of_questions']);
	row.appendChild(label_number);

	var grid = document.createElement('grid');
	row.appendChild(grid);
	var g_cols = document.createElement('columns');
	grid.appendChild(g_cols);
	var g_col_1 = document.createElement('column');
	g_cols.appendChild(g_col_1);
	var g_col_2 = document.createElement('column');
		g_col_2.setAttribute('flex','1');
	g_cols.appendChild(g_col_2);
	var g_col_3 = document.createElement('column');
	g_cols.appendChild(g_col_3);
	var g_rows = document.createElement('rows');
	grid.appendChild(g_rows);
	var g_row_1 = document.createElement('row');
	g_rows.appendChild(g_row_1);
	var g_label_1 = document.createElement('label');
	g_row_1.appendChild(g_label_1);
	var g_label_2 = document.createElement('label');
		g_label_2.setAttribute('value', my_asvq.question() );
	g_row_1.appendChild(g_label_2);
	var g_row_2 = document.createElement('row');
	g_rows.appendChild(g_row_2);
	var g_label2_1 = document.createElement('label');
		g_label2_1.setAttribute('value', 'a)' );
	g_row_2.appendChild(g_label2_1);
	var g_tb = document.createElement('textbox');
		g_tb.setAttribute('flex','1');
	g_row_2.appendChild(g_tb);
	if (last_button) last_button.setAttribute('accesskey','');
	var g_b = document.createElement('button');
		g_b.setAttribute('label','Save this Response');
		g_b.setAttribute('accesskey','R');
		g_b.setAttribute('oncommand','add_answer(event,' + my_asvq.id() + ');');
	g_row_2.appendChild(g_b);

	var blank = document.createElement('row');
	rows.insertBefore( blank , document.getElementById('page2_grid1_row1') );
	var blank2 = document.createElement('label');
		blank2.setAttribute('value', ' ');
	blank.appendChild( blank2 );

	last_answer = g_tb;
	last_button = g_b;
}

function page1_check_advance() {
	if ( document.getElementById('survey_name').value ) {
		document.getElementById('survey_add').canAdvance = true;
	} else {
		document.getElementById('survey_add').canAdvance = false;
	}
}

