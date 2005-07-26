# ------------------------------------------------------------------------
# Evergreen makefile
# ------------------------------------------------------------------------

IMAGE=$(WEBDIR)/images

# A kludge until we move the generic parts of the staff client to Open-ILS

all:	xul 


install:	images-install circ-install

xul:
	cp -R staff_client local_staff_client
	find local_staff_client/ -type f -exec sed -i s/evergreen/${NEW_XUL_PACKAGE_NAME}/g {} \;
	find local_staff_client/ -type f -exec sed -i s/Evergreen/${NEW_XUL_PACKAGE_LABEL}/g {} \;
	(cd local_staff_client/chrome/skin/evergreen; mv evergreen.css ${NEW_XUL_PACKAGE_NAME}.css)
	(cd local_staff_client/defaults/preferences; mv evergreen.js ${NEW_XUL_PACKAGE_NAME}.js)
	(cd local_staff_client/chrome/content; mv evergreen ${NEW_XUL_PACKAGE_NAME})
	(cd local_staff_client/chrome/locale/en-US/; mv evergreen ${NEW_XUL_PACKAGE_NAME})
	(cd local_staff_client/chrome/skin; mv evergreen ${NEW_XUL_PACKAGE_NAME})
	make -C local_staff_client build
	find local_staff_client/ -type f -exec sed -i s/gapines.org/${NEW_OPAC_URL}/g {} \;
	make -C local_staff_client package

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
	make -C local_staff_client clean
