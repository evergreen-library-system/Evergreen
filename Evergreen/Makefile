# ------------------------------------------------------------------------
# Evergreen makefile
# ------------------------------------------------------------------------

IMAGE=$(WEBDIR)/images

all:	xul 


install:	images-install circ-install

xul:
	make -C staff_client

images-install:
	@echo "Installing images to $(IMAGE)";
	cp -r images $(WEBDIR)
	ln -sf $(IMAGE)/map.jpg $(IMAGE)/cartographic.jpg
	ln -sf $(IMAGE)/bigpinesLogo.jpg $(IMAGE)/main_logo.jpg
	ln -sf $(IMAGE)/open_book.gif $(IMAGE)/"mixed material.jpg"
	ln -sf $(IMAGE)/movie.jpg $(IMAGE)/"moving image.jpg"
	ln -sf $(IMAGE)/music_icon.jpg $(IMAGE)/"notated music.jpg"
	ln -sf $(IMAGE)/smallpinesLogo.jpg $(IMAGE)/"small_logo.jpg"
	ln -sf $(IMAGE)/computer.jpg $(IMAGE)/"software, multimedia.jpg"
	ln -sf $(IMAGE)/speaker.gif $(IMAGE)/"sound recording-musical.jpg"
	ln -sf $(IMAGE)/speaker.gif $(IMAGE)/"sound recording-nonmusical.jpg"
	ln -sf $(IMAGE)/speaker.gif $(IMAGE)/"sound recording.jpg"
	ln -sf $(IMAGE)/camera.gif $(IMAGE)/"still images.jpg"
	ln -sf $(IMAGE)/open_book.gif $(IMAGE)/text.jpg
	ln -sf $(IMAGE)/book_icon.jpeg $(IMAGE)/"three dimensional object.jpg"

circ-install:
	mkdir -p $(CIRCRULESDIR)
	cp circ_rules/*.rules $(CIRCRULESDIR)/

clean:
	make -C staff_client clean
