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

use constant REVISION => "20241124";

GetOptions(
	'config=s' => \my $configfile,
	'state=s' => \my $statefile,
	'verbose' => \my $verbose,
	'help'    => \my $need_help,
	'addtime=s' => \my $addtime, # 1h1m1s
);
my $state = {};
my $config = {};
my $dlay = 30; # adding duration to user counter very 30 seconds
my $warntime = 5*60; # 5 minutes
print "userlimiter (REV " . REVISION . ") started.\n";

$configfile //= "/etc/userlimit.conf";        print "\$configfile=$configfile\n";
$statefile //= "/var/run/userlimit.state";    print "\$statefile=$configfile\n";

die("ERROR: Config file '$configfile' not found. Edit or move from old directory /opt/userlimit/.") unless -f $configfile;

$config = LoadFile( $configfile ); # may crash
print "Loading state data from file $statefile\n";
print "Not loading state data (not found). Starting from 0.\n" unless -f $statefile;
$state = LoadFile( $statefile ) if -f $statefile;

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

print "state: " . Dumper( $state );
print "Hint: Execute '$0 --addtime user1,duration' to give a user more time for today.\n";

# Increase a users' day limit:
# userlimit --addtime amv7,1200
#
# Place a ticket file in /var/spool/userlimit/ and send SIGINT to running daemon
if (defined($addtime) && $addtime =~ /^([a-z_]+[a-z0-9_]*),(.+)$/)
{
	my $tme = time();
	my $user = $1;
	my $duration = hms2secs( $2 );
	my $ticket = {
		user => $user,
		duration => $duration,
		fordate => strftime("%Y-%m-%d", localtime($tme)),
	};
	DumpFile("/var/spool/userlimit/$tme.ticket", $ticket);
	print("Created a ticket in /var/spool/userlimit/\n");

	# send signal
	chomp(my $id = `cat /var/run/userlimit.pid`);
	die("no running daemon found!?") unless $id > 0;
	kill('INT', $id);
	print "Sent a signal to the daemon with PID $id\n";
	exit(0);
}

sub load_tickets
{
	print "Scanning for tickets\n";
	foreach my $filename (glob("/var/spool/userlimit/*.ticket"))
	{
		print "Processing ticket '$filename'\n";
		my $ticket = LoadFile( $filename );
		my $user = $ticket->{ user };
		my $duration = $ticket->{ duration };
		my $fordate  = $ticket->{ fordate  };
		if (defined($state->{ $user }))
		{
			if ($state->{ $user }->{today} eq $ticket->{ fordate })
			{
				print "Topping up user '$user' by $duration seconds on $fordate\n";
				$state->{ $user }->{ limit } = $state->{ $user }->{ limit } + $duration;
				$state->{ $user }->{ warned } = 0;
			}
			else {
				print "Ticket '$filename' had wrong date '$fordate'.\n";
			}
		}
		else {
			print "Unknown user '$user' in ticket '$filename'.\n";
		}
		unlink($filename) or die("Cannot remove file '$filename'");
	}
}

# =============================================================

$SIG{"INT"} = \&load_tickets;
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
			$state->{ $user }->{ limit } = $maxduration; # with the limit in the state data we can change a day's limit
		}

		if (countProcesses( $user ))
		{
			$state->{ $user }->{ duration } = $state->{ $user }->{ duration } + $dlay;
		}

		my $duration  = $state->{ $user }->{ duration };
		my $userlimit = $state->{ $user }->{ limit } // $maxduration;

		# Lock and kick out the user when reaching the limit:
		if ($duration >= $userlimit)
		{
			print "User '$user' has duration $duration  >= limit $userlimit\n";
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
			if ($duration >= ( $userlimit - $warntime ))
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
exit(0);

# Write PID file:
BEGIN {
	open(my $fh, ">", "/var/run/userlimit.pid") or die("cannot write PID file");
	print $fh $$;
	close($fh);
}

# Remove PID file:
END {
	unlink("/var/run/userlimit.pid");
}
# =============================================================
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
				exit(0);
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

# -------------------------------------------------------------
sub fileage
{
	my $filename = shift;
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	                    $atime,$mtime,$ctime,$blksize,$blocks)
	                       = stat($filename);
	return time() - $mtime;
}

# -------------------------------------------------------------
sub hms2secs
{
	my $hms = shift;
	$hms .= 's' if $hms !~ /[hms]$/; # append "s"
	my $secs = 0;
	while ($hms =~ /([0-9]+)([hms]+)/g)
	{
		my $amount = $1;
		my $quantifier = $2;
		$secs +=        $amount if $quantifier eq "s";
		$secs +=   60 * $amount if $quantifier eq "m";
		$secs += 3600 * $amount if $quantifier eq "h";
	}
	return $secs;
}
