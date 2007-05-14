#!/usr/bin/python2.4
import os, sys, time, readline, atexit, re
from string import *
from osrf.system import osrfConnect
from osrf.json import *
from osrf.ses import osrfClientSession
from osrf.conf import osrfConfigValue
import osrf.ex

prompt = "\033[01;32msrfsh\033[01;34m% \033[00m"
last_response = None
commands = {}


def register_command(name, callback):
    commands[name] = callback
    

# -------------------------------------------------------------------
# main listen loop
# -------------------------------------------------------------------
"""
def do_loop():
    while True:

        try:
            line = raw_input(prompt+'')
            if not len(line): 
                continue
            if lower(line) == 'exit' or lower(line) == 'quit': 
                break
            parts = split(line)

            command = parts.pop(0)
        
            if command == 'request':
                handle_request(parts)
                continue

            if command == 'math_bench':
                handle_math_bench(parts)
                continue

            if command == 'help':
                handle_help()
                continue

            if command == 'set':
                handle_set(parts)

            if command == 'get':
                handle_get(parts)

            if command == 'eval':
                handle_eval(parts)



        except KeyboardInterrupt:
            print ""

        except EOFError:
            print "exiting..."
            sys.exit(0)
"""


# -------------------------------------------------------------------
# Set env variables to control behavior
# -------------------------------------------------------------------
def handle_set(parts):
    m = re.compile('(.*)=(.*)').match(parts[0])
    key = m.group(1)
    val = m.group(2)
    set_var(key, val)
    print "%s = %s" % (key, val)

def handle_get(parts):
    try:
        print get_var(parts[0])
    except:
        print ""

def handle_eval(parts):
    com = ' '.join(parts)
    try:
        print eval(com)
    except Exception, e:
        print "EVAL failed: " + str(e)

# -------------------------------------------------------------------
# Prints help info
# -------------------------------------------------------------------
def handle_help():
    print """
  help
    - show this menu

  math_bench <count>
    - runs <count> opensrf.math requests and reports the average time

  request <service> <method> [<param1>, <param2>, ...]
    - performs an opensrf request

  eval <command>
    - evals the requested command within the srfsh environment
    - special variables:
      - last_response - last item received from a network call

  set VAR=<value>
    - sets an environment variable

  Environment variables:
    SRFSH_OUTPUT = pretty - print pretty JSON and key/value pairs for network objects
                 = raw - print formatted JSON 
    """

        


# -------------------------------------------------------------------
# performs an opesnrf request
# -------------------------------------------------------------------
def handle_request(parts):
    service = parts.pop(0)
    method = parts.pop(0)
    jstr = '[%s]' % join(parts)
    params = None
    global last_response

    try:
        params = osrfJSONToObject(jstr)
    except:
        print "Error parsing JSON: %s" % jstr
        return

    otp = get_var('SRFSH_OUTPUT')

    ses = osrfClientSession(service)

    end = None
    start = time.time()
    req = ses.request2(method, tuple(params))


    while True:

        resp = None

        try:
            resp = req.recv(timeout=120)
        except Exception, e:
            print "\nThere was a problem running your request:\n\n%s\n" % str(e)
            return

        if not end:
            total = time.time() - start
        if not resp: break

        if otp == 'pretty':
            print osrfDebugNetworkObject(resp.content())
        else:
            print osrfFormatJSON(osrfObjectToJSON(resp.content()))
        last_response = resp.content()

    req.cleanup()
    ses.cleanup()

    print '-'*60
    print "Total request time: %f" % total
    print '-'*60


def handle_math_bench(parts):

    count = int(parts.pop(0))
    ses = osrfClientSession('opensrf.math')
    times = []

    for i in range(100):
        if i % 10: sys.stdout.write('.')
        else: sys.stdout.write( str( i / 10 ) )
    print "";


    for i in range(count):
    
        starttime = time.time()
        req = ses.request('add', 1, 2)
        resp = req.recv(timeout=2)
        endtime = time.time()
    
        if resp.content() == 3:
            sys.stdout.write("+")
            sys.stdout.flush()
            times.append( endtime - starttime )
        else:
            print "What happened? %s" % str(resp.content())
    
        req.cleanup()
        if not ( (i+1) % 100):
            print ' [%d]' % (i+1)
    
    ses.cleanup()
    total = 0
    for i in times: total += i
    print "\naverage time %f" % (total / len(times))




# -------------------------------------------------------------------
# Defines the tab-completion handling and sets up the readline history 
# -------------------------------------------------------------------
def setup_readline():
    class SrfshCompleter(object):
        def __init__(self, words):
            self.words = words
            self.prefix = None
    
        def complete(self, prefix, index):
            if prefix != self.prefix:
                # find all words that start with this prefix
                self.matching_words = [
                    w for w in self.words if w.startswith(prefix)
                ]
                self.prefix = prefix
                try:
                    return self.matching_words[index]
                except IndexError:
                    return None
    
    words = 'request', 'help', 'exit', 'quit', 'opensrf.settings', 'opensrf.math', 'set'
    completer = SrfshCompleter(words)
    readline.parse_and_bind("tab: complete")
    readline.set_completer(completer.complete)

    histfile = os.path.join(get_var('HOME'), ".srfsh_history")
    try:
        readline.read_history_file(histfile)
    except IOError:
        pass
    atexit.register(readline.write_history_file, histfile)

def do_connect():
    file = os.path.join(get_var('HOME'), ".srfsh.xml")

    print_green("Connecting to opensrf...")
    osrfConnect(file)
    print_red('OK')
    print ''

def load_plugins():
    # Load the user defined external plugins
    # XXX Make this a real module interface, with tab-complete words, commands, etc.
    plugins = osrfConfigValue('plugins')
    plugins = osrfConfigValue('plugins.plugin')
    if not isinstance(plugins, list):
        plugins = [plugins]

    for module in plugins:
        name = module['module']
        init = module['init']
        print_green("Loading module %s..." % name)

        try:
            str = 'from %s import %s\n%s()' % (name, init, init)
            exec(str)
            print_red('OK')
            print ''

        except Exception, e:
            sys.stderr.write("\nError importing plugin %s, with init symbol %s: \n%s\n" % (name, init, e))

def set_vars():
    if not get_var('SRFSH_OUTPUT'):
        set_var('SRFSH_OUTPUT', 'pretty')


def set_var(key, val):
    os.environ[key] = val


def get_var(key):
    try: return os.environ[key]
    except: return ''
    
    
def print_green(str):
    sys.stdout.write("\033[01;32m")
    sys.stdout.write(str)
    sys.stdout.write("\033[00m")
    #sys.stdout.flush()

def print_red(str):
    sys.stdout.write("\033[01;31m")
    sys.stdout.write(str)
    sys.stdout.write("\033[00m")
    #sys.stdout.flush()

def print_purple(str):
    sys.stdout.write("\033[01;34m")
    sys.stdout.write(str)
    sys.stdout.write("\033[00m")
    #sys.stdout.flush()







# -------------------------------------------------------------------
# main listen loop
# -------------------------------------------------------------------
def do_loop():
    while True:

        try:
            line = raw_input(prompt+'')
            if not len(line): 
                continue
            if lower(line) == 'exit' or lower(line) == 'quit': 
                break
            parts = split(line)

            command = parts.pop(0)
        
            if command == 'request':
                handle_request(parts)
                continue

            if command == 'math_bench':
                handle_math_bench(parts)
                continue

            if command == 'help':
                handle_help()
                continue

            if command == 'set':
                handle_set(parts)

            if command == 'get':
                handle_get(parts)

            if command == 'eval':
                handle_eval(parts)



        except KeyboardInterrupt:
            print ""

        except EOFError:
            print "exiting..."
            sys.exit(0)







# Kick it off
set_vars()
setup_readline()
do_connect()
load_plugins()
do_loop()



