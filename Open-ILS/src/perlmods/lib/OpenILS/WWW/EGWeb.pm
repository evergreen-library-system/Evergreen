package OpenILS::WWW::EGWeb;
use strict; use warnings;
use Template;
use XML::Simple;
use XML::LibXML;
use File::stat;
use Encode;
use Apache2::Const -compile => qw(OK DECLINED HTTP_INTERNAL_SERVER_ERROR);
use Apache2::Log;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::CStoreEditor q/:funcs/;
use List::MoreUtils qw/uniq/;

use constant OILS_HTTP_COOKIE_SKIN => 'eg_skin';
use constant OILS_HTTP_COOKIE_THEME => 'eg_theme';
use constant OILS_HTTP_COOKIE_LOCALE => 'eg_locale';

# cache string bundles
my %registered_locales;

sub handler {
    my $r = shift;
    my $ctx = load_context($r);
    my $base = $ctx->{base_path};

    my($template, $page_args, $as_xml) = find_template($r, $base, $ctx);
    $ctx->{page_args} = $page_args;

    my $stat = run_context_loader($r, $ctx);

    return $stat unless $stat == Apache2::Const::OK;
    return Apache2::Const::DECLINED unless $template;

    my $text_handler = set_text_handler($ctx, $r);

    my $tt = Template->new({
        ENCODING => 'utf-8',
        OUTPUT => ($as_xml) ?  sub { parse_as_xml($r, $ctx, @_); } : $r,
        INCLUDE_PATH => $ctx->{template_paths},
        DEBUG => $ctx->{debug_template},
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

    $ctx->{encode_utf8} = sub {return encode_utf8(shift())};

    unless($tt->process($template, {ctx => $ctx, ENV => \%ENV, l => $text_handler})) {
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
        my $lh = OpenILS::WWW::EGWeb::I18N->get_handle($locale);
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
    $ctx->{debug_template} = ($r->dir_config('OILSWebDebugTemplate') =~ /true/io);
    $ctx->{media_prefix} = $r->dir_config('OILSWebMediaPrefix');
    $ctx->{hostname} = $r->hostname;
    $ctx->{base_url} = $cgi->url(-base => 1);
    $ctx->{skin} = $cgi->cookie(OILS_HTTP_COOKIE_SKIN) || 'default';
    $ctx->{theme} = $cgi->cookie(OILS_HTTP_COOKIE_THEME) || 'default';
    $ctx->{proto} = $cgi->https ? 'https' : 'http';

    my @template_paths = uniq $r->dir_config->get('OILSWebTemplatePath');
    $ctx->{template_paths} = [ reverse @template_paths ];

    my %locales = $r->dir_config->get('OILSWebLocale');
    load_locale_handlers($ctx, %locales);

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
        $cgi->cookie(OILS_HTTP_COOKIE_LOCALE) || 
        parse_accept_lang($r->headers_in->get('Accept-Language')) || 'en_us';

    my $mprefix = $ctx->{media_prefix};
    if($mprefix and $mprefix !~ /^http/ and $mprefix !~ /^\//) {
        # if a hostname is provided /w no protocol, match the protocol to the current page
        $ctx->{media_prefix} = ($cgi->https) ? "https://$mprefix" : "http://$mprefix";
    }

    return $ctx;
}

# turn Accept-Language into sometihng EG can understand
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

    my @parts = split('/', $path);
    my $localpath = $path;

    if ($localpath =~ m|opac/css|) {
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
            if(-r $fpath) {
                $template = "$localpath.$ext";
                last;
            }
        }
        last if $template;
        push(@args, pop @parts);
        $localpath = join('/', @parts);
    } 

    $page_args = [@args];

    # no template configured or found
    unless($template) {
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
    my %locales = @_;

    my $editor = new_editor();
    my @locale_tags = sort { length($a) <=> length($b) } keys %locales;

    # always fall back to en_us, the assumed template language
    push(@locale_tags, 'en_us');

    for my $idx (0..$#locale_tags) {

        my $tag = $locale_tags[$idx];
        next if grep { $_ eq $tag } keys %registered_locales;

        my $res = $editor->json_query({
            "from" => [
                "evergreen.get_locale_name",
                $tag
            ]
        });

        my $locale_name = $res->[0]->{"name"} if exists $res->[0]->{"name"};
        next unless $locale_name;

        my $parent_tag = '';
        my $sub_idx = $idx;

        # find the parent locale if possible.  It will be 
        # longest left-anchored substring of the current tag
        while( --$sub_idx >= 0 ) {
            my $ptag = $locale_tags[$sub_idx];
            if( substr($tag, 0, length($ptag)) eq $ptag ) {
                $parent_tag = "::$ptag";
                last;
            }
        }

        my $messages = $locales{$tag} || '';

        # TODO Can we do this without eval?
        my $eval = <<"        EVAL";
            package OpenILS::WWW::EGWeb::I18N::$tag;
            use base 'OpenILS::WWW::EGWeb::I18N$parent_tag';
            if(\$messages) {
                use Locale::Maketext::Lexicon {
                    _decode => 1
                };
                use Locale::Maketext::Lexicon::Gettext;
                if(open F, '$messages') {
                    our %Lexicon = (%Lexicon, %{ Locale::Maketext::Lexicon::Gettext->parse(<F>) });
                    close F;
                } else {
                    warn "EGWeb: unable to open messages file: $messages"; 
                }
            }
        EVAL
        eval $eval;

        if ($@) {
            warn "$@\n" if $@;
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
