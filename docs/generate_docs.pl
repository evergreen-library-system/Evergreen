#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright © 2020 MOBIUS
# Blake Graham-Henderson <blake@mobiusconsortium.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------


use Getopt::Long;
use Cwd;
use File::Path;
use Data::Dumper;

my $base_url;
my $tmp_space = './build';
my $html_output = './output';
my $antoraui_git = 'git://git.evergreen-ils.org/eg-antora.git';
my $antoraui_git_branch = 'main';
my $antora_version = '3.1.7';
my $help;



GetOptions (
"base-url=s" => \$base_url,
"tmp-space=s" => \$tmp_space,
"html-output=s" => \$html_output,
"antora-ui-repo=s" => \$antoraui_git,
"antora-ui-repo-branch=s" => \$antoraui_git_branch,
"antora-version=s" => \$antora_version,
"help" => \$help
);

sub help
{
    print <<HELP;
    $0
    --base-url http://example.com
    --tmp-space ../../tmp
    --html-output /var/www/html
    --antora-ui-repo git://git.evergreen-ils.org/eg-antora.git
    --antora-version 2.3

    You must specify
    --base-url                                    [URL where html output is expected to be available eg: http//examplesite.org/docs]
    --tmp-space                                   [Writable path for staging the antora UI repo and build files, defaults to ./build]
    --html-output                                 [Path for the generated HTML files, defaults to ./output]
    --antora-ui-repo                              [Antora-UI repository for the built UI, defaults to git://git.evergreen-ils.org/eg-antora.git]
    --antora-ui-repo-branch                       [OPTIONAL: Antora-UI repository checkout branch, Defaults to "main"]
    --antora-version                              [Target version of antora, defaults to 2.3]

HELP
    exit;
}

# Make sure the user supplied ALL of the options
help() if(!$base_url || !$tmp_space || !$html_output || !$antoraui_git || !$antora_version);

# make sure the URL is "right"
$base_url = lc ($base_url);
$base_url =~ s/^[\s\t]*//g;
$base_url =~ s/[\s\t]*$//g;
if ( !($base_url =~ m/^https?:\/\/.+\..+$/))
{
    print "Please specify a proper URL starting with http(s)\n";
    exit;
}


# deal with destination folders
if (-d "$tmp_space/antora-ui") {
    print "cleaning $tmp_space/antora-ui/\n";
    rmtree("$tmp_space/antora-ui/");
}

if (-d "$html_output") {
    print "cleaning $html_output/\n";
    rmtree("$html_output/");
}

# make sure the temp folder is good
mkdir $tmp_space unless ( -d $tmp_space );

# make sure the output folder is good
mkdir $html_output unless ( -d $html_output );

die "Both " . $tmp_space . " and " . $html_output . " must be writable!" unless ( -w $tmp_space && -w $html_output );

# Deal with ui repo
exec_system_cmd("git clone $antoraui_git $tmp_space/antora-ui");

exec_system_cmd("cd $tmp_space/antora-ui && git checkout $antoraui_git_branch");

exec_system_cmd("cd $tmp_space/antora-ui && npm install gulp-cli");

exec_system_cmd("cd $tmp_space/antora-ui && npm install");

exec_system_cmd("cd $tmp_space/antora-ui && ./node_modules/.bin/gulp build && ./node_modules/.bin/gulp pack");


exec_system_cmd("cp site.yml site-working.yml");

# Deal with root URL Antora configuration
rewrite_yml($base_url,"site/url","site-working.yml");
rewrite_yml("$html_output","output/dir","site-working.yml");
rewrite_yml("$tmp_space/antora-ui/build/ui-bundle.zip","ui/bundle/url","site-working.yml");

#npm install antora
exec_system_cmd('npm install antora@' . $antora_version . ' @antora/lunr-extension@^1.0.0-alpha.8');

# Now, finally, let's build the site
exec_system_cmd('DOCSEARCH_INDEX_VERSION=latest NODE_PATH="$(npm root)" ./node_modules/@antora/cli/bin/antora --extension @antora/lunr-extension site-working.yml');

print "Success: your site files are available at " . $html_output . " and can be moved into place for access at " . $base_url . "\n";

sub rewrite_yml
{
    my $replacement = shift;
    my $yml_path = shift;
    my $file = shift;
    my $contents = replace_yml($replacement,$yml_path,$file);
    $contents =~ s/[\n\t]*$//g;
    write_file($file, $contents) if ($contents =~ m/$replacement/);
}

sub write_file
{
    my $file = shift;
    my $contents = shift;

	my $ret=1;
	open(OUTPUT, '> '.$file) or $ret=0;
	binmode(OUTPUT, ":utf8");
	print OUTPUT "$contents\n";
	close(OUTPUT);
	return $ret;
}

sub replace_yml
{
    my $replacement = shift;
    my $yml_path = shift;
    my $file = shift;
    my @path = split(/\//,$yml_path);
    my @lines = @{read_file($file)};
    my $depth = 0;
    my $ret = '';
    while(@lines[0])
    {
        my $line = shift @lines;
        if(@path[0])
        {
            my $preceed_space = $depth * 2;
            my $exp = '\s{'.$preceed_space.'}';
            $exp = '[^\s#]' if $preceed_space == 0;
            # print "testing $exp\n";
            if($line =~ m/^$exp.*/)
            {
                if($line =~ m/^\s*@path[0].*/)
                {
                    $depth++;
                    if(!@path[1])
                    {
                        # print "replacing '$line'\n";
                        my $t = @path[0];
                        $line =~ s/^(.*?$t[^\s]*).*$/\1 $replacement/g;
                        # print "now: '$line'\n";
                    }
                    shift @path;
                }
            }
        }
        $line =~ s/[\n\t]*$//g;
        $ret .= "$line\n";
    }

    return $ret;
}

sub exec_system_cmd
{
    my $cmd = shift;
    print "executing $cmd\n";
    system($cmd) == 0
        or die "system @args failed: $?";
}

sub read_file
{
	my $file = shift;
	my $trys=0;
	my $failed=0;
	my @lines;
	#print "Attempting open\n";
	if(-e $file)
	{
		my $worked = open (inputfile, '< '. $file);
		if(!$worked)
		{
			print "******************Failed to read file*************\n";
		}
        binmode(inputfile, ":utf8");
		while (!(open (inputfile, '< '. $file)) && $trys<100)
		{
			print "Trying again attempt $trys\n";
			$trys++;
			sleep(1);
		}
		if($trys<100)
		{
			#print "Finally worked... now reading\n";
			@lines = <inputfile>;
			close(inputfile);
		}
		else
		{
			print "Attempted $trys times. COULD NOT READ FILE: $file\n";
		}
		close(inputfile);
	}
	else
	{
		print "File does not exist: $file\n";
	}
	return \@lines;
}

exit;
