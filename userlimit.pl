#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use FindBin;
use Getopt::Long;
use POSIX qw(strftime);
use YAML::Syck;

use constant REVISION => "20241115";

GetOptions(
	'config=s' => \my $configfile,
	'state=s' => \my $statefile,
	'verbose' => \my $verbose,
	'help'    => \my $need_help,
);
my $state = {};
my $config = {};
my $dlay = 30;
my $warntime = 5*60; # 5 minutes

print "$0 (REV " . REVISION . ") started.\n";
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

# Save the state into a file an exit
sub shutdown
{
	DumpFile($statefile, $state);
	exit(0);
}

# terminate a user's login session
# ( string -- )
sub logoutUser
{
	my $user = shift;
	`loginctl terminate-user $user`;
}

# lock a user's login account
# ( string -- )
sub lockUser
{
	my $user = shift;
	`usermod -L -e 1 $user`;
}

# count how many processes a user is running
# ( string -- )
sub countProcesses
{
	my $user = shift;
	return scalar split(/\n/, `pgrep -u $user`);
}

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

# unlock a user's login account
# ( string -- )
sub unlock
{
	my $user = shift;
	`usermod -U -e 99999 $user`;
}

$SIG{"INT"} = \&shutdown;
$SIG{"TERM"} = \&shutdown;

my $t_last_info = time();

# mainloop
while(4e4)
{
	sleep($dlay);

	my $tme = time();
	my $today = strftime("%F", localtime( $tme ));   # YYYY-mm-dd
	my $weekday = strftime("%u", localtime( $tme )); # 1 = Mo, ..

	foreach my $user (keys %{ $config->{ users } })
	{
		my $maxduration = $weekday <= 5 ? $config->{ users }->{ $user }->{ normal } : $config->{ users }->{ $user }->{ weekend };
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

		# Lock and kick out the user when reaching the limit:
		if ($state->{ $user }->{ duration } >= $maxduration )
		{
			if (! isLocked( $user ))
			{
				lockUser( $user );
				print "User '$user' has been locked.\n";
			}
			if (countProcesses( $user ))
			{
				terminateUser( $user );
				$state->{ $user }->{ terminated } = 1;
				print "User '$user' has been terminated.\n";
			}
		}
		# warn the user 5 minutes before reaching the limit:
		elsif ((! $state->{ $user }->{ warned }) && ($state->{ $user }->{ duration } >= ( $maxduration - $warntime )) )
		{
			warnUser( $user );
			$state->{ $user }->{ warned } = 1;
			print "User '$user' has been warned.\n";
		}
		# unlock a locked user when not reaching the limit:
		elsif (isLocked( $user ))
		{
			unlock( $user );
			$state->{ $user }->{ terminated } = 0;
			$state->{ $user }->{ warned } = 0;
			print "User $user has been reactivated\n";
		}
	}

	if ((time() - $t_last_info) >= 15*60)
	{
		print Dumper( $state );
		$t_last_info = time();
	}
}

