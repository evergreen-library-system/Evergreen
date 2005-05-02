# TOP level 'src' makefile for OpenSRF
#
#


all: prep router srfsh gateway

prep:
	if [ ! -d ../lib ];then mkdir ../lib; fi;

install: 
	make -C srfsh install
	make -C router install

transport:
	make -C libtransport

json: 
	make -C libjson

stack: json transport
	make -C libstack

router: stack  
	make -C router

srfsh: stack
	make -C srfsh

gateway: stack
	make -C gateway


clean:
	make -C libtransport clean
	make -C libjson clean
	make -C libstack clean
	make -C router clean
	make -C gateway clean
