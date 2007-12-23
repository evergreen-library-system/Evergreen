# vim:noet:ts=4

install: python-install

python-build:
	@echo $@
	python setup.py build

python-install:
	@echo $@
	python setup.py install

clean:
	@echo $@
	rm -fr build
	find . -name "*.pyc" -exec rm -f {} \;
