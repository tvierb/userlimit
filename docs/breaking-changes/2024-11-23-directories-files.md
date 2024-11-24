# new places for all files

* the config is now in /etc/userlimit.conf (still YAML)
* the state file is now in /var/run/
* the binary is now in /usr/local/bin

Steps:
* Stop the service
* move the binary/perl file to /usr/local/bin/
* Move the state file to /var/run/userlimit.state
* Move the config to /etc/userlimit.conf

