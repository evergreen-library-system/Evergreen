#include "jserver-c.h"
#include <signal.h>
#include <fcntl.h>

/* config vars */
jserver* js					= NULL;
int		port				= -1;
char*		unix_sock_file = NULL;
int		log_level		= -1;
char*		log_file			= NULL;

/* starts the logging and server processes */
void launch_server();


/* shut down, clean up, and restart */
void sig_hup_handler( int a ) { 
	warning_handler(" +++ Re-launching server for SIGHUP");

	log_free();
	jserver_free(js);
	unlink(unix_sock_file);

	launch_server();
	return; 
}

/* die gracefully */
void sig_int_handler( int a ) { 
	warning_handler(" +++ Shutting down because of user signal");
	log_free();
	jserver_free(js);
	unlink(unix_sock_file);
	exit(0); 
}



/* loads the command line settings and launches the server */
int main(int argc, char* argv[]) {

	signal(SIGHUP, &sig_hup_handler);
	signal(SIGINT, &sig_int_handler);
	signal(SIGTERM, &sig_int_handler);

	char* prog			= argv[0];
	char* sport			= argv[1];	
	unix_sock_file		= argv[2];	
	char* slog_level	= argv[3];
	log_file				= argv[4];

	if(!sport || !unix_sock_file || !slog_level) {
		fprintf(stderr, 
			"usage: %s <port> <path_to_unix_sock_file> <log_level [1-4]"
			"(4 is the highest)> [log_file (optional, goes to stderr otherwise)]\n"
			"e.g: %s 5222 /tmp/server.sock 1 /tmp/server.log\n",
			prog, prog);
		return 99;
	}

	port			= atoi(sport);
	log_level	= atoi(slog_level);

	if(port < 1) {
		warning_handler("invalid port (%d), falling back to 5222");
		port = 5222;
	}

	if(log_level < 1 || log_level > 4) {
		warning_handler("log level (%d) is not recognized, falling back to WARN", log_level);
		log_level = 2;
	}

	fprintf(stderr, "Launching with port %d, unix sock %s, log level %d, log file %s\n",
			port, unix_sock_file, log_level, log_file );

	launch_server();
	return 0;
}

void launch_server() {

	log_init(log_level, log_file);
	info_handler("Booting jserver-c on port %d and "
			"sock file %s", port, unix_sock_file);

	js = jserver_init();
	unlink(unix_sock_file);
	if(jserver_connect(js, port, unix_sock_file) < 0)
		fatal_handler("Could not connect...");

	jserver_wait(js);
}





