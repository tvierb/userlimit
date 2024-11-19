#!/usr/bin/perl

# Q: There may be a problem with running again right after suspend:
# The clock may still tell us the old date and see the duration played yesterday und lock the user.
# A: wait a minute befor any actions?

use strict;
use warnings;
use Data::Dumper;
use FindBin;
use Getopt::Long;
use POSIX qw(strftime);
use YAML::Syck;

use constant REVISION => "20241119";

GetOptions(
	'config=s' => \my $configfile,
	'state=s' => \my $statefile,
	'verbose' => \my $verbose,
	'help'    => \my $need_help,
);
my $state = {};
my $config = {};
my $dlay = 30; # adding duration to user counter very 30 seconds
my $warntime = 5*60; # 5 minutes

print "userlimiter (REV " . REVISION . ") started.\n";
$configfile //= "$FindBin::Bin/limits.conf";
print "\$configfile=$configfile\n" if $verbose;
$config = LoadFile( $configfile ); # may crash
die("I need at least one user in the config file '$configfile'") unless scalar keys %{ $config->{ users } };
foreach my $user (keys %{ $config->{ users }})
{
	# Ensure all user account names are safe when calling an external command:
	die("Malformed user name '$user'") unless $user =~ /^[a-z_]+[a-z0-9_]*$/;
	die("Cannot limit the root user") if $user eq "root";
	die("Cannot limit the sysadmin user") if $user eq "sysadmin";
	die("Missing 'normal: <num>' in config of user '$user'") unless $config->{users}->{ $user }->{ normal };
	die("Missing 'weekend: <num>' in config of user '$user'") unless $config->{users}->{ $user }->{ weekend };
}

$statefile //= "$FindBin::Bin/.userlimit.state";
if (-f $statefile)
{
	print "Loading state from '$statefile'.\n";
	$state = LoadFile( $statefile );
}
else {
	print "State file '$statefile' not found. Counters start from 0.\n";
}
print "state: " . Dumper( $state );

# -------------------------------------------------------------
# Save the state into a file an exit
sub shutdown
{
	DumpFile($statefile, $state);
	exit(0);
}

# -------------------------------------------------------------
# terminate a user's login session
# ( string -- )
sub logoutUser
{
	my $user = shift;
	`loginctl terminate-user $user`;
}

# -------------------------------------------------------------
# lock a user's login account
# ( string -- )
sub lockUser
{
	my $user = shift;
	`usermod -L -e 1 $user`;
}

# -------------------------------------------------------------
# count how many processes a user is running
# ( string -- )
sub countProcesses
{
	my $user = shift;
	return scalar split(/\n/, `pgrep -u $user`);
}

# -------------------------------------------------------------
# open a info box on the user's desktop screen
# ( string -- )
sub warnUser
{
	my $user = shift;
	foreach my $line( split(/\n/, `who` ))
	{
		next unless substr($line, 0, length($user)) eq $user;
		my $xauth="/home/$user/.Xauthority";
		if ($line =~ /\(([^\)]+)\)$/)
		{
			my $disp = $1;
			my $id = fork();
			if ($id == 0) # am I the child?
			{
				`DISPLAY=$disp XAUTHORITY="$xauth" xmessage "Deine Bildschirmzeit ist gleich zu Ende. Sichere Deine Daten und logge dich aus."`; # fire and forget
			}
		}
	}
}

# -------------------------------------------------------------
# Find out: is the account already locked?
# ( string -- )
sub isLocked
{
	my $user = shift;
	foreach my $line (split(/\n/, `cat /etc/shadow`))
	{
		return 1 if (substr($line, 0, length($user)+2) eq "$user:!");
	}
	return 0;
}

# -------------------------------------------------------------
# unlock a user's login account
# ( string -- )
sub unlock
{
	my $user = shift;
	`usermod -U -e 99999 $user`;
}

# =============================================================

$SIG{"INT"} = \&shutdown;
$SIG{"TERM"} = \&shutdown;

# let's wait a minute so that the ntp sync can be ready
print "Sleeping 1 minute to be shure the time is right after suspend-recovery (we hope so)\n";
sleep(60);

my $t_last_info = 0;

# mainloop
while(4e4)
{
	my $tme = time();
	my $today = strftime("%F", localtime( $tme ));   # YYYY-mm-dd
	my $weekday = strftime("%u", localtime( $tme )); # 1 = Mo, ..

	foreach my $user (keys %{ $config->{ users } })
	{
		my $maxduration = $weekday <= 5 ? $config->{ users }->{ $user }->{ normal }
		                                : $config->{ users }->{ $user }->{ weekend };
		$maxduration //= 3600; # set a default

		# reset the state on a fresh new day:
		if (! (defined($state->{ $user }->{ today }) && ($state->{ $user }->{ today } eq $today )))
		{
			$state->{ $user }->{ today } = $today;
			$state->{ $user }->{ duration } = 0;
			$state->{ $user }->{ terminated } = 0; # wird eignetl nicht verwendet
			$state->{ $user }->{ warned } = 0;
		}

		if (countProcesses( $user ))
		{
			$state->{ $user }->{ duration } = $state->{ $user }->{ duration } + $dlay;
		}

		my $duration = $state->{ $user }->{ duration };
		# Lock and kick out the user when reaching the limit:
		if ($duration >= $maxduration )
		{
			print "User '$user' has duration $duration  >= maxduration $maxduration\n";
			if (! isLocked( $user ))
			{
				print "Locking the user account of '$user'\n";
				lockUser( $user );
			}
			if (countProcesses( $user ))
			{
				print "Logging out user '$user'.\n";
				logoutUser( $user );
				$state->{ $user }->{ terminated } = 1;
			}
		}
		else
		{
			if (isLocked( $user )) # unlock a locked user who has not reached the limit
			{
				unlock( $user );
				$state->{ $user }->{ terminated } = 0;
				print "User $user has been reactivated\n";
			}

			# warn the user 5 minutes before reaching the limit
			if ($duration >= ( $maxduration - $warntime )) 
			{
				if (! $state->{ $user }->{ warned })
				{
					print "Warning the user '$user'.\n";
					$state->{ $user }->{ warned } = 1;
					warnUser( $user );
				}
			}
			else
			{
				$state->{ $user }->{ warned } = 0;
			}
		}
	}

	if ((time() - $t_last_info) >= 15*60)
	{
		print "state: " . Dumper( $state );
		$t_last_info = time();
	}

	sleep($dlay);
}

