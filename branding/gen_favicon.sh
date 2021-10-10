#!/bin/bash

# Run this from inside this folder!

# Generates the favicon from the SVGs in this folder.
# You need ImageMagick and Inkscape installed.

inkscape -w 16 -h 16 icon_16x16.svg -o icon_16x16.png
inkscape -w 32 -h 32 icon_32x32.svg -o icon_32x32.png
inkscape -w 48 -h 48 icon_48x48.svg -o icon_48x48.png
inkscape -w 128 -h 128 icon_128x128.svg -o icon_128x128.png
inkscape -w 256 -h 256 icon_128x128.svg -o icon_256x256.png

convert \
  icon_16x16.png \
  icon_32x32.png \
  icon_48x48.png \
  icon_128x128.png \
  icon_256x256.png \
  -colors 256 \
  ../priv/static/favicon.ico
