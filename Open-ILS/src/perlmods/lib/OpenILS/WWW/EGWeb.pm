package OpenILS::WWW::EGWeb;
use strict; use warnings;
use Template;
use XML::Simple;
use XML::LibXML;
use File::stat;
use Encode;
use Apache2::Const -compile => qw(OK DECLINED HTTP_INTERNAL_SERVER_ERROR HTTP_NOT_FOUND HTTP_GONE);
use Apache2::Log;
use OpenSRF::EX qw(:try);
use OpenSRF::AppSession;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use List::MoreUtils qw/uniq/;

use constant OILS_HTTP_COOKIE_SKIN => 'eg_skin';
use constant OILS_HTTP_COOKIE_THEME => 'eg_theme';
use constant OILS_HTTP_COOKIE_LOCALE => 'eg_locale';

# cache string bundles
my %registered_locales;

# cache template path -r tests
my %vhost_path_cache;

# cache template processors by vhost
my %vhost_processor_cache;

my $bootstrap_config;
my @context_loaders_to_preinit = ();
my %locales_to_preinit = ();

sub import {
    my ($self, $bootstrap_config, $loaders, $locales) = @_;
    @context_loaders_to_preinit = split /\s+/, $loaders, -1 if defined($loaders);
    %locales_to_preinit = map { $_ => parse_eg_locale($_) }
                          split /\s+/, $locales, -1 if defined($locales);
}

sub child_init {
    OpenSRF::System->bootstrap_client(config_file => $bootstrap_config);
    my $idl = OpenSRF::Utils::SettingsClient->new->config_value("IDL");
    Fieldmapper->import(IDL => $idl);
    foreach my $loader (@context_loaders_to_preinit) {
        eval {
            $loader->use;
            $loader->child_init(%locales_to_preinit);
        };
    }
    return Apache2::Const::OK;
}

sub handler {
    my $r = shift;
    my $stat = handler_guts($r);

    # other opensrf clients share this apache process,
    # so it's critical to reset the locale after each
    # response is handled, lest the other clients 
    # adopt our temporary, global locale value.
    OpenSRF::AppSession->reset_locale;
    return $stat;
}
    
sub handler_guts {
    my $r = shift;
    my $ctx = load_context($r);
    my $base = $ctx->{base_path};

    my($template, $page_args, $as_xml) = find_template($r, $base, $ctx);
    $ctx->{page_args} = $page_args;

    my $stat = run_context_loader($r, $ctx);

    # Handle deleted or never existing records a little more gracefully.
    # For these two special cases, we set the status so that the request
    # header will contain the appropriate HTTP status code, but reset the
    # status so that Apache will continue to process the request and provide
    # more than just the raw HTTP error page.
    if ($stat == Apache2::Const::HTTP_GONE || $stat == Apache2::Const::HTTP_NOT_FOUND) {
        $r->status($stat);
        $stat = Apache2::Const::OK;
    }   
    return $stat unless $stat == Apache2::Const::OK;

    # emit context as JSON if handler requests
    if ($ctx->{json_response}) {
        $r->content_type("application/json; charset=utf-8");
        $r->headers_out->add("cache-control" => "no-store, no-cache, must-revalidate");
        $r->headers_out->add("expires" => "-1");
        if ($ctx->{json_reponse_cookie}) {
            $r->headers_out->add('Set-Cookie' => $ctx->{json_reponse_cookie})
        }
        $r->print(OpenSRF::Utils::JSON->perl2JSON($ctx->{json_response}));
        return Apache2::Const::OK;
    }

    return Apache2::Const::DECLINED unless $template;

    my $text_handler = set_text_handler($ctx, $r);

    my $processor_key = $as_xml ? 'xml:' : 'text:';                 # separate by XML strictness
    $processor_key .= $r->hostname.':';                         # ... and vhost
    $processor_key .= $r->dir_config('OILSWebContextLoader').':';   # ... and context loader
    $processor_key .= $ctx->{locale};                               # ... and locale
    # NOTE: context loader and vhost together imply template path and debug template values

    my $tt = $vhost_processor_cache{$processor_key} || Template->new({
        ENCODING => 'utf-8',
        OUTPUT => ($as_xml) ?  sub { parse_as_xml($r, $ctx, @_); } : $r,
        INCLUDE_PATH => $ctx->{template_paths},
        DEBUG => $ctx->{debug_template},
        (
            $r->dir_config('OILSWebCompiledTemplateCache') ?
                (COMPILE_DIR => $r->dir_config('OILSWebCompiledTemplateCache')) :
                ()
        ),
        (
            ($r->dir_config('OILSWebTemplateStatTTL') =~ /^\d+$/) ?
                (STAT_TTL => $r->dir_config('OILSWebTemplateStatTTL')) :
                ()
        ),
        PLUGINS => {
            EGI18N => 'OpenILS::WWW::EGWeb::I18NFilter',
            CGI_utf8 => 'OpenILS::WWW::EGWeb::CGI_utf8'
        },
        FILTERS => {
            # Register a dynamic filter factory for our locale::maketext generator
            l => [
                sub {
                    my($ctx, @args) = @_;
                    return sub { $text_handler->(shift(), @args); }
                }, 1
            ]
        }
    });

    if (!$tt) {
        $r->log->error("Error creating template processor: $@");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }   

    $vhost_processor_cache{$processor_key} = $tt;
    $ctx->{encode_utf8} = sub {return encode_utf8(shift())};

    unless($tt->process($template, {ctx => $ctx, ENV => \%ENV, l => $text_handler}, $r)) {
        $r->log->warn('egweb: template error: ' . $tt->error);
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    return Apache2::Const::OK;
}

sub set_text_handler {
    my $ctx = shift;
    my $r = shift;

    my $locale = $ctx->{locale};

    $r->log->debug("egweb: messages locale = $locale");

    return sub {
        my $lh = OpenILS::WWW::EGWeb::I18N->get_handle($locale) 
            || OpenILS::WWW::EGWeb::I18N->new;
        return $lh->maketext(@_);
    };
}



sub run_context_loader {
    my $r = shift;
    my $ctx = shift;

    my $stat = Apache2::Const::OK;

    my $loader = $r->dir_config('OILSWebContextLoader');
    return $stat unless $loader;

    eval {
        $loader->use;
        $stat = $loader->new($r, $ctx)->load;
    };

    if($@) {
        $r->log->error("egweb: Context Loader error: $@");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    $r->log->debug("egweb: context loader resulted in status $stat");
    return $stat;
}

sub parse_as_xml {
    my $r = shift;
    my $ctx = shift;
    my $data = shift;

    my $success = 0;

    try { 
        my $doc = XML::LibXML->new->parse_string($data); 
        $data = $doc->documentElement->toStringC14N;
        $data = $ctx->{final_dtd} . "\n" . $data;
        $success = 1;
    } otherwise {
        my $e = shift;
        my $err = "Invalid XML: $e";
        $r->log->error("egweb: $err");
        $r->content_type('text/plain; encoding=utf8');
        $r->print("\n$err\n\n$data");
    };

    $r->print($data) if ($success);
}

sub load_context {
    my $r = shift;
    my $cgi = CGI->new;
    my $ctx = {}; # new context for each page load

    $ctx->{base_path} = $r->dir_config('OILSWebBasePath');
    $ctx->{web_dir} = $r->dir_config('OILSWebWebDir');
    $ctx->{debug_template} = ($r->dir_config('OILSWebDebugTemplate') =~ /true/io) ? 1 : 0;
    $ctx->{hostname} = $r->hostname;
    $ctx->{media_prefix} = $r->dir_config('OILSWebMediaPrefix') || $ctx->{hostname};
    $ctx->{base_url} = $cgi->url(-base => 1);
    $ctx->{skin} = $cgi->cookie(OILS_HTTP_COOKIE_SKIN) || 'default';
    $ctx->{theme} = $cgi->cookie(OILS_HTTP_COOKIE_THEME) || 'default';
    $ctx->{proto} = $cgi->https ? 'https' : 'http';
    $ctx->{ext_proto} = $ctx->{proto};
    my $default_locale = $r->dir_config('OILSWebDefaultLocale') || 'en_us';

    my @template_paths = uniq $r->dir_config->get('OILSWebTemplatePath');
    $ctx->{template_paths} = [ reverse @template_paths ];

    my @locales = $r->dir_config->get('OILSWebLocale');
    load_locale_handlers($ctx, @locales);

    $ctx->{locales} = \%registered_locales;

    # Set a locale cookie if the requested locale is valid
    my $set_locale = $cgi->param('set_eg_locale') || '';
    if (!(grep {$_ eq $set_locale} keys %registered_locales)) {
        $set_locale = '';
    } else {
        my $slc = $cgi->cookie({
            '-name' => OILS_HTTP_COOKIE_LOCALE,
            '-value' => $set_locale,
            '-expires' => '+10y'
        });
        $r->headers_out->add('Set-Cookie' => $slc);
    }

    $ctx->{locale} = $set_locale ||
        $cgi->cookie(OILS_HTTP_COOKIE_LOCALE) || $default_locale ||
        parse_accept_lang($r->headers_in->get('Accept-Language'));

    # set the editor default locale for each page load
    my $ses_locale = parse_eg_locale($ctx->{locale});
    OpenSRF::AppSession->default_locale($ses_locale);
    # give templates access to the en-US style locale
    $ctx->{eg_locale} = $ses_locale;

    my $mprefix = $ctx->{media_prefix};
    if($mprefix and $mprefix !~ /^http/ and $mprefix !~ /^\//) {
        # if a hostname is provided /w no protocol, match the protocol to the current page
        $ctx->{media_prefix} = ($cgi->https) ? "https://$mprefix" : "http://$mprefix";
    }

    return $ctx;
}

# turn Accept-Language into something EG can understand
# TODO: try all langs, not just the first
sub parse_accept_lang {
    my $al = shift;
    return undef unless $al;
    my ($locale) = split(/,/, $al);
    ($locale) = split(/;/, $locale);
    return undef unless $locale;
    $locale =~ s/-/_/og;
    return $locale;
}

# Accept-Language uses locales like 'en', 'fr', 'fr_fr', while Evergreen
# internally uses 'en-US', 'fr-CA', 'fr-FR' (always with the 2 lowercase,
# hyphen, 2 uppercase convention)
sub parse_eg_locale {
    my $ua_locale = shift || 'en_us';

    $ua_locale =~ m/^(..).?(..)?$/;
    my $lang_code = lc($1);
    my $region_code = $2 ? uc($2) : uc($1);
    return "$lang_code-$region_code";
}

# Given a URI, finds the configured template and any extra page 
# arguments (trailing path info).  Any extra data is returned
# as page arguments, in the form of an array, one item per 
# /-separated URI component
sub find_template {
    my $r = shift;
    my $base = shift;
    my $ctx = shift;
    my $path = $r->uri;
    $path =~ s/$base\/?//og;
    my $template = '';
    my $page_args = [];
    my $as_xml = $r->dir_config('OILSWebForceValidXML');
    my $ext = $r->dir_config('OILSWebDefaultTemplateExtension');
    my $at_index = $r->dir_config('OILSWebStopAtIndex');

    $vhost_path_cache{$r->hostname} ||= {};
    my $path_cache = $vhost_path_cache{$r->hostname};

    my @parts = split('/', $path);
    my $localpath = $path;

    if ($localpath =~ m|/css/|) {
        $r->content_type('text/css; encoding=utf8');
    } else {
        $r->content_type('text/html; encoding=utf8');
    }

    my @args;
    while(@parts) {
        last unless $localpath;
        for my $tpath (@{$ctx->{template_paths}}) {
            my $fpath = "$tpath/$localpath.$ext";
            $r->log->debug("egweb: looking at possible template $fpath");
            if ($template = $path_cache->{$fpath}) { # we've checked with -r before...
                next if ($template eq '0E0'); # ... and found nothing
                last;
            } elsif (-r $fpath) { # or, we haven't checked, and if we find a file...
                $path_cache->{$fpath} = $template = "$localpath.$ext"; # ... note it
                last;
            } else { # Nothing there...
                $path_cache->{$fpath} = '0E0'; # ... note that fact
            }
        }
        last if $template and $template ne '0E0';

        if ($at_index) {
            # no matching template was found in the current directory.
            # stop-at-index requested; see if there is an index.ext 
            # file in the same directory instead.
            for my $tpath (@{$ctx->{template_paths}}) {
                # replace the final path component with 'index'
                if ($localpath =~ m|/$|) {
                    $localpath .= 'index';
                } else {
                    $localpath =~ s|/[^/]+$|/index|;
                }
                my $fpath = "$tpath/$localpath.$ext";
                $r->log->debug("egweb: looking at possible template $fpath");
                if ($template = $path_cache->{$fpath}) { # See above block
                    next if ($template eq '0E0');
                    last;
                } elsif (-r $fpath) {
                    $path_cache->{$fpath} = $template = "$localpath.$ext";
                    last;
                } else {
                    $path_cache->{$fpath} = '0E0';
                } 
            }
        }
        last if $template and $template ne '0E0';

        push(@args, pop @parts);
        $localpath = join('/', @parts);
    } 

    $page_args = [@args];

    # no template configured or found
    if(!$template or $template eq '0E0') {
        $r->log->debug("egweb: No template configured for path $path");
        return ();
    }

    $r->log->debug("egweb: template = $template : page args = @$page_args");
    return ($template, $page_args, $as_xml);
}

# Create an I18N sub-module for each supported locale
# Each module creates its own MakeText lexicon by parsing .po/.mo files
sub load_locale_handlers {
    my $ctx = shift;
    my @raw = @_;
    my %locales = (en_us => []);
    while (@raw) {
        my ($l,$file) = (shift(@raw),shift(@raw)); 
        $locales{$l} ||= [];
        push @{$locales{$l}}, $file;
    }

    my $editor = new_editor();
    my @locale_tags = sort { length($a) <=> length($b) } keys %locales;

    for my $idx (0..$#locale_tags) {

        my $tag = $locale_tags[$idx];
        my $parent_tag = 'OpenILS::WWW::EGWeb::I18N';

        my $res = $editor->json_query({
            "from" => [
                "evergreen.get_locale_name",
                $tag
            ]
        });

        my $locale_name = $res->[0]->{"name"} if exists $res->[0]->{"name"};
        next unless $locale_name;

        my $sub_idx = $idx;

        # find the parent locale if possible.  It will be 
        # longest left-anchored substring of the current tag
        while( --$sub_idx >= 0 ) {
            my $ptag = $locale_tags[$sub_idx];
            if( substr($tag, 0, length($ptag)) eq $ptag ) {
                $parent_tag .= "::$ptag";
                last;
            }
        }

        my $eval = <<"        EVAL"; # Dynamic part
            package OpenILS::WWW::EGWeb::I18N::$tag;
            use base '$parent_tag';
        EVAL

        $eval .= <<'        EVAL';
            our %Lexicon;
            if(@{$locales{$tag}}) {
                use Locale::Maketext::Lexicon {
                    _decode => 1
                };
                use Locale::Maketext::Lexicon::Gettext;
                for my $messages (@{$locales{$tag}}) {
                    if(open F, $messages) {
                        %Lexicon = (%Lexicon, %{ Locale::Maketext::Lexicon::Gettext->parse(<F>) });
                        close F;
                    } else {
                        warn "EGWeb: unable to open messages file: $messages"; 
                    }
                }
            }
        EVAL

        eval $eval;

        if ($@) {
            warn "$@\n";
        } else {
            $registered_locales{"$tag"} = $locale_name;
        }
    }
}


# base class for all supported locales
package OpenILS::WWW::EGWeb::I18N;
use base 'Locale::Maketext';
our %Lexicon = (_AUTO => 1);

1;
