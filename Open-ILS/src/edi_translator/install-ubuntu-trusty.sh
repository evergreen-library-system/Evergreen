#!/bin/bash
# hopefully this is all temporary

# install ruby via APT
sudo apt-get install rubygems-integration ruby-dev

# install gem dependencies
sudo gem install parseconfig rspec edi4r edi4r-tdid json openils-mapper

# clone berick's openils-mapper repo
git clone https://github.com/berick/openils-mapper
cd openils-mapper
# move openils-mapper files into place
git checkout -b GIR-segments-for-copy-data origin/GIR-segments-for-copy-data
sudo cp lib/openils/mapper.rb /var/lib/gems/1.9.1/gems/openils-mapper-0.9.9/lib/openils/mapper.rb
sudo cp lib/edi/mapper.rb /var/lib/gems/1.9.1/gems/openils-mapper-0.9.9/lib/edi/mapper.rb
