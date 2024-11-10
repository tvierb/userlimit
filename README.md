# Restrict the computer time of your children (linux accounts)

## What does it do?

The programm loads the state file and limits.conf when starting.

There's a check every 30 seconds that adds 30 seconds to the spent computer time of each user who has active processes.

5 minutes before reaching the time limit it will warn the user by starting "xmessage" in the X session of the user.

When reaching the time limit it will lock the user account (usermod) and it will terminate the login session if there are any user processes.

The children should logout, suspend, hibernate or switch off the computer to pause the counter.

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

Copy "systemd/userlimit.service" to "/etc/systemd/system/" and check the paths in the file.

Start the program:

* systemctl daemon-reload
* systemctl enable -now userlimit.service
* journalctl -f -u userlimit

### Debugging

To check the functionality without locking someone you can comment out the lines with "loginctl terminate..." and "usermod -L ..." and watch the log file / journal.

You also can stop the program and look into the state file to check the counters.

## TODO / Ideas

### "Add some time for user X only for today"

### Log current state once on an hour (half hour?)

### How much time is left?

The user should see how much time is left (but that information is currently only in the internal $state variable.

Idea:

* write status into a file in the user's home directory from time to time.
* every 5 minutes, but only when account is not blocked

### Name clash when doing shell completion

The file names "userlimit1.pl" and "userlimit.service" have too many chars in common.
I don't want to enter more than two chars user:

    vim us<TAB>

### More implementations

* GForth
* NewLisp
* CommonLisp
* Python

for fun :-)

## Licence

GPL 3.0

