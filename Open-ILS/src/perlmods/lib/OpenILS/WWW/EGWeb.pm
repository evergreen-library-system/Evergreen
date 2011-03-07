package OpenILS::WWW::EGWeb;
use strict; use warnings;
use Template;
use XML::Simple;
use XML::LibXML;
use File::stat;
use Apache2::Const -compile => qw(OK DECLINED HTTP_INTERNAL_SERVER_ERROR);
use Apache2::Log;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::CStoreEditor;

use constant OILS_HTTP_COOKIE_SKIN => 'oils:skin';
use constant OILS_HTTP_COOKIE_THEME => 'oils:theme';
use constant OILS_HTTP_COOKIE_LOCALE => 'oils:locale';

my $web_config;
my $web_config_file;
my $web_config_edit_time;
my %lh_cache; # locale handlers

sub import {
    my $self = shift;
    $web_config_file = shift || '';
    unless(-r $web_config_file) {
        warn "Invalid web config $web_config_file\n";
        return;
    }
    check_web_config();
}


sub handler {
    my $r = shift;
    check_web_config($r); # option to disable this
    my $ctx = load_context($r);
    my $base = $ctx->{base_path};

    $r->content_type('text/html; encoding=utf8');

    my($template, $page_args, $as_xml) = find_template($r, $base, $ctx);
    $ctx->{page_args} = $page_args;

    my $stat = run_context_loader($r, $ctx);

    return $stat unless $stat == Apache2::Const::OK;
    return Apache2::Const::DECLINED unless $template;

    $template = $ctx->{skin} . "/$template";

    my $tt = Template->new({
        OUTPUT => ($as_xml) ?  sub { parse_as_xml($r, $ctx, @_); } : $r,
        INCLUDE_PATH => $ctx->{template_paths},
        DEBUG => $ctx->{debug_template},
        PLUGINS => {
            EGI18N => 'OpenILS::WWW::EGWeb::I18NFilter',
            CGIUTF8 => 'OpenILS::WWW::EGWeb::CGIUTF8'
        }
    });

    unless($tt->process($template, {ctx => $ctx, l => set_text_handler($ctx, $r)})) {
        $r->log->warn('egweb: template error: ' . $tt->error);
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    return Apache2::Const::OK;
}

sub set_text_handler {
    my $ctx = shift;
    my $r = shift;

    my $locale = $ctx->{locale};
    $locale =~ s/-/_/g;

    $r->log->debug("egweb: messages locale = $locale");

    unless($lh_cache{$locale}) {
        $r->log->info("egweb: Unsupported locale: $locale");
        $lh_cache{$locale} = $lh_cache{'en_US'};
    }

    return $OpenILS::WWW::EGWeb::I18NFilter::maketext = 
        sub { return $lh_cache{$locale}->maketext(@_); };
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
    $ctx->{$_} = $web_config->{base_ctx}->{$_} for keys %{$web_config->{base_ctx}};
    $ctx->{hostname} = $r->hostname;
    $ctx->{base_url} = $cgi->url(-base => 1);
    $ctx->{skin} = $cgi->cookie(OILS_HTTP_COOKIE_SKIN) || 'default';
    $ctx->{theme} = $cgi->cookie(OILS_HTTP_COOKIE_THEME) || 'default';

    $ctx->{locale} = 
        $cgi->cookie(OILS_HTTP_COOKIE_LOCALE) || 
        parse_accept_lang($r->headers_in->get('Accept-Language')) || 'en-US';

    my $mprefix = $ctx->{media_prefix};
    if($mprefix and $mprefix !~ /^http/ and $mprefix !~ /^\//) {
        # if a hostname is provided /w no protocol, match the protocol to the current page
        $ctx->{media_prefix} = ($cgi->https) ? "https://$mprefix" : "http://$mprefix";
    }

    return $ctx;
}

# turn Accept-Language into sometihng EG can understand
sub parse_accept_lang {
    my $al = shift;
    return undef unless $al;
    my ($locale) = split(/,/, $al);
    ($locale) = split(/;/, $locale);
    return undef unless $locale;
    $locale =~ s/-(.*)/eval '-'.uc("$1")/e;
    return $locale;
}

# Given a URI, finds the configured template and any extra page 
# arguments (trailing path info).  Any extra data is returned
# as page arguments, in the form of an array, one item per 
# /-separated URI component
sub find_template {
    my $r = shift;
    my $base = shift;
    my $ctx = shift;
    my $skin = $ctx->{skin};
    my $path = $r->uri;
    $path =~ s/$base//og;
    my @parts = split('/', $path);
    my $template = '';
    my $page_args = [];
    my $as_xml = $ctx->{force_valid_xml};
    my $handler = $web_config->{handlers};

    while(@parts) {
        my $part = shift @parts;
        next unless $part;
        my $t = $handler->{$part};
        if(ref($t) eq 'PathConfig') {
            $template = $t->{template};
            $as_xml = ($t->{as_xml} and $t->{as_xml} =~ /true/io) || $as_xml;
            $page_args = [@parts];
            last;
        } else {
            $handler = $t;
        }
    }

    unless($template) { # no template configured

        # see if we can magically find the template based on the path and default extension
        my $ext = $ctx->{default_template_extension};

        my @parts = split('/', $path);
        my $localpath = $path;
        my @args;
        while(@parts) {
            last unless $localpath;
            for my $tpath (@{$ctx->{template_paths}}) {
                my $fpath = "$tpath/$skin/$localpath.$ext";
                $r->log->debug("egweb: looking at possible template $fpath");
                if(-r $fpath) {
                    $template = "$localpath.$ext";
                    last;
                }
            }
            last if $template;
            push(@args, pop @parts);
            $localpath = '/'.join('/', @parts);
        } 

        $page_args = [@args];

        # no template configured or found
        unless($template) {
            $r->log->debug("egweb: No template configured for path $path");
            return ();
        }
    }

    $r->log->debug("egweb: template = $template : page args = @$page_args");
    return ($template, $page_args, $as_xml);
}

# if the web configuration file has never been loaded or has
# changed since the last load, reload it
sub check_web_config {
    my $r = shift;
    my $epoch = stat($web_config_file)->mtime;
    unless($web_config_edit_time and $web_config_edit_time == $epoch) {
        $r->log->debug("egweb: Reloading web config after edit...") if $r;
        $web_config_edit_time = $epoch;
        $web_config = parse_config($web_config_file);
    }
}

# Create an I18N sub-module for each supported locale
# Each module creates its own MakeText lexicon by parsing .po/.mo files
sub load_locale_handlers {
    my $ctx = shift;
    my $locales = $ctx->{locales};

    $locales->{en_US} = {} unless exists $locales->{en_US};

    for my $lang (keys %$locales) {
        my $messages = $locales->{$lang};
        $messages = '' if ref $messages; # empty {}

        # TODO Can we do this without eval?
        my $eval = <<EVAL;
            package OpenILS::WWW::EGWeb::I18N::$lang;
            use base 'OpenILS::WWW::EGWeb::I18N';
            if(\$messages) {
                use Locale::Maketext::Lexicon::Gettext;
                if(open F, '$messages') {
                    our %Lexicon = (%Lexicon, %{ Locale::Maketext::Lexicon::Gettext->parse(<F>) });
                    close F;
                } else {
                    warn "unable to open messages file: $messages"; 
                }
            }
EVAL
        eval $eval;
        warn "$@\n" if $@; # TODO better logging
        $lh_cache{$lang} = "OpenILS::WWW::EGWeb::I18N::$lang"->new;
    }
}



sub parse_config {
    my $cfg_file = shift;
    my $data = XML::Simple->new->XMLin($cfg_file);
    my $ctx = {};
    my $handlers = {};

    $ctx->{media_prefix} = (ref $data->{media_prefix}) ? '' : $data->{media_prefix};
    $ctx->{base_path} = (ref $data->{base_path}) ? '' : $data->{base_path};
    $ctx->{template_paths} = [];
    $ctx->{force_valid_xml} = ( ($data->{force_valid_xml}||'') =~ /true/io) ? 1 : 0;
    $ctx->{debug_template} = ( ($data->{debug_template}||'')  =~ /true/io) ? 1 : 0;
    $ctx->{default_template_extension} = $data->{default_template_extension} || 'tt2';
    $ctx->{web_dir} = $data->{web_dir};
    $ctx->{locales} = $data->{locales};
    load_locale_handlers($ctx);

    my $tpaths = $data->{template_paths}->{path};
    $tpaths = [$tpaths] unless ref $tpaths;
    push(@{$ctx->{template_paths}}, $_) for @$tpaths;

    for my $handler (@{$data->{handlers}->{handler}}) {
        my @parts = split('/', $handler->{path});
        my $h = $handlers;
        my $pcount = scalar(@parts);
        for(my $i = 0; $i < $pcount; $i++) {
            my $p = $parts[$i];
            unless(defined $h->{$p}) {
                if($i == $pcount - 1) {
                    $h->{$p} = PathConfig->new(%$handler);
                    last;
                } else {
                    $h->{$p} = {};
                }
            }
            $h = $h->{$p};
        }
    }

    return {base_ctx => $ctx, handlers => $handlers};
}

package PathConfig;
sub new {
    my($class, %args) = @_;
    return bless(\%args, $class);
}

# base class for all supported locales
package OpenILS::WWW::EGWeb::I18N;
use base 'Locale::Maketext';
our %Lexicon = (_AUTO => 1);

1;
