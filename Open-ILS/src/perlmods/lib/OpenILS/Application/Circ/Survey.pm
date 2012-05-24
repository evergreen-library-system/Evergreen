# ---------------------------------------------------------------
# Copyright (C) 2005  Georgia Public Library Service 
# Bill Erickson <highfalutin@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

package OpenILS::Application::Circ::Survey;
use base qw/OpenILS::Application/;
use strict; use warnings;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::AppUtils;
use Data::Dumper;
use OpenILS::Event;
use Time::HiRes qw(time);
use OpenILS::Utils::CStoreEditor qw/:funcs/;

my $apputils = "OpenILS::Application::AppUtils";

# - creates a new survey
# expects a survey complete with questions and answers
__PACKAGE__->register_method(
	method	=> "add_survey",
	api_name	=> "open-ils.circ.survey.create");

sub add_survey {
	my( $self, $client, $user_session, $survey ) = @_;

	my($user_obj, $evt) = $apputils->checkses($user_session); 
    return $evt if $evt;

	my $session = $apputils->start_db_session();
	$apputils->set_audit_info($session, $user_session, $user_obj->id, $user_obj->wsid);
	my $err = undef; my $id;


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
	return get_fleshed_survey($self, $client, $survey->id() );
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

	
			my $req = $session->request(
				'open-ils.storage.direct.action.survey_question.create',
				$question );
			my $new_id = $req->gather(1);
	
			if(!$new_id) {
				throw OpenSRF::EX::ERROR
					("Error creating new survey question " . $question->question() . "\n")
			}
	
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
	$answer->clear_id();
	my $req = $session->request(
		"open-ils.storage.direct.action.survey_answer.create",
		$answer );
	my $id = $req->gather(1);
	if(!$id) {
		throw OpenSRF::EX::ERROR
			("Error creating survey answer " . $answer->answer() );
	}

}



# retrieve surveys for a specific org subtree.
__PACKAGE__->register_method(
	method	=> "get_required_surveys",
	api_name	=> "open-ils.circ.survey.retrieve.required");

sub get_required_surveys {
	my( $self, $client, $user_session ) = @_;
	

	my ($user_obj, $evt) = $apputils->checkses($user_session); 
    return $evt if $evt;

	my $orgid = $user_obj->ws_ou() ? $user_obj->ws_ou() : $user_obj->home_ou();
	my $surveys = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.action.survey.required.atomic",
		$orgid );

	my @fleshed;
	for my $survey (@$surveys) {
		push(@fleshed, get_fleshed_survey($self, $client, $survey));
	}
	return \@fleshed;

}

__PACKAGE__->register_method(
	method	=> "get_survey_responses",
	api_name	=> "open-ils.circ.survey.response.retrieve");

sub get_survey_responses {
	my( $self, $client, $user_session, $survey_id, $user_id ) = @_;
	
	if(!$user_id) {
	    my ($user_obj, $evt) = $apputils->checkses($user_session); 
        return $evt if $evt;
		$user_id = $user_obj->id;
	}

	my $res = $apputils->simple_scalar_request(
		"open-ils.cstore",
		"open-ils.cstore.direct.action.survey_response.search.atomic",
		{ usr => $user_id, survey => $survey_id } );

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
	
    my ($user_obj, $evt) = $apputils->checkses($user_session); 
    return $evt if $evt;

	my $orgid = $user_obj->ws_ou() ? $user_obj->ws_ou() : $user_obj->home_ou();
	my $surveys = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.action.survey.all.atomic",
		$orgid );

	my @fleshed;
	for my $survey (@$surveys) {
		push(@fleshed, get_fleshed_survey($self, $client, $survey));
	}
	return \@fleshed;
}




__PACKAGE__->register_method(
	method	=> "get_fleshed_survey",
	api_name	=> "open-ils.circ.survey.fleshed.retrieve");

sub get_fleshed_survey {
	my( $self, $client, $survey_id ) = @_;

	my $session = OpenSRF::AppSession->create("open-ils.storage");

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
	

	my $qreq = $session->request(
		"open-ils.storage.direct.action.survey_question.search.survey.atomic", 
		$survey->id() );

	my $questions = $qreq->gather(1); 

	if($questions) {

		for my $question (@$questions) {
			next unless defined $question;
	
			# add this question to the survey
			push( @{$survey->questions()}, $question );
	

			my $ans_req = $session->request(
				"open-ils.storage.direct.action.survey_answer.search.question.atomic",
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


	if(!ref($responses)) { $responses = [$responses]; }

	my $session = $apputils->start_db_session();

	my $group_id = $session->request(
		"open-ils.storage.action.survey_response.next_group_id")->gather(1);

	my %already_seen;
	for my $res (@$responses) {

		my $id; 

		if($self->api_name =~ /session/) {
			if( ! ($id = $already_seen{$res->usr}) ) {
                my ($user_obj, $evt) = $apputils->checkses($res->usr);
                return $evt if $evt;
				$id = $user_obj->id;
				$already_seen{$res->usr} = $id;
			}
			$res->usr($id);
		} elsif( $self->api_name =~ /anon/ ) {
			$res->clear_usr();
		}
		
		$res->response_group_id($group_id);
		my $req = $session->request(
			"open-ils.storage.direct.action.survey_response.create",
			$res );
		my $newid = $req->gather(1);

		if(!$newid) {
			throw OpenSRF::EX::ERROR
				("Error creating new survey response");
		}
	}

	$apputils->commit_db_session($session);

	return 1;
}


__PACKAGE__->register_method(
	method	=> "get_random_survey",
	api_name	=> "open-ils.circ.survey.retrieve.opac.random");

sub get_random_survey {
	my( $self, $client, $user_session ) = @_;
	
    my ($user_obj, $evt) = $apputils->checkses($user_session); 
    return $evt if $evt;

	my $surveys = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.action.survey.opac.atomic",
		$user_obj->home_ou() );

	my $random = int(rand(scalar(@$surveys)));
	my $surv = $surveys->[$random];

	return get_fleshed_survey($self, $client, $surv);

}

__PACKAGE__->register_method(
	method	=> "get_random_survey_global",
	api_name	=> "open-ils.circ.survey.retrieve.opac.random.global");

sub get_random_survey_global {
	my( $self, $client ) = @_;
	
	my $surveys = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.action.survey.search.atomic",
		# XXX grab the org tree to get the root id...
		{ owner => 1, opac => 't' } );

	my $random = int(rand(scalar(@$surveys)));
	my $surv = $surveys->[$random];

	return get_fleshed_survey($self, $client, $surv);

}


__PACKAGE__->register_method (
	method		=> 'delete_survey',
	api_name	=> 'open-ils.circ.survey.delete.cascade'
);
__PACKAGE__->register_method (
	method		=> 'delete_survey',
	api_name	=> 'open-ils.circ.survey.delete.cascade.override'
);

sub delete_survey {
    my($self, $conn, $auth, $survey_id, $oargs) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    $oargs = { all => 1 } unless defined $oargs;

    my $survey = $e->retrieve_action_survey($survey_id) 
        or return $e->die_event;
    return $e->die_event unless $e->allowed('ADMIN_SURVEY', $survey->owner);

    my $questions = $e->search_action_survey_question({survey => $survey_id});
    my @answers;
    push(@answers, @{$e->search_action_survey_answer({question => $_->id})}) for @$questions;
    my $responses = $e->search_action_survey_response({survey => $survey_id});

    return OpenILS::Event->new('SURVEY_RESPONSES_EXIST')
        if @$responses and ($self->api_name =! /override/ || !($oargs->{all} || grep { $_ eq 'SURVEY_RESPONSES_EXIST' } @{$oargs->{events}}));

    for my $resp (@$responses) {
        $e->delete_action_survey_response($resp) or return $e->die_event;
    }

    for my $ans (@answers) {
        $e->delete_action_survey_answer($ans) or return $e->die_event;
    }

    for my $quest (@$questions) {
        $e->delete_action_survey_question($quest) or return $e->die_event;
    }

    $e->delete_action_survey($survey) or return $e->die_event;

    $e->commit;
    return 1;
}





1;
