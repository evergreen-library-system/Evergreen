# TOP level 'src' makefile for OpenSRF


all: router


transport:
	make -C libtransport

json: 
	make -C libjson

stack: json transport
	make -C libstack

router: stack  
	make -C router


clean:
	make -C libtransport clean
	make -C libjson clean
	make -C libstack clean
	make -C router clean
