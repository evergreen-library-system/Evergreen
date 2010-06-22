#!/bin/bash
#
# Author: Joe Atzberger
#
# This script will update your git-svn repository from the 
# SVN source repo and push to a github remote (if one exists).
#
# The design is (somewhat) suitable for cronjob because it:
#   ~ only updates the local "master" branch
#   ~ dies if it cannot switch to "master"
#   ~ switches back to whatever branch was current initially
#
# However, it will fail if you cannot switch branches, (i.e. 
# have a lot of uncommited changes).  
#
# WARNING: you should NOT run this in crontab on a repo you
# are actively developing since switching branches (even
# momentarily) in the middle of editing or runtime could
# seriously confuse any developer.  Instead, just run it 
# manually as needed.
#
# Workflow might look like:
#   git checkout -b my_feature
#   [ edit, edit, edit ]
#   git commit -a
#   ./build/tools/update_git_svn.sh
#   git rebase master
#   git push github my_feature
#

function die_msg {
    echo "ERROR at $1" >&2;
    exit;
}
function parse_git_branch {
    ref=$(git-symbolic-ref HEAD 2> /dev/null) || return;
    ref=${ref#refs/heads/};
    # echo "REF2: $ref";
}


parse_git_branch;
BRANCH=$ref;

echo "Current branch: $BRANCH";

git svn fetch  || die_msg 'git svn fetch';
# git status     || die_msg 'git status';
git checkout master  || die_msg 'git checkout master';

MESSAGE='';
git svn rebase  || MESSAGE="ERROR at git svn rebase;  ";
git checkout $BRANCH  || die_msg "${MESSAGE}git checkout $BRANCH";
git push github master;

