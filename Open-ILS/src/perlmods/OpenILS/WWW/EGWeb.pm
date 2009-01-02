package OpenILS::WWW::EGWeb;
use strict; use warnings;
use Template;
use XML::Simple;
use File::stat;
use Apache2::Const -compile => qw(OK DECLINED HTTP_INTERNAL_SERVER_ERROR);
use Apache2::Log;

use constant OILS_HTTP_COOKIE_SKIN => 'oils:skin';
use constant OILS_HTTP_COOKIE_THEME => 'oils:theme';
use constant OILS_HTTP_COOKIE_LOCALE => 'oils:locale';

my $web_config;
my $web_config_file;
my $web_config_edit_time;

sub import {
    my $self = shift;
    $web_config_file = shift;
    unless(-r $web_config_file) {
        warn "Invalid web config $web_config_file";
        return;
    }
    check_web_config();
}


sub handler {
    my $r = shift;
    check_web_config($r); # option to disable this
    my $ctx = load_context($r);
    my $base = $ctx->{base_uri};
    my($template, $page_args) = find_template($r, $base, $ctx);
    return Apache2::Const::DECLINED unless $template;

    $template = $ctx->{skin} . "/$template";
    $ctx->{page_args} = $page_args;
    $r->content_type('text/html; encoding=utf8');

    my $tt = Template->new({
        OUTPUT => ($ctx->{force_valid_xml}) ? sub { validate_as_xml($r, @_); } : $r,
        INCLUDE_PATH => $ctx->{template_paths},
    });

    unless($tt->process($template, {ctx => $ctx})) {
        $r->log->warn('Template error: ' . $tt->error);
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    return Apache2::Const::OK;
}

sub validate_as_xml {
    my $r = shift;
    my $data = shift;
    eval { XML::Simple->new->XMLin($data); };
    if($@) {
        my $err = "Invalid XML: $@";
        $r->log->error($err);
        $r->content_type('text/plain; encoding=utf8');
        $r->print("\n$err\n\n$data");
    } else {
        $r->print($data);
    }
}


sub load_context {
    my $r = shift;
    my $cgi = CGI->new;
    my $ctx = $web_config->{ctx};
    $ctx->{skin} = $cgi->cookie(OILS_HTTP_COOKIE_SKIN) || 'default';
    $ctx->{theme} = $cgi->cookie(OILS_HTTP_COOKIE_THEME) || 'default';
    $ctx->{locale} = 
        $r->headers_in->get('Accept-Language') || # this will need some trimming
        $cgi->cookie(OILS_HTTP_COOKIE_LOCALE) || 'en-US';
    $r->log->debug('skin = ' . $ctx->{skin} . ' : theme = ' . 
        $ctx->{theme} . ' : locale = ' . $ctx->{locale});
    return $ctx;
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
    my $handler = $web_config->{handlers};
    while(@parts) {
        my $part = shift @parts;
        next unless $part;
        my $t = $handler->{$part};
        if(ref $t) {
            $handler = $t;
        } else {
            $template = $t;
            $page_args = [@parts];
            last;
        }
    }

    unless($template) { # no template configured

        # see if we can magically find the template based on the path and default extension
        my $ext = $ctx->{default_template_extension};
        for my $tpath (@{$ctx->{template_paths}}) {
            my $fpath = "$tpath/$skin/$path.$ext";
            $r->log->debug("looking at possible template $fpath");
            if(-r $fpath) {
                $template = "$path.$ext";
                last;
            }
        }

        # no template configured or found
        unless($template) {
            $r->log->warn("No template configured for path $path");
            return ();
        }
    }

    $r->log->debug("template = $template : page args = @$page_args");
    return ($template, $page_args);
}

# if the web configuration file has never been loaded or has
# changed since the last load, reload it
sub check_web_config {
    my $r = shift;
    my $epoch = stat($web_config_file)->mtime;
    unless($web_config_edit_time and $web_config_edit_time == $epoch) {
        $r->log->debug("Reloading web config after edit...") if $r;
        $web_config_edit_time = $epoch;
        $web_config = parse_config($web_config_file);
    }
}

sub parse_config {
    my $cfg_file = shift;
    my $data = XML::Simple->new->XMLin($cfg_file);
    my $ctx = {};
    my $handlers = {};

    $ctx->{media_prefix} = (ref $data->{media_prefix}) ? '' : $data->{media_prefix};
    $ctx->{base_uri} = (ref $data->{base_uri}) ? '' : $data->{base_uri};
    $ctx->{template_paths} = [];
    $ctx->{force_valid_xml} = ($data->{force_valid_xml} =~ /true/io) ? 1 : 0;
    $ctx->{default_template_extension} = $data->{default_template_extension} || 'tt2';

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
                    $h->{$p} = $handler->{template};
                    last;
                } else {
                    $h->{$p} = {};
                }
            }
            $h = $h->{$p};
        }
    }

    return {ctx => $ctx, handlers => $handlers};
}


1;
