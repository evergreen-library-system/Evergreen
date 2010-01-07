dump('Loading survey.js\n');

var SURVEY = {};
var last_answer;
var last_button;

function render_lib_menu() {
    try {
        JSAN.use('util.functional'); JSAN.use('util.fm_utils'); JSAN.use('util.widgets');

        var work_ous = g.network.simple_request(
            'PERM_RETRIEVE_WORK_OU',
            [ ses(), 'CREATE_SURVEY']
        );
        if (work_ous.length == 0) {
            alert(document.getElementById('offlineStrings').getString('menu.cmd_survey_wizard.inadequate_perm'));
            window.close();
            return;
        }
        var my_libs = [];
        for (var i = 0; i < work_ous.length; i++ ) {
            var perm_depth = g.OpenILS.data.hash.aout[ g.OpenILS.data.hash.aou[ work_ous[i] ].ou_type() ].depth();

            var my_libs_tree = g.network.simple_request(
                'FM_AOU_DESCENDANTS_RETRIEVE',
                [ work_ous[i], perm_depth ]
            );
            if (!instanceOf(my_libs_tree,aou)) { /* FIXME - workaround for weird descendants call result */
                my_libs_tree = my_libs_tree[0];
            }
            my_libs = my_libs.concat( util.fm_utils.flatten_ou_branch( my_libs_tree ) );
        }

        var x = document.getElementById('placeholder');
        util.widgets.remove_children( x );

        var default_lib = my_libs[0].id(); 

        var ml = util.widgets.make_menulist( 
            util.functional.map_list( 
                my_libs,
                function(obj) { 
                    return [ 
                        obj.shortname(), 
                        obj.id(), 
                        false,
                        ( g.OpenILS.data.hash.aout[ obj.ou_type() ].depth() )
                    ]; 
                }
            ),
            default_lib
        );
        ml.setAttribute('id','lib_menulist');

        x.appendChild( ml );
    } catch(E) {
        alert('Error in survey.js, render_lib_menu(): ' + E);
    }
}


function survey_init() {
	dump('survey_init()\n');
	render_lib_menu();
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
	var strbundle = document.getElementById("offlineStrings");
	g_b.setAttribute('label', strbundle.getString('staff.admin.survey.save_response.label'));
	g_b.setAttribute('accesskey', strbundle.getString('staff.admin.survey.save_response.label'));
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

