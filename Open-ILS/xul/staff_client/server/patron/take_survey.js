var cgi;
var orgTree;
var responses = {};
var survey_user;


function save_responses (root) {

	try {

		var res = [];
		for (var i in responses) {
			if (!i) continue;
			for (var j in responses[i]) {
				if (!j) continue;
				var r = new asvr();
				r.usr(survey_user);
				r.survey(i);
				r.question(j);
				r.answer(responses[i][j]);
				r.answer_date( findNodeByName(root,'effective_date').value );
				res.push(r);
			}
		}

		responses = {};

		var meth = 'open-ils.circ.survey.submit.anon';
		if (survey_user) meth = 'open-ils.circ.survey.submit.user_id';

		var req = new RemoteRequest( 'open-ils.circ', meth, res );
		req.send(true);
		var ok = req.getResultObject();

		if (ok) {
			alert('Survey response successfully saved!');
		}

	} catch (e) {
		alert(e)
	};

	return false;
}

function init_survey (root, s_id, usr_id) {
	
	var x = findNodeByName(root,'editor');

	survey_user = usr_id;

	cgi = new CGI();
	var adv = cgi.param('adv');

	if (!s_id) {
		alert('No survey id passed in!');
		return false;
	}

	if (findNodeByName(root,'save_response')) {
		findNodeByName(root,'save_response')
			.setAttribute(
				'onclick',
				"save_responses(document.getElementById('" + root.id + "')); return false;"
			);
	}

	var today = new Date()
	var month = today.getMonth() + 1
	var day = today.getDate()
	var year = today.getFullYear()
	var s = "-"
	if (findNodeByName(root,'effective_date')) {
		findNodeByName(root,'effective_date').value = '%04d%s%02d%s%02d'.sprintf(year,s,month,s,day);
		findNodeByName(root,'effective_date').id = 'e_date_' + s_id;
	}


	if (adv) {
		findNodeByName(root,'effective_date').parentNode.parentNode.setAttribute('adv','false');
	}

	var req = new RemoteRequest( 'open-ils.circ', 'open-ils.circ.survey.fleshed.retrieve', s_id );
	req.send(true);
	sur = req.getResultObject();



	if (findNodeByName(x,'sur.name'))
		findNodeByName(x,'sur.name').appendChild( text( sur.name() ) );

	if (findNodeByName(x,'sur.description'))
		findNodeByName(x,'sur.description').appendChild( text( sur.description() ) );

	if (findNodeByName(x,'sur.start_date'))
		findNodeByName(x,'sur.start_date').appendChild( text( sur.start_date() ) );

	if (findNodeByName(x,'sur.end_date'))
		findNodeByName(x,'sur.end_date').appendChild( text( sur.end_date() ) );

	q_tmpl = findNodeByName(root,'question-tmpl').getElementsByTagName('table')[0];

	x = findNodeByName(x,'questions');
	for (var i in sur.questions()) {
		var q = sur.questions()[i];
		var new_q = q_tmpl.cloneNode(true);
		x.appendChild(new_q);

		findNodeByName(new_q,'q.question').appendChild( text( q.question() ) );

		var sel = findNodeByName(new_q,'answers-sel');
		sel.options[0] = new Option('-- Select one --');

		var rad = findNodeByName(new_q,'answers-rad');

		if (!sur.poll()) {
			sel.className = '';
			for (var j in q.answers()) {
				var a = q.answers()[j];
				var opt = new Option(a.answer());

				opt.setAttribute('answer', a.id());
				opt.setAttribute('question', q.id());
				opt.setAttribute('survey', sur.id());

				sel.options[sel.options.length] = opt;
			}
		} else {
			rad.parentNode.className = 'rad-value';
			for (var j in q.answers()) {
				var a = q.answers()[j];

				var opt = rad.cloneNode(true);
				opt.className = '';

				opt.firstChild.setAttribute('name','res_' + i );
				opt.firstChild.setAttribute('answer', a.id());
				opt.firstChild.setAttribute('question', q.id());
				opt.firstChild.setAttribute('survey', sur.id());

				opt.appendChild(text(a.answer()));
				rad.parentNode.appendChild(opt);
			}
		}
	}

	return true;
}

function update_response (sel) {
	var opt = sel.options[sel.selectedIndex];
	if (!responses[opt.getAttribute('survey')])
		responses[opt.getAttribute('survey')] = {};

	responses[opt.getAttribute('survey')][opt.getAttribute('question')] = opt.getAttribute('answer');
}
function update_response_rad (opt) {
	if (!responses[opt.getAttribute('survey')])
		responses[opt.getAttribute('survey')] = {};

	responses[opt.getAttribute('survey')][opt.getAttribute('question')] = opt.getAttribute('answer');
}

