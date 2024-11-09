# Restrict the computer time of your children (linux accounts)

## What does it do?

The programm loads the state file and limits.conf when starting.

There's a check every 30 seconds that adds 30 seconds to the spent computer time of each user who has active processes.

5 minutes before reaching the time limit it will warn the user by starting "xmessage" in the X session of the user.

When reaching the time limit it will lock the user account (usermod) and it will terminate the login session if there are any user processes.

## Dependencies

* A linux computer
* A personal sysadmin account where you can login and become root that is not one of those accounts that we will locked :-)
* xmessage
* pgrep
* systemd + loginctl
* perl
* perl-yaml-syck
* Logged-in user has a "~/.XAuthority" file in his home directory

## Installation

Place the files anywhere -- for example in "/opt/userlimit/" .

The program "userlimit1.pl" will read "limits.conf" and will write ".userlimits.state" in the same directory as where the program sits.

Copy "sample-limits.conf" to "limits.conf" and add computer time limits for users (seconds).

Copy "userlimit.service" to "/etc/systemd/system/" and check the paths in the file.

Start the program:

* systemctl daemon-reload
* systemctl enable -now userlimit.service
* journalctl -f -u userlimit

### Debugging

To check the functionality without locking someone you can comment out the lines with "loginctl terminate..." and "usermod -L ..." and watch the log file / journal.

You also can stop the program and look into the state file to check the counters.

## Licence

GPL 3.0

