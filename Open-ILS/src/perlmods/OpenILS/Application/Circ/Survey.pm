package OpenILS::Application::Circ::Survey;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::AppUtils;
use Data::Dumper;
use Time::HiRes qw(time);

my $apputils = "OpenILS::Application::AppUtils";

#open-ils.storage.direct.action.survey.search.*




# - creates a new survey
# expects a survey complete with questions and answers

__PACKAGE__->register_method(
	method	=> "add_survey",
	api_name	=> "open-ils.circ.survey.create");

sub add_survey {
	my( $self, $client, $user_session, $survey ) = @_;

	my $user_obj = $apputils->check_user_session($user_session); 
	my $session = $apputils->start_db_session();
	my $err = undef; my $id;

	warn "Creating new survey\n" . Dumper($survey) . "\n";


	try {

		$survey = _add_survey($session, $survey);
		_add_questions($session, $survey);
		$apputils->commit_db_session($session);

	} catch Error with {
		my $e = shift;
		$err = "Error creating survey: $e\n";
		$apputils->rollback_db_session($session);
	};

	if($err) { throw OpenSRF::EX::ERROR ($err); }

	# re-retrieve the survey from the db and return it
	return $self->get_fleshed_survey( $client, $survey->id() );
}


sub _add_survey {
	my($session, $survey) = @_;
	my $req = $session->request(
		"open-ils.storage.direct.action.survey.create",
		$survey );

	my $id = $req->gather(1);

	if(!$id) { 
		throw OpenSRF::EX::ERROR 
			("Unable to create new survey " . $survey->name()); 
	}

	warn "Created new survey with id $id\n";
	$survey->id($id);
	return $survey;
}

sub _update_survey {
	my($session, $survey) = @_;
}

sub _add_questions {
	my($session, $survey) = @_;

	# create new questions in the db
	if( $survey->questions() ) {
		for my $question (@{$survey->questions()}){
	
			$question->survey($survey->id());
			my $virtual_id = $question->id();
			$question->clear_id();

	
			warn "Creating new question: " . $question->question() . "\n";
			warn Dumper $question;
	
			my $req = $session->request(
				'open-ils.storage.direct.action.survey_question.create',
				$question );
			my $new_id = $req->gather(1);
	
			if(!$new_id) {
				throw OpenSRF::EX::ERROR
					("Error creating new survey question " . $question->question() . "\n")
			}
	
			warn "added new question with id $new_id\n";
	
			# now update the responses to this question
			if($question->answers()) {
				for my $answer (@{$question->answers()}) {
					$answer->question($new_id);
					_add_answer($session,$answer);
				}
			}
		}
	}
}


sub _add_answer {
	my($session, $answer) = @_;
	warn "Adding answer " . $answer->answer() . "\n";
	$answer->clear_id();
	my $req = $session->request(
		"open-ils.storage.direct.action.survey_answer.create",
		$answer );
	my $id = $req->gather(1);
	if(!$id) {
		throw OpenSRF::EX::ERROR
			("Error creating survey answer " . $answer->answer() );
	}

	warn "Added new answer with id $id\n";
}



# retrieve surveys for a specific org subtree.
__PACKAGE__->register_method(
	method	=> "get_required_surveys",
	api_name	=> "open-ils.circ.survey.retrieve.required");

sub get_required_surveys {
	my( $self, $client, $user_session ) = @_;
	
	my $user_obj = $apputils->check_user_session($user_session); 
	return $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.action.survey.required.atomic",
		$user_obj->home_ou() );
}

__PACKAGE__->register_method(
	method	=> "get_survey_responses",
	api_name	=> "open-ils.circ.survey.response.retrieve");

sub get_survey_responses {
	my( $self, $client, $user_session, $survey_id, $user_id ) = @_;
	
	warn "retrieing responses $user_session $survey_id $user_id\n";
	if(!$user_id) {
		my $user_obj = $apputils->check_user_session($user_session); 
		$user_id = $user_obj->id;
	}

	my $res = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.action.survey_response.search.atomic",
		{ usr => $user_id, survey => $survey_id } );

	warn "Surveys: " .  Dumper($res);

	if( $res && ref($res) and $res->[0]) {
		return [ sort { $a->id() <=> $b->id() } @$res ];
	} 

	return [];
}

__PACKAGE__->register_method(
	method	=> "get_all_surveys",
	api_name	=> "open-ils.circ.survey.retrieve.all");

sub get_all_surveys {
	my( $self, $client, $user_session ) = @_;
	
	my $user_obj = $apputils->check_user_session($user_session); 
	my $surveys = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.action.survey.all.atomic",
		$user_obj->home_ou() );

	my @fleshed;
	for my $survey (@$surveys) {
		push(@fleshed, $self->get_fleshed_survey($client, $survey));
	}
	return \@fleshed;
}




__PACKAGE__->register_method(
	method	=> "get_fleshed_survey",
	api_name	=> "open-ils.circ.survey.fleshed.retrieve");

sub get_fleshed_survey {
	my( $self, $client, $survey_id ) = @_;

	my $session = OpenSRF::AppSession->create("open-ils.storage");

	warn "Searching for survey $survey_id\n";

	my $survey;
	if( ref($survey_id) and 
			(ref($survey_id) =~ /^Fieldmapper/)) {
		$survey = $survey_id;

	} else {

		my $sreq = $session->request(
			"open-ils.storage.direct.action.survey.retrieve",
			$survey_id );
		$survey = $sreq->gather(1);
		if(! $survey) { return undef; }
	}

	$survey->questions([]);
	

	warn "Grabbing survey questions\n";
	my $qreq = $session->request(
		"open-ils.storage.direct.action.survey_question.search.survey", 
		$survey->id() );

	my $questions = $qreq->gather(1); 

	if($questions) {

		for my $question (@$questions) {
	
			# add this question to the survey
			push( @{$survey->questions()}, $question );
	
			warn "Grabbing question answers\n";

			my $ans_req = $session->request(
				"open-ils.storage.direct.action.survey_answer.search.question",
				$question->id() );
	
			# add this array of answers to this question
			$question->answers( $ans_req->gather(1) );
	
		}
	}

	$session->disconnect();
	return $survey;

}



__PACKAGE__->register_method(
	method	=> "submit_survey",
	api_name	=> "open-ils.circ.survey.submit.session");

__PACKAGE__->register_method(
	method	=> "submit_survey",
	api_name	=> "open-ils.circ.survey.submit.user_id");

__PACKAGE__->register_method(
	method	=> "submit_survey",
	api_name	=> "open-ils.circ.survey.submit.anon");


sub submit_survey {
	my( $self, $client, $responses ) = @_;

	if(!$responses) {
		throw OpenSRF::EX::ERROR 
			("No survey object sent in update");
	}

	use Data::Dumper;
	warn "Submitting survey " . Dumper($responses) . "\n";

	if(!ref($responses)) { $responses = [$responses]; }

	my $session = $apputils->start_db_session();

	my $group_id = $session->request(
		"open-ils.storage.action.survey_response.next_group_id")->gather(1);

	my %already_seen;
	for my $res (@$responses) {

		my $id; 

		if($self->api_name =~ /session/) {
			if( ! ($id = $already_seen{$res->usr}) ) {
				my $user_obj = $apputils->check_user_session($res->usr); 
				$id = $user_obj->id;
				$already_seen{$res->usr} = $id;
			}
			$res->usr($id);
		} elsif( $self->api_name =~ /anon/ ) {
			$res->clear_usr();
		}
		
		warn "Submitting response with question " . 
			$res->question . " and group $group_id \n";

		$res->response_group_id($group_id);
		my $req = $session->request(
			"open-ils.storage.direct.action.survey_response.create",
			$res );
		my $newid = $req->gather(1);
		warn "New response id: $newid\n";

		if(!$newid) {
			throw OpenSRF::EX::ERROR
				("Error creating new survey response");
		}
	}

	$apputils->commit_db_session($session);
	warn "survey response update completed\n";

	return 1;
}


__PACKAGE__->register_method(
	method	=> "get_random_survey",
	api_name	=> "open-ils.circ.survey.retrieve.opac.random");

sub get_random_survey {
	my( $self, $client, $user_session ) = @_;
	
	warn "retrieving random survey\n";
	my $user_obj = $apputils->check_user_session($user_session); 
	my $surveys = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.action.survey.opac.atomic",
		$user_obj->home_ou() );

	my $random = int(rand(scalar(@$surveys)));
	warn "Random survey index for process $$ is $random\n";
	my $surv = $surveys->[$random];

	return $self->get_fleshed_survey($client, $surv);

}

__PACKAGE__->register_method(
	method	=> "get_random_survey_global",
	api_name	=> "open-ils.circ.survey.retrieve.opac.random.global");

sub get_random_survey_global {
	my( $self, $client ) = @_;
	
	warn "retrieving random global survey\n";
	my $surveys = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.action.survey.search.atomic",
		# XXX grab the org tree to get the root id...
		{ owner => 1, opac => 't' } );

	my $random = int(rand(scalar(@$surveys)));
	warn "Random survey index for process $$ is $random\n";
	my $surv = $surveys->[$random];

	return $self->get_fleshed_survey($client, $surv);

}










1;





