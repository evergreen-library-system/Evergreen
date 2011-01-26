#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'parseconfig'
require 'stringio'
require 'webrick'
require 'xmlrpc/server'

require 'openils/mapper'
require 'edi/edi2json'
# require 'edi/mapper'

base = File.basename($0, '.rb')

# Defaults
defaults = {
  'port'      => 9191,
  'config'    => "./#{base}.cnf",
  'namespace' => "/EDI",
# 'defcon'    => 0,         # uncomment the 2 decons here, and one in the config file to see the collision/interaction
}

options = {
#  'defcon'    => 3,
}

# Parse command line to override defaults

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-c", "--config [/path/to/file]", "Config file           (default: #{defaults['config']})"   ) do |x|
    options['config'] = x
  end

  opts.on("-n", "--namespace [/web/path]",  "Web request namespace (default: #{defaults['namespace']})") do |x|
    options['namespace'] = x
  end

  opts.on("-p", "--port [PORT]",            "Port number           (default: #{defaults['port']})"     ) do |x|
    options['port'] = x
  end

  opts.on("-v", "--[no-]verbose", "Set verbosity") do |x|
    options['verbose'] = x
  end

  opts.on("-d", "--defaults",   "Show defaults") do |x|
    puts "## Default values:"
    defaults.each { |key, value| printf "%10s = %s\n", key, value }
    exit
  end

  opts.on("-D", "--dumpconfig", "Show effective settings from command-line, config file or defaults") do |x|
    options['dumpconfig'] = x
  end

  opts.on_tail("-h", "--help",  "Show this message") do
    puts opts
    exit
  end

end.parse!

if options['verbose']
  puts "OPTIONS: " ; p options
  puts "Reading config file #{options['config'] || defaults['config']}"
  # puts "\n ARGV: " ; p ARGV
end

# Read config file, then integrate 
c = ParseConfig.new(options['config'] || defaults['config'])
# puts c.methods().sort ; print "\n\n"

keylist = ["host", "port", "config", "namespace", "verbose"] | c.get_params() | defaults.keys | options.keys

for key in keylist
  src =  options.has_key?(key) ? 'command-line' : \
              c.get_value(key) ? 'config file'  : \
        defaults.has_key?(key) ? 'default'      : 'NOWHERE!'

  options[key] ||= c.get_value(key) || defaults[key]
  printf "%10s = %-22s (%12s)\n", key, options[key], src if options['dumpconfig']
end

# after this, all values we care about are in the options hash

# create a servlet to handle XML-RPC requests:
servlet = XMLRPC::WEBrickServlet.new
servlet.add_handler("mapper_version") { OpenILS::Mapper::VERSION }
servlet.add_handler("upper_case") { |a_string| a_string.upcase   }
servlet.add_handler("lower_case") { |a_string| a_string.downcase }
servlet.add_handler("edi2json"  ) { |a_string|
  File.open('/tmp/ruby_edi2json.tmp', 'w') {|f| f.write(a_string) }      # debugging, so we can compare what we rec'd w/ the orig. file
  interchange = StringIO.open(a_string){ |io| EDI::E::Interchange.parse(io) }
  # interchange.header.cS002.d0004 = 'sender'
  # interchange.header.cS003.d0010 = 'recipient'
  interchange.to_json
}
servlet.add_handler("json2edi"  ) { |a_string|
  File.open('/tmp/ruby_json2edi.tmp', 'w') {|f| f.write(a_string) }      # debugging, so we can compare what we rec'd w/ the orig. file
  @map = OpenILS::Mapper.from_json(a_string)
  @map.to_s
}
servlet.add_introspection

# create a WEBrick instance to host the servlets
server = WEBrick::HTTPServer.new(:Port => options['port'])
trap("INT"){ server.shutdown }
server.mount(options['namespace'], servlet)
server.start

