#!/bin/bash

INKSCAPESCRIPT=""
ALLICONS=""

# Build alt color sets! All start with blue
# ORANGE - RGB -> BGR
mkdir -p toolbar_orange
for file in `ls toolbar_blue/blue_*`; do sed -e 's/"#\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)"/"#\3\2\1"/' -e 's/"#\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)"/"#\3\2\1"/' $file > `echo $file | sed -e 's/blue/orange/g'`; done
# Green - RGB -> GBR
mkdir -p toolbar_green
for file in `ls toolbar_blue/blue_*`; do sed -e 's/"#\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)"/"#\2\3\1"/' -e 's/"#\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)"/"#\2\3\1"/' $file > `echo $file | sed -e 's/blue/green/g'`; done
# Fuschia - RGB -> BRG
mkdir -p toolbar_fuschia
for file in `ls toolbar_blue/blue_*`; do sed -e 's/"#\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)"/"#\3\1\2"/' -e 's/"#\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)"/"#\3\1\2"/' $file > `echo $file | sed -e 's/blue/fuschia/g'`; done
# Teal - RGB -> RBG
mkdir -p toolbar_teal
for file in `ls toolbar_blue/blue_*`; do sed -e 's/"#\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)"/"#\1\3\2"/' -e 's/"#\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)"/"#\1\3\2"/' $file > `echo $file | sed -e 's/blue/teal/g'`; done
# Purple - RGB -> GRB
mkdir -p toolbar_purple
for file in `ls toolbar_blue/blue_*`; do sed -e 's/"#\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)\([0-9A-Fa-f]\{2\}\)"/"#\2\1\3"/' -e 's/"#\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)\([0-9A-Fa-f]\)"/"#\2\1\3"/' $file > `echo $file | sed -e 's/blue/purple/g'`; done

mkdir -p pngfiles_working
rm -f pngfiles_working/*

# Start by exporting all the svg files as png files
# This also collects icon names for later, and notes those that have no disabled icon
for color in blue orange green fuschia teal purple
do
    for icon in $( ls toolbar_$color/${color}_*.svg | cut -f1 -d. | cut -f2- -d/ | cut -f2- -d_  )
    do
        if [ "$color" == "blue" ]; then
            ALLICONS="$ALLICONS $icon"
        fi
        INKSCAPESCRIPT="$INKSCAPESCRIPT
-w 32 -e pngfiles_working/${color}_${icon}_active_32.png toolbar_$color/${color}_${icon}.svg
-w 16 -e pngfiles_working/${color}_${icon}_active_16.png toolbar_$color/${color}_${icon}.svg"
    done
done
# Do the full export in one inkscape session
echo "$INKSCAPESCRIPT" | inkscape --shell

# Now make disabled variants
for file in `ls pngfiles_working/*active*`
do
    convert $file -fx '(r+g+b)/3' `echo $file | sed -e 's/active/disabled/'`
done

mkdir -p pngfiles_complete

# Now we need to assemble the icons. For this we use imagemagick to combine 4 (or 8?) images into one.
for icon in $ALLICONS
do
    for color in blue orange green fuschia teal purple
    do
        mkdir -p pngfiles_complete/toolbar_$color
        convert \( pngfiles_working/${color}_${icon}_active_32.png pngfiles_working/${color}_${icon}_disabled_32.png -append \) \
                \( pngfiles_working/${color}_${icon}_active_16.png pngfiles_working/${color}_${icon}_disabled_16.png -append \) \
                -background none +append pngfiles_complete/toolbar_$color/${icon}_toolbar.png
    done
done
