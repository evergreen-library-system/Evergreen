package OpenILS::Application::URLVerify;

# For code searchability, I'm telling you this is the "link checker."

use base qw/OpenILS::Application/;
use strict; use warnings;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::MultiSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::AppUtils;
use LWP::UserAgent;

use Data::Dumper;

$Data::Dumper::Indent = 0;

my $U = 'OpenILS::Application::AppUtils';

my $user_agent_string;

sub initialize {
    my $conf = new OpenSRF::Utils::SettingsClient;

    my @confpath = qw/apps open-ils.url_verify app_settings user_agent/;

    $user_agent_string =
        sprintf($conf->config_value(@confpath), __PACKAGE__->ils_version);

    $logger->info("using '$user_agent_string' as User Agent string");
}

__PACKAGE__->register_method(
    method => 'verify_session',
    api_name => 'open-ils.url_verify.session.verify',
    stream => 1,
    max_bundle_count => 1,
    signature => {
        desc => q/
            Performs verification on all (or a subset of the) URLs within the requested session.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Session ID (url_verify.session.id)', type => 'number'},
            {desc => 'URL ID list (optional).  An empty list will result in no URLs being processed, but null will result in all the URLs for the session being processed', type => 'array'},
            {
                desc => q/
                    Options (optional).
                        report_all => bypass response throttling and return all URL sub-process
                            responses to the caller.  Not recommened for remote (web, etc.) clients,
                            because it can be a lot of data.
                        resume_attempt => atttempt_id.  Resume verification after a failure.
                        resume_with_new_attempt => If true, resume from resume_attempt, but
                            create a new attempt to track the resumption.
                    /,
                type => 'hash'
            }
        ],
        return => {desc => q/
            Stream of objects containing the number of URLs to be processed (url_count),
            the number processed thus far including redirects (total_processed),
            and the current url_verification object (current_verification).

            Note that total_processed may ultimately exceed url_count, since it
            includes non-anticipate-able redirects.

            The final response contains url_count, total_processed, and the
            verification_attempt object (attempt).
            /
        }
    }
);

# "verify_session" sounds like something to do with authentication, but it
# actually means for a given session, verify all the URLs associated with
# that session.
sub verify_session {
    my ($self, $client, $auth, $session_id, $url_ids, $options) = @_;
    $options ||= {};

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('URL_VERIFY');

    my $session = $e->retrieve_url_verify_session($session_id)
        or return $e->die_event;

    my $attempt_id = $options->{resume_attempt};

    if (!$url_ids) {

        # No URLs provided, load all URLs for the requested session

        my $query = {
            select => {uvu => ['id']},
            from => {
                uvu => { # url
                    uvs => { # session
                        filter => {id => $session_id}
                    }
                }
            }
        };

        if ($attempt_id) {

            # when resuming an existing attempt (that presumably failed
            # mid-processing), we only want to process URLs that either
            # have no linked url_verification or have an un-completed
            # url_verification.

            $logger->info("url: resuming attempt $attempt_id");

            $query->{from}->{uvu}->{uvuv} = {
                type => 'left',
                filter => {attempt => $attempt_id}
            };

            $query->{where} = {
                '+uvuv' => {
                    '-or' => [
                        {id => undef}, # no verification started
                        {res_code => undef} # verification started but did no complete
                    ]
                }
            };

        } else {

            # this is a new attempt, so we only want to process URLs that
            # originated from the source records and not from redirects.

            $query->{where} = {
                '+uvu' => {redirect_from => undef}
            };
        }

        my $ids = $e->json_query($query);
        $url_ids = [ map {$_->{id}} @$ids ];
    }

    my $url_count = scalar(@$url_ids);
    $logger->info("url: processing $url_count URLs");

    my $attempt;
    if ($attempt_id and !$options->{resume_with_new_attempt}) {

        $attempt = $e->retrieve_url_verification_attempt($attempt_id)
            or return $e->die_event;

        # no data was written
        $e->rollback;

    } else {

        $attempt = Fieldmapper::url_verify::verification_attempt->new;
        $attempt->session($session_id);
        $attempt->usr($e->requestor->id);
        $attempt->start_time('now');

        $e->create_url_verify_verification_attempt($attempt)
            or return $e->die_event;

        $attempt = $e->data;
        $e->commit;
    }

    # END DB TRANSACTION

    # Now cycle through the URLs in batches.

    my $batch_size = $U->ou_ancestor_setting_value(
        $session->owning_lib,
        'url_verify.verification_batch_size', $e) || 5;

    my $total_excluding_redirects = 0;
    my $total_processed = 0; # total number processed, including redirects
    my $resp_window = 1;

    # before we start the real work, let the caller know
    # the attempt (id) so recovery is possible.

    $client->respond({
        url_count => $url_count,
        total_processed => $total_processed,
        total_excluding_redirects => $total_excluding_redirects,
        attempt => $attempt
    });

    my $multises = OpenSRF::MultiSession->new(

        app => 'open-ils.url_verify', # hey, that's us!
        cap => $batch_size,

        success_handler => sub {
            my ($self, $req) = @_;

            # API call streams fleshed url_verification objects.  We wrap
            # those up with some extra info and pass them on to the caller.

            for my $resp (@{$req->{response}}) {
                my $content = $resp->content;

                if ($content) {

                    $total_processed++;

                    if ($options->{report_all} or ($total_processed % $resp_window == 0)) {

                        $client->respond({
                            url_count => $url_count,
                            current_verification => $content,
                            total_excluding_redirects => $total_excluding_redirects,
                            total_processed => $total_processed
                        });

                        # start off responding quickly, then throttle
                        # back to only relaying every 256 messages.
                        $resp_window *= 2 unless $resp_window >= 256;
                    }
                }
            }
        },

        failure_handler => sub {
            my ($self, $req) = @_;

            # {error} should be an Error w/ a toString
            $logger->error("url: error processing URL: " . $req->{error});
        }
    );

    sort_and_fire_domains(
        $e, $auth, $attempt, $url_ids, $multises, \$total_excluding_redirects
    );

    # Wait for all requests to be completed
    $multises->session_wait(1);

    # All done.  Let's wrap up the attempt.
    $attempt->finish_time('now');

    $e->xact_begin;
    $e->update_url_verify_verification_attempt($attempt) or
        return $e->die_event;

    $e->xact_commit;

    # This way the caller gets an actual timestamp in the "finish_time" field
    # instead of the string "now".
    $attempt = $e->retrieve_url_verify_verification_attempt($e->data) or
        return $e->die_event;

    $e->disconnect;

    return {
        url_count => $url_count,
        total_processed => $total_processed,
        total_excluding_redirects => $total_excluding_redirects,
        attempt => $attempt
    };
}

# retrieves the URL domains and sorts them into buckets*
# Iterates over the buckets and fires the multi-session call
# the main drawback to this domain sorting approach is that
# any domain used a lot more than the others will be the
# only domain standing after the others are exhausted, which
# means it will take a beating at the end of the batch.
#
# * local data structures, not container.* buckets
sub sort_and_fire_domains {
    my ($e, $auth, $attempt, $url_ids, $multises, $count) = @_;

    # there is potential here for data sets to be too large
    # for delivery, but it's not likely, since we're only
    # fetching ID and domain.
    my $urls = $e->json_query(
        {
            select => {uvu => ['id', 'domain']},
            from => 'uvu',
            where => {id => $url_ids}
        },
        # {substream => 1} only if needed
    );

    # sort them into buckets based on domain name
    my %domains;
    for my $url (@$urls) {
        $domains{$url->{domain}} = [] unless $domains{$url->{domain}};
        push(@{$domains{$url->{domain}}}, $url->{id});
    }

    # loop through the domains and fire the verification call
    while (keys %domains) {
        for my $domain (keys %domains) {

            my $url_id = pop(@{$domains{$domain}});
            delete $domains{$domain} unless @{$domains{$domain}};

            $multises->request(
                'open-ils.url_verify.verify_url',
                $auth, $attempt->id, $url_id);
            
            $$count++;  # sic, a reference to a scalar
        }
    }
}


# XXX I really want to move this method to open-ils.storage, so we don't have
# to authenticate a zillion times. LFW

__PACKAGE__->register_method(
    method => 'verify_url',
    api_name => 'open-ils.url_verify.verify_url',
    stream => 1,
    signature => {
        desc => q/
            Performs verification of a single URL.  When a redirect is detected,
            a new URL is created to model the redirect and the redirected URL
            is then tested, up to max-redirects or a loop is detected.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Verification attempt ID (url_verify.verification_attempt.id)', type => 'number'},
            {desc => 'URL id (url_verify.url.id)', type => 'number'},
        ],
        return => {desc => q/Stream of url_verification objects, one per URL tested/}
    }
);

=head comment

verification.res_code:

999 bad hostname, etc. (IO::Socket::Inet errors)
998 in-flight errors (e.g connection closed prematurely)
997 timeout
996 redirect loop
995 max redirects

verification.res_text:

$@ or custom message "Redirect Loop"

=cut

sub verify_url {
    my ($self, $client, $auth, $attempt_id, $url_id) = @_;
    my %seen_urls;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $url = $e->retrieve_url_verify_url($url_id) or return $e->event;

    my ($attempt, $delay, $max_redirects, $timeout) =
        collect_verify_attempt_and_settings($e, $attempt_id);

    return $e->event unless $e->allowed(
        'URL_VERIFY', $attempt->session->owning_lib);

    my $cur_url = $url;
    my $loop_detected = 0;
    my $redir_count = 0;

    while ($redir_count++ < $max_redirects) {

        if ($seen_urls{$cur_url->full_url}) {
            $loop_detected = 1;
            last;
        }

        $seen_urls{$cur_url->full_url} = $cur_url;

        my $url_resp = verify_one_url($e, $attempt, $cur_url, $timeout);

        # something tragic happened
        return $url_resp if $U->is_event($url_resp);

        # flesh and respond to the caller
        $url_resp->{verification}->url($cur_url);
        $client->respond($url_resp->{verification});

        $cur_url = $url_resp->{redirect_url} or last;
    }

    if ($loop_detected or $redir_count > $max_redirects) {

        my $vcation = Fieldmapper::url_verify::url_verification->new;
        $vcation->url($cur_url->id);
        $vcation->attempt($attempt->id);
        $vcation->req_time('now');

        if ($loop_detected) {
            $logger->info("url: redirect loop detected at " . $cur_url->full_url);
            $vcation->res_code('996');
            $vcation->res_text('Redirect Loop');

        } else {
            $logger->info("url: max redirects reached for source URL " . $url->full_url);
            $vcation->res_code('995');
            $vcation->res_text('Max Redirects');
        }

        $e->xact_begin;
        $e->create_url_verify_url_verification($vcation) or return $e->die_event;
        $e->xact_commit;
    }

    # The calling code is likely not multi-threaded, so a
    # per-URL (i.e. per-thread) delay would not be possible.
    # Applying the delay here allows the caller to process
    # batches of URLs without having to worry about the delay.
    sleep $delay;

    return undef;
}

# temporarily cache some data to avoid a pile
# of data lookups on every URL processed.
my %cache;
sub collect_verify_attempt_and_settings {
    my ($e, $attempt_id) = @_;
    my $attempt;

    if (!(keys %cache) or $cache{age} > 20) { # configurable?
        %cache = (
            age => 0,
            attempt => {},
            delay => {},
            redirects => {},
            timeout => {},
        );
    }

    if ( !($attempt = $cache{attempt}{$attempt_id}) ) {

        # attempt may have just been created, so
        # we need to guarantee a write-DB read.
        $e->xact_begin;

        $attempt =
            $e->retrieve_url_verify_verification_attempt([
                $attempt_id, {
                    flesh => 1,
                    flesh_fields => {uvva => ['session']}
                }
            ]) or return $e->die_event;

        $e->rollback;

        $cache{attempt}{$attempt_id} = $attempt;
    }

    my $org = $attempt->session->owning_lib;

    if (!$cache{timeout}{$org}) {

        $cache{delay}{$org} = $U->ou_ancestor_setting_value(
            $org, 'url_verify.url_verification_delay', $e);

        # 0 is a valid delay
        $cache{delay}{$org} = 2 unless defined $cache{delay}{$org};

        $cache{redirects}{$org} = $U->ou_ancestor_setting_value(
            $org, 'url_verify.url_verification_max_redirects', $e) || 20;

        $cache{timeout}{$org} = $U->ou_ancestor_setting_value(
            $org, 'url_verify.url_verification_max_wait', $e) || 5;

        $logger->info(
            sprintf("url: loaded settings delay=%s; max_redirects=%s; timeout=%s",
                $cache{delay}{$org}, $cache{redirects}{$org}, $cache{timeout}{$org}));
    }

    $cache{age}++;


    return (
        $cache{attempt}{$attempt_id},
        $cache{delay}{$org},
        $cache{redirects}{$org},
        $cache{timeout}{$org}
    );
}


# searches for a completed url_verfication for any url processed
# within this verification attempt whose full_url matches the
# full_url of the provided URL.
sub find_matching_url_for_attempt {
    my ($e, $attempt, $url) = @_;

    my $match = $e->json_query({
        select => {uvuv => ['id']},
        from => {
            uvuv => {
                uvva => { # attempt
                    filter => {id => $attempt->id}
                },
                uvu => {} # url
            }
        },
        where => {
            '+uvu' => {
                id => {'!=' => $url->id},
                full_url => $url->full_url
            },

            # There could be multiple verifications for matching URLs
            # We only want a verification that completed.
            # Note also that 2 identical URLs processed within the same
            # sub-batch will have to each be fully processed in their own
            # right, since neither knows how the other will ultimately fare.
            '+uvuv' => {
                res_time => {'!=' => undef}
            }
        }
    })->[0];

    return $e->retrieve_url_verify_url_verification($match->{id}) if $match;
    return undef;
}


=head comment

1. create the verification object and commit.
2. test the URL
3. update the verification object to capture the results of the test
4. Return redirect_url object if this is a redirect, otherwise undef.

=cut

sub verify_one_url {
    my ($e, $attempt, $url, $timeout) = @_;

    my $url_text = $url->full_url;
    my $redir_url;

    # first, create the verification object so we can a) indicate that
    # we're working on this URL and b) get the DB to set the req_time.

    my $vcation = Fieldmapper::url_verify::url_verification->new;
    $vcation->url($url->id);
    $vcation->attempt($attempt->id);
    $vcation->req_time('now');

    # begin phase-I DB communication

    $e->xact_begin;

    my $match_vcation = find_matching_url_for_attempt($e, $attempt, $url);

    if ($match_vcation) {
        $logger->info("url: found matching URL in verification attempt [$url_text]");
        $vcation->res_code($match_vcation->res_code);
        $vcation->res_text($match_vcation->res_text);
        $vcation->redirect_to($match_vcation->redirect_to);
    }

    $e->create_url_verify_url_verification($vcation) or return $e->die_event;
    $e->xact_commit;

    # found a matching URL, no need to re-process
    return {verification => $vcation} if $match_vcation;

    # End phase-I DB communication
    # No active DB xact means no cstore timeout concerns.

    # Now test the URL.

    $ENV{FTP_PASSIVE} = 1; # TODO: setting?

    my $ua = LWP::UserAgent->new(
        ssl_opts => {verify_hostname => 0}, # TODO: verify_hostname setting?
        agent => $user_agent_string
    );

    $ua->timeout($timeout);

    my $req = HTTP::Request->new(HEAD => $url->full_url);

    # simple_request avoids LWP's auto-redirect magic
    my $res = $ua->simple_request($req);

    $logger->info(sprintf(
        "url: received HTTP '%s' / '%s' [%s]",
        $res->code,
        $res->message,
        $url_text
    ));

    $vcation->res_code($res->code);
    $vcation->res_text($res->message);

    # is this a redirect?
    if ($res->code =~ /^3/) {

        if (my $loc = $res->headers->{location}) {
            $redir_url = Fieldmapper::url_verify::url->new;
            $redir_url->session($attempt->session);
            $redir_url->redirect_from($url->id);
            $redir_url->full_url($loc);

            $logger->info("url: redirect found $url_text => $loc");

        } else {
            $logger->info("url: server returned 3XX but no 'Location' header for url $url_text");
        }
    }

    # Begin phase-II DB communication

    $e->xact_begin;

    if ($redir_url) {
        $redir_url = $e->create_url_verify_url($redir_url) or return $e->die_event;
        $vcation->redirect_to($redir_url->id);
    }

    $vcation->res_time('now');
    $e->update_url_verify_url_verification($vcation) or return $e->die_event;
    $e->commit;

    return {
        verification => $vcation,
        redirect_url => $redir_url
    };
}


__PACKAGE__->register_method(
    method => "create_session",
    api_name => "open-ils.url_verify.session.create",
    signature => {
        desc => q/Create a URL verify session. Also automatically create and
            link a container./,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "session name", type => "string"},
            {desc => "QueryParser search", type => "string"},
            {desc => "owning_lib (defaults to ws_ou)", type => "number"},
        ],
        return => {desc => "ID of new session or event on error", type => "number"}
    }
);

sub create_session {
    my ($self, $client, $auth, $name, $search, $owning_lib) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    $owning_lib ||= $e->requestor->ws_ou;
    return $e->die_event unless $e->allowed("URL_VERIFY", $owning_lib);

    $name .= "";
    my $name_test = $e->search_url_verify_session({name => $name});
    return $e->die_event unless $name_test; # db error
    return $e->die_event(
        new OpenILS::Event("OBJECT_UNIQUE_IDENTIFIER_USED", note => "name"),
    ) if @$name_test;   # already existing sessions with that name

    my $session = Fieldmapper::url_verify::session->new;
    $session->name($name);
    $session->owning_lib($owning_lib);
    $session->creator($e->requestor->id);
    $session->search($search);

    my $container = Fieldmapper::container::biblio_record_entry_bucket->new;
    $container->btype("url_verify");
    $container->owner($e->requestor->id);
    $container->name($name);
    $container->description("Automatically generated");

    $e->create_container_biblio_record_entry_bucket($container) or
        return $e->die_event;

    $session->container($e->data->id);
    $e->create_url_verify_session($session) or
        return $e->die_event;

    $e->commit or return $e->die_event;

    return $e->data->id;
}

__PACKAGE__->register_method(
    method => "delete_session",
    api_name => "open-ils.url_verify.session.delete",
    signature => {
        desc => q/Delete a URL verify session and associated containers, selectors, attempts,
            and verifications./,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "session id", type => "number"},
        ],
        return => {desc => "1 on success, event on failure", type => "number"}
    }
);

sub delete_session {
    my ($self, $client, $auth, $session_id) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    return $e->die_event unless $e->allowed("URL_VERIFY", $e->requestor->ws_ou);

    my $session = $e->retrieve_url_verify_session($session_id);
    return $e->die_event unless $session; # not found

    my $container = $e->retrieve_container_biblio_record_entry_bucket($session->container);

    $e->delete_url_verify_session($session) or
        return $e->die_event;

    $e->delete_container_biblio_record_entry_bucket($container) or
        return $e->die_event;

    $e->commit or return $e->die_event;

    return 1;
}

# _check_for_existing_bucket_items() is used later by session_search_and_extract()
sub _check_for_existing_bucket_items {
    my ($e, $session) = @_;

    my $items = $e->json_query(
        {
            select => {cbrebi => ['id']},
            from => {cbrebi => {}},
            where => {bucket => $session->container},
            limit => 1
        }
    ) or return $e->die_event;

    return new OpenILS::Event("URL_VERIFY_SESSION_ALREADY_SEARCHED") if @$items;

    return;
}

# _get_all_search_results() is used later by session_search_and_extract()
sub _get_all_search_results {
    my ($client, $session) = @_;

    my @result_ids;

    # Don't loop if the user has specified their own offset.
    if ($session->search =~ /offset\(\d+\)/) {
        my $res = $U->simplereq(
            "open-ils.search",
            "open-ils.search.biblio.multiclass.query.staff",
            {}, $session->search
        );

        return new OpenILS::Event("UNKNOWN") unless $res;
        return $res if $U->is_event($res);

        @result_ids = map { shift @$_ } @{$res->{ids}}; # IDs nested in array
    } else {
        my $count;
        my $so_far = 0;

        LOOP: { do {    # Fun fact: you cannot "last" out of a do/while in Perl
                        # unless you wrap it another loop structure.
            my $search = $session->search . " offset(".scalar(@result_ids).")";

            my $res = $U->simplereq(
                "open-ils.search",
                "open-ils.search.biblio.multiclass.query.staff",
                {}, $search
            );

            return new OpenILS::Event("UNKNOWN") unless $res;
            return $res if $U->is_event($res);

            # Search only returns the total count when offset is 0.
            # We can't get more than one superpage this way, XXX TODO ?
            $count = $res->{count} unless defined $count;

            my @this_batch = map { shift @$_ } @{$res->{ids}}; # unnest IDs
            push @result_ids, @this_batch;

            # Send a keepalive in case search is slow, although it'll probably
            # be the query for the first ten results that's slowest.
            $client->status(new OpenSRF::DomainObject::oilsContinueStatus);

            last unless @this_batch; # Protect against getting fewer results
                                     # than count promised.

        } while ($count - scalar(@result_ids) > 0); }
    }

    return (undef, @result_ids);
}


__PACKAGE__->register_method(
    method => "session_search_and_extract",
    api_name => "open-ils.url_verify.session.search_and_extract",
    stream => 1,
    signature => {
        desc => q/
            Perform the search contained in the session,
            populating the linked bucket, and extracting URLs /,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "url_verify.session id", type => "number"},
        ],
        return => {
            desc => q/stream of numbers: first number of search results, then
                numbers of extracted URLs for each record, grouped into arrays
                of 100/,
            type => "number"
        }
    }
);

sub session_search_and_extract {
    my ($self, $client, $auth, $ses_id) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    my $session = $e->retrieve_url_verify_session(int($ses_id));

    return $e->die_event unless
        $session and $e->allowed("URL_VERIFY", $session->owning_lib);

    if ($session->creator != $e->requestor->id) {
        $e->disconnect;
        return new OpenILS::Event("URL_VERIFY_NOT_SESSION_CREATOR");
    }

    my $delete_error =
        _check_for_existing_bucket_items($e, $session);

    if ($delete_error) {
        $e->disconnect;
        return $delete_error;
    }

    my ($search_error, @result_ids) =
        _get_all_search_results($client, $session);

    if ($search_error) {
        $e->disconnect;
        return $search_error;
    }

    $e->xact_begin;

    # Make and save a bucket item for each search result.

    my $pos = 0;
    my @item_ids;

    # There's an opportunity below to parallelize the extraction of URLs if
    # we need to.

    foreach my $bre_id (@result_ids) {
        my $bucket_item =
            Fieldmapper::container::biblio_record_entry_bucket_item->new;

        $bucket_item->bucket($session->container);
        $bucket_item->target_biblio_record_entry($bre_id);
        $bucket_item->pos($pos++);

        $e->create_container_biblio_record_entry_bucket_item($bucket_item) or
            return $e->die_event;

        push @item_ids, $e->data->id;
    }

    $e->xact_commit;

    $client->respond($pos); # first response: the number of items created
                            # (number of search results)

    # For each contain item, extract URLs.  Report counts of URLs extracted
    # from each record in batches at every hundred records.  XXX Arbitrary.

    my @url_counts;
    foreach my $item_id (@item_ids) {
        my $res = $e->json_query({
            from => ["url_verify.extract_urls", $ses_id, $item_id]
        }) or return $e->die_event;

        push @url_counts, $res->[0]{"url_verify.extract_urls"};

        if (scalar(@url_counts) % 100 == 0) {
            $client->respond([ @url_counts ]);
            @url_counts = ();
        }
    }

    $client->respond([ @url_counts ]) if @url_counts;

    $e->disconnect;
    return;
}


1;
