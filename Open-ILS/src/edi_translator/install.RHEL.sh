#!/bin/bash
#
# JEDI converter scripts installation
#
# RHEL/CENTOS Install
# note: need older version of rubygems since RHEL package for ruby is old
#
# run this script as root or with sudo

yum install ruby ruby-devel ruby-rdoc

wget http://production.cf.rubygems.org/rubygems/rubygems-1.3.5.tgz
tar zxvf rubygems-1.3.5.tgz
pushd rubygems-1.3.5
ruby setup.rb        # this gives harmless errors about README files missing
gem install rubygems-update
update_rubygems
popd

# RHEL has a bug in json module, but mbklein moved to using yajl for us....
gem install parseconfig rspec edi4r edi4r-tdid rcov openils-mapper # mkmf

