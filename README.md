# Server Scripts

This is a repository of various installation scripts for Operating systems that one can use for servers. This should make setting up any new VPS fairly painless and automated.

## To Setup a Fresh debian 12 installation:
curl -fsSL https://raw.githubusercontent.com/jblais493/ServerScripts/master/debian-setup.sh > debian.sh
chmod +x debian.sh
./debian.sh

### To Setup Mailcow:
curl -fsSL https://raw.githubusercontent.com/jblais493/ServerScripts/master/mailcow.sh > mailcow.sh
chmod +x mailcow.sh
sudo ./mailcow.sh

### To Setup Postgres:
curl -fsSL https://raw.githubusercontent.com/jblais493/ServerScripts/master/postgres.sh > postgres.sh
chmod +x postgres.sh
sudo ./postgres.sh
