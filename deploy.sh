#!/bin/bash
# Deploy SimpleEPGP to the WoW TBC Anniversary AddOns folder
rsync -av --delete \
  ~/claude/simple-epgp/SimpleEPGP/ \
  "/home/sd/.steam/debian-installation/steamapps/compatdata/2243145978/pfx/drive_c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/SimpleEPGP/"
echo "Deployed. /reloadui in game to load."
