all: clean client
	@echo

client:
	@echo We need the OpenSRF javascript code...
	mkdir math/content/OpenSRF/
	cp ../../src/javascript/*.js math/content/OpenSRF/
	@echo We need a log directory...
	mkdir math/content/log
	touch math/content/log/preserve.directory.when.zipping
	@echo We also need a math/content/conf/client_config.xml pointing to a running OpenSRF Math application.
	@echo Then we package this into a Mozilla XPI file...
	zip -q -r math.xpi install.js math/
	@echo After installing the XPI, use the chrome URL:
	@echo chrome://math/content/

clean:
	@echo Removing the OpenSRF javascript code, the log directory, and math.xpi...
	rm -rf math/content/OpenSRF/ math/content/log math.xpi
