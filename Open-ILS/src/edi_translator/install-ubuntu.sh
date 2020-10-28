#!/bin/bash
# hopefully this is all temporary

UBUNTU_RELEASE=$(lsb_release -sc)
if [ "$UBUNTU_RELEASE" == "xenial" ]; then
    RUBY_VERSION="2.3.0"
elif [ "$UBUNTU_RELEASE" == "bionic" ]; then
    RUBY_VERSION="2.5.0"
else 
    echo "Could not determine your Ubuntu release."
    echo "Please consult $0 and install manually."
    exit 1
fi

# install ruby via APT
sudo apt-get install rubygems-integration ruby-dev

# install gem dependencies
sudo gem install parseconfig rspec edi4r edi4r-tdid json openils-mapper xmlrpc

# clone berick's openils-mapper repo
git clone https://github.com/berick/openils-mapper
cd openils-mapper
# move openils-mapper files into place
git checkout -b GIR-segments-for-copy-data origin/GIR-segments-for-copy-data
sudo cp lib/openils/mapper.rb /var/lib/gems/$RUBY_VERSION/gems/openils-mapper-0.9.9/lib/openils/mapper.rb
sudo cp lib/edi/mapper.rb /var/lib/gems/$RUBY_VERSION/gems/openils-mapper-0.9.9/lib/edi/mapper.rb
