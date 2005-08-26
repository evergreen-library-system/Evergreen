#include <stdio.h>
#include "logging.h"

void get_timestamp( char buf_36chars[]) {

	struct timeb tb;
	ftime(&tb);
	char* localtime = strdup( ctime( &(tb.time) ) );
	char mil[4];
	memset(mil,0,4);
	sprintf(mil," (%d)",tb.millitm);
	strcpy( buf_36chars, localtime );
	buf_36chars[ strlen(localtime)-1] = '\0'; // remove newline
	strcat(buf_36chars,mil);
	free(localtime);
}

static char* lf = NULL;
static int log_level = -1;
static int logging = 0;

void log_free() { if( lf != NULL ) free(lf); }

int fatal_handler( char* msg, ... ) {

	FILE * log_file;

	char buf[36];
	memset( buf, 0, 36 );
	get_timestamp( buf );
	pid_t  pid = getpid();
	va_list args;

	if( logging ) {
		if( log_level < LOG_ERROR )
			return -1;

		log_file = fopen( lf, "a" );
		if( log_file == NULL ) {
			perror( "Unable to open log file for appending\n" );
		} else {

			fprintf( log_file, "[%s %d] [%s] ", buf, pid, "ERR " );
	
			va_start(args, msg);
			vfprintf(log_file, msg, args);
			va_end(args);
	
			fprintf(log_file, "\n");
			fflush( log_file );

			fclose(log_file);
		}
	}
	
	/* also log to stderr  for ERRORS*/
	fprintf( stderr, "[%s %d] [%s] ", buf, pid, "ERR " );
	va_start(args, msg);
	vfprintf(stderr, msg, args);
	va_end(args);
	fprintf( stderr, "\n" );

	exit(99);
	return -1; /* for consistency */
}

int warning_handler( char* msg, ... ) {

	FILE * log_file;

	char buf[36];
	memset( buf, 0, 36 );
	get_timestamp( buf );
	pid_t  pid = getpid();
	va_list args;
	
	if( log_level < LOG_WARNING )
		return -1;

	if(logging) {

		log_file = fopen( lf, "a" );
		if( log_file == NULL ) {
			perror( "Unable to open log file for appending\n" );
			fprintf( stderr, "[%s %d] [%s] ", buf, pid, "WARN" );
			va_start(args, msg);
			vfprintf(stderr, msg, args);
			va_end(args);
			fprintf( stderr, "\n" );
		} else {

			fprintf( log_file, "[%s %d] [%s] ", buf, pid, "WARN" );
	
			va_start(args, msg);
			vfprintf(log_file, msg, args);
			va_end(args);
	
			fprintf(log_file, "\n");
			fflush( log_file );

			fclose(log_file);
		}
	} else {

		fprintf( stderr, "[%s %d] [%s] ", buf, pid, "WARN" );
		va_start(args, msg);
		vfprintf(stderr, msg, args);
		va_end(args);
		fprintf( stderr, "\n" );
	}

	return -1;
}

int info_handler( char* msg, ... ) {

	FILE * log_file;

	char buf[36];
	memset( buf, 0, 36 );
	get_timestamp( buf );
	pid_t  pid = getpid();
	va_list args;

	if( log_level < LOG_INFO )
		return -1;

	if(logging) {

		log_file = fopen( lf, "a" );
		if( log_file == NULL ) {
			perror( "Unable to open log file for appending\n" );
			fprintf( stderr, "[%s %d] [%s] ", buf, pid, "INFO" );
			va_start(args, msg);
			vfprintf(stderr, msg, args);
			va_end(args);
			fprintf( stderr, "\n" );
			fflush(stderr);
		} else {

			fprintf( log_file, "[%s %d] [%s] ", buf, pid, "INFO" );

			va_start(args, msg);
			vfprintf(log_file, msg, args);
			va_end(args);
	
			fprintf(log_file, "\n");
			fflush( log_file );
			fclose(log_file);
		}
	} else {

		fprintf( stderr, "[%s %d] [%s] ", buf, pid, "INFO" );
		va_start(args, msg);
		vfprintf(stderr, msg, args);
		va_end(args);
		fprintf( stderr, "\n" );
		fflush(stderr);

	}
	return -1;
}


int debug_handler( char* msg, ... ) {

	FILE * log_file;

	char buf[36];
	memset( buf, 0, 36 );
	get_timestamp( buf );
	pid_t  pid = getpid();
	va_list args;
	
	if( log_level < LOG_DEBUG )
		return -1;

	if(logging) {

		log_file = fopen( lf, "a" );
		if( log_file == NULL ) {
			perror( "Unable to open log file for appending\n" );
			fprintf( stderr, "[%s %d] [%s] ", buf, pid, "DEBG" );
			va_start(args, msg);
			vfprintf(stderr, msg, args);
			va_end(args);
			fprintf( stderr, "\n" );
		} else {
			fprintf( log_file, "[%s %d] [%s] ", buf, pid, "DEBG" );
	
			va_start(args, msg);
			vfprintf(log_file, msg, args);
			va_end(args);
	
			fprintf(log_file, "\n");
			fflush( log_file );
		
			fclose(log_file);
		}
	} else {

		fprintf( stderr, "[%s %d] [%s] ", buf, pid, "DEBG" );
		va_start(args, msg);
		vfprintf(stderr, msg, args);
		va_end(args);
		fprintf( stderr, "\n" );
	}

	return -1;
}


int log_init( int llevel, char* lfile ) {


	if( llevel < 1 ) {
		logging = 0;
		return 0;
	}

	/* log to stderr */
	if(lfile == NULL) return 0;

	log_level = llevel;
	lf = strdup(lfile);

	logging = 1;
	return 1;

}


