#include "jserver-c.h"
#include <signal.h>
#include <fcntl.h>

/* config vars */
jserver* js					= NULL;
int		port				= -1;
char*		unix_sock_file = NULL;
int		log_level		= -1;
char*		log_file			= NULL;
char* 	listen_ip		= NULL;

/* starts the logging and server processes */
void launch_server();


/* shut down, clean up, and restart */
void sig_hup_handler( int a ) { 
	warning_handler(" +++ Re-launching server for SIGHUP");

	jserver_free(js);
	log_free();
	unlink(unix_sock_file);

	launch_server();
	return; 
}

/* die gracefully */
void sig_int_handler( int a ) { 
	warning_handler(" +++ Shutting down because of user signal");
	jserver_free(js);
	log_free();
	unlink(unix_sock_file);
	exit(0); 
}



/* loads the command line settings and launches the server */
int main(int argc, char* argv[]) {

	char* prog			= argv[0];
	char* sport			= argv[1];	
	listen_ip			= argv[2];
	unix_sock_file		= argv[3];	
	char* slog_level	= argv[4];
	log_file				= argv[5];

	if(!sport || !unix_sock_file || !slog_level) {
		fprintf(stderr, 
			"usage: %s <port> <listen_ip> <path_to_unix_sock_file> <log_level [1-4]"
			"(4 is the highest)> [log_file (optional, goes to stderr otherwise)]\n"
			"e.g: %s 5222 10.0.0.100 /tmp/server.sock 1 /tmp/server.log\n"
			"if listen_ip is '*', then we will listen on all addresses",
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

	if (daemonize() == -1) {
		fprintf(stderr, "!!! Error forking the daemon!  Going away now... :(\n");
		exit(2);
	}

	signal(SIGHUP, &sig_hup_handler);
	signal(SIGINT, &sig_int_handler);
	signal(SIGTERM, &sig_int_handler);

	//init_proc_title( argc, argv );
	//set_proc_title( "opensrf jabber" );

	launch_server();
	return 0;
}

void launch_server() {

	log_init(log_level, log_file);
	info_handler("Booting jserver-c on port %d and "
			"sock file %s", port, unix_sock_file);

	if(!strcmp(listen_ip,"*")) listen_ip = NULL;

	js = jserver_init();
	unlink(unix_sock_file);
	if(jserver_connect(js, port, listen_ip, unix_sock_file) < 0)
		fatal_handler("Could not connect...");

	jserver_wait(js);
}





