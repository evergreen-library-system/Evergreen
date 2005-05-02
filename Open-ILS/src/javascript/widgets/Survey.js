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
		var ans = new SurveyAnswer(answer, poll);
		this.answers.push(ans);
		this.selector.appendChild(
			createAppTextNode(answer.answer()));
		this.selector.appendChild(ans.getNode());
	} else {
		var ans = new SurveyAnswer(answer);
		this.answers.push(ans);
		this.selector.options[ this.selector.options.length ] = ans.getNode();
	}
}


function SurveyAnswer(answer,poll) {
	this.answer = answer;

	if(poll) {
		this.node = createAppElement("input");
		this.node.setAttribute("type", "radio");
		this.node.value = answer.id();
	} else {
		this.node = new Option( answer.answer(), answer.id() );
	}

	add_css_class( this.node, "survey_answer" );
}

SurveyAnswer.prototype.getNode = function() {
	return this.node;
}

function Survey(survey, onclick) {

	debug("Creating new survey " + survey.name() );
	this.survey = survey;

	this.node			= createAppElement("div");
	this.node.id		= "survey_" + survey.id();

	this.wrapperNode	= createAppElement("div");
	this.wrapperNode.appendChild(this.node);
	this.nameNode		= createAppElement("div");
	this.nameNode.appendChild(createAppTextNode(survey.name()));
	this.descNode		= createAppElement("div");
	this.descNode.appendChild( createAppTextNode(survey.description()));

	if( survey.poll() == 0 )
		survey.poll(false);
	if( survey.poll() == 1 )
		survey.poll(true);

	if(survey.poll())
		this.qList			= createAppElement("ul");
	else
		this.qList			= createAppElement("ol");

	this.questions		= new Array();
	this.submittedNode	= createAppElement("div");

	add_css_class(this.submittedNode,	"survey_submitted" );
	add_css_class(this.nameNode,			"survey_name");
	add_css_class(this.descNode,			"survey_description");
	add_css_class(this.node,				"survey" );

	this.node.appendChild( this.nameNode );
	this.node.appendChild( this.descNode );
	this.node.appendChild( this.qList );

	for( var i in survey.questions() ) {
		this.addQuestion( survey.questions()[i] );
	}

	this.buttonDiv	= createAppElement("div");
	add_css_class( this.buttonDiv, "survey_button");
	this.button = createAppElement("input");
	this.button.setAttribute("type", "submit");
	this.button.value = "Submit Survey";
	if(onclick)
		this.button.onclick = onclick;
	this.buttonDiv.appendChild(this.button);
	this.node.appendChild(this.buttonDiv);
	this.node.appendChild( this.submittedNode );
	this.node.appendChild(createAppElement("hr"));

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

Survey.prototype.toString = function() {
	return this.wrapperNode.innerHTML;
}

Survey.prototype.getNode = function() {
	return this.node;
}

Survey.prototype.addQuestion = function(question) {
	var questionObj = new SurveyQuestion(question, this.survey.poll());
	this.questions.push(questionObj);
	for( var i in question.answers() ) {
		questionObj.addAnswer(question.answers()[i], this.survey.poll());
	}

	var item = createAppElement("li");
	item.appendChild(questionObj.getNode());
	this.qList.appendChild(item); 
}

Survey.prototype.submit = function() {

	var responses = this.buildSurveyResponse();
	var request = new RemoteRequest(
		"open-ils.circ",
		"open-ils.circ.survey.submit",
		responses );
	request.send(true);

	/* there is nothing to return, just check for exceptions */
	request.getResultObject();
	this.buttonDiv.innerHTML = "";
	this.submittedNode.appendChild( 
		createAppTextNode("* Submitted *"));
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

Survey._retrieve = function(user_session, method, recvCallback) {

	var request = new RemoteRequest(
		"open-ils.circ", method, user_session );

	if( recvCallback ) {

		debug("Retrieving random survey asynchronously");
		var c = function(req) {
			var surveys = req.getResultObject();
			for( var i in surveys ) {
				var s = surveys[i];
				debug("Retrieved survey " + s.name() );
				var surv = new Survey(s);
				surv.setUserSession(user_session);
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
			surv.setUserSession(user_session);
			surveys.push(surv);
		}
		return surveys;
	}

}

/* this needs a different method for retrieving the correct survey */
Survey.retrieveRandom = function(user_session, recvCallback) {
	return Survey._retrieve(user_session, 
		"open-ils.circ.survey.retrieve.all", recvCallback );
	
}


Survey.retrieveAll = function(user_session, recvCallback) {
	return Survey._retrieve(user_session, 
		"open-ils.circ.survey.retrieve.all", recvCallback );
}


Survey.retrieveRequired = function(user_session, recvCallback) {
	return Survey._retrieve(user_session, 
		"open-ils.circ.survey.required.retrieve", recvCallback );
}




