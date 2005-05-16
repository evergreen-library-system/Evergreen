/* */


function SurveyQuestion(question, poll) {
	debug("Creating new survey question " + question.question() );
	this.question = question;
	this.node = createAppElement("div");
	this.node.id	= "survey_question_" + question.id();
	add_css_class( this.node, "survey_question" );
	var div = createAppElement("div");
	add_css_class(div, "survey_question_question");
	div.appendChild(	
		createAppTextNode(question.question()));
	this.node.appendChild(div);

	if(poll) {
		this.selector = createAppElement("div");
	} else {
		this.selector = createAppElement("select");
	}

	add_css_class( this.selector, "survey_answer_selector" );
	this.selector.name = "survey_question_" + question.id();
	this.selector.value = "survey_question_" + question.id();
	this.node.appendChild(this.selector);
	this.answers = new Array();
}


SurveyQuestion.prototype.getNode = function() {
	return this.node;
}

SurveyQuestion.prototype.addAnswer = function(answer,poll) {
	if(poll) {
		var ans = new SurveyAnswer(answer, this.question.id(), poll);
		this.answers.push(ans);

		this.selector.appendChild(ans.getNode());
		this.selector.appendChild(createAppTextNode(answer.answer()));
		this.selector.appendChild(createAppElement("br"));

	} else {
		var ans = new SurveyAnswer(answer, this.question.id());
		this.answers.push(ans);
		this.selector.options[ this.selector.options.length ] = ans.getNode();
	}
}


function SurveyAnswer(answer,qid, poll) {
	this.answer = answer;

	if(poll) {

		if(IE) {
			this.node = createAppElement(
				"<input name='survey_answer_" + qid + "' type='radio' value='" + answer.id() + "'></input>" );
		} else {

			this.node = createAppElement("input");
			this.node.setAttribute("type", "radio");
			this.node.setAttribute("name", "survey_answer_" + qid);
			this.node.setAttribute("value", answer.id());
		}

	} else {
		this.node = new Option( answer.answer(), answer.id() );
	}

	add_css_class( this.node, "survey_answer" );
}

SurveyAnswer.prototype.getNode = function() {
	return this.node;
}




Survey.prototype					= new ListBox();
Survey.prototype.constructor	= Survey;
Survey.baseClass					= ListBox.constructor;

function Survey(survey, onclick) {

	this.survey = survey;
	debug("Creating new survey " + survey.name() );

	if( survey.poll() == 0 ) survey.poll(false);
	if( survey.poll() == 1 ) survey.poll(true);

	if( survey.poll() )
		this.listBoxInit( false, survey.name(), true, false );
	else
		this.listBoxInit( true, survey.name(), true, false );


	this.questions			= new Array();

	this.addCaption( survey.description() );

	for( var i in survey.questions() ) {
		this.addQuestion( survey.questions()[i] );
	}

	
	this.button = createAppElement("input");
	this.button.setAttribute("type", "submit");
	this.button.value = "Submit Survey";

	if(onclick)
		this.button.onclick = onclick;
	this.addFooter(this.button);

	var obj = this;
	this.setAction( function() { obj.submit(); });
}

Survey.prototype.setUserSession = function(userSession) {
	this.userSession = userSession;
}

Survey.prototype.setAnswerDate = function(date) {
	this.answerDate = date;
}

Survey.prototype.setEffectiveDate = function(date) {
	this.effectiveDate = date;
}

Survey.prototype.setAction = function(onclick) {
	this.button.onclick = onclick;
}

Survey.prototype.getName = function() {
	debug("getting name for " + this.survey.name() ); 
	return this.survey.name();
}

Survey.prototype.addQuestion = function(question) {
	var questionObj = new SurveyQuestion(question, this.survey.poll());
	this.questions.push(questionObj);
	for( var i in question.answers() ) {
		questionObj.addAnswer(question.answers()[i], this.survey.poll());
	}

	this.addItem(questionObj.getNode());
}

Survey.prototype.setUser = function(userid) {
	this.userId = userid;
}

Survey.prototype.setSubmitCallback = function(callback) {
	this.submitCallback = callback;
}

Survey.prototype.submit = function() {

	var responses = this.buildSurveyResponse();

	if( this.commitCallback) {
		this.commitCallback(responses);

	} else {
		this.commit(responses);
	}
	
	var bool = true;
	if( this.submitCallback )
		bool = this.submitCallback(this);
	
	this.removeFooter();

}

Survey.prototype.commit = function(responses) {
	var method;
	if( this.userId ) 
		method = "open-ils.circ.survey.submit.user_id";
	else {
		if( this.userSession )
			method = "open-ils.circ.survey.submit.session";
		else 
			method = "open-ils.circ.survey.submit.anon";
	}

	var request = new RemoteRequest(
		"open-ils.circ", method, responses );
	request.send(true);

	/* there is nothing to return, just check for exceptions */
	request.getResultObject();
}


Survey.prototype.buildSurveyResponse = function() {

	var responses = new Array();

	for( var index in this.questions ) {
		var que	= this.questions[index];
		var ans = null;	 
		for( var ansindex in que.answers ) {
			ansobj = que.answers[ansindex];
			if( ansobj.getNode().selected || ansobj.getNode().checked ) {
				ans = ansobj.answer.id();
				debug("User selected answer " + ans );
				break;
			}
		}
		var qid = que.question.id()
		var sur = new asvr();
		if( this.userId )
			sur.usr(this.userId);
		else
			sur.usr(this.userSession);
		sur.survey(this.survey.id());
		sur.question(qid);
		sur.answer(ans);
		sur.answer_date(this.answerDate);
		sur.effective_date(this.effectiveDate);
		responses.push(sur);
	}

	return responses;
}

/* Global survey retrieval functions.  In each case, if recvCallback
	is not null, the retrieval will be asynchronous and will
	call recvCallback(survey) on each survey retrieved.  Otherwise
	an array of surveys is returned.
	*/

Survey._retrieve = function(request, surveyTaker, recvCallback) {


	if( recvCallback ) {

		debug("Retrieving random survey asynchronously");
		var c = function(req) {
			var surveys = req.getResultObject();
			if(!surveys) return null;

			if( typeof surveys != 'object' || 
					surveys.constructor != Array )
				surveys = [surveys];

			for( var i in surveys ) {
				var s = surveys[i];
				debug("Retrieved survey " + s.name() );
				var surv = new Survey(s);
				surv.setUserSession(surveyTaker);
				recvCallback(surv);
			}
		}

		request.setCompleteCallback(c);
		request.send();

	} else {

		request.send(true);
		var surveys = new Array();
		var results = request.getResultObject();
		for(var index in results) {
			var s = results[index];
			debug("Retrieved survey " + s.name());
			var surv = new Survey(s);
			surv.setUserSession(surveyTaker);
			surveys.push(surv);
		}
		return surveys;
	}

}

/* this needs a different method for retrieving the correct survey */
Survey.retrieveOpacRandom = function(user_session, recvCallback) {

	var request = new RemoteRequest( 
		"open-ils.circ", 
		"open-ils.circ.survey.retrieve.opac.random", 
		user_session );
	return Survey._retrieve(request, user_session, recvCallback );
}


Survey.retrieveAll = function(user_session, recvCallback) {
	var request = new RemoteRequest( 
		"open-ils.circ", 
		"open-ils.circ.survey.retrieve.all", 
		user_session );
	return Survey._retrieve(request, user_session, recvCallback );
}


Survey.retrieveRequired = function(user_session, recvCallback) {
	var request = new RemoteRequest( 
		"open-ils.circ", 
		"open-ils.circ.survey.retrieve.required", 
		user_session );
	return Survey._retrieve(request, user_session, recvCallback );
}

Survey.retrieveById = function(user_session, id, recvCallback) {
	var request = new RemoteRequest(
		"open-ils.circ",
		"open-ils.circ.survey.fleshed.retrieve",
		id );
	return Survey._retrieve(request, user_session, recvCallback );
}

Survey.retrieveOpacRandomGlobal = function(recvCallback) {
	var request = new RemoteRequest(
		"open-ils.circ",
		"open-ils.circ.survey.retrieve.opac.random.global");
	return Survey._retrieve(request, null, recvCallback );
}


