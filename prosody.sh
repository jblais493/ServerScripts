#!/bin/bash

sudo apt install prosody certbot lua-dbi-postgresql

sudo apt install postgresql
sudo -u postgres createuser --pwprompt prosody
sudo -u postgres createdb --owner=prosody prosody
