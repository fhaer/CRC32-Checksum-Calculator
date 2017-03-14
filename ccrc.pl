#!/usr/bin/perl
# calculates crc32-checksums (for bit-rot-detection only) for directories specified in %dir
# - outputs values to an sfv-file for each directory
# - in subsequent runs
#   - a crc-value for each file is calculated again
#   - IF file modification time has not changed, the value is compared to the one in the sfv file
#   - IF a missmatch occurs, an e-mail is sent
#   - new checksums are written to a new sfv file, the old file is backed up 

# requires libdigest-crc-perl
use Digest::CRC;
use Fcntl;
use strict;

# directories to calculate checksums for
# key = dir, value = r for recursive, m for mtime compare
my %dir = (
'/home/user/dir1' => 'rm',
'/home/user/dir2' => 'rm',
);

my $quiet = 0;
$quiet = $ARGV[0];

# name of file where checksums are stored
my $checksumFileName = "ccrc.sfv";

# exit now if > 0
my $exitNow = 0;

# count errors
my $errC = 0;

# currently used checksum file
my $checksumFile = "";

# mtimes and checksums in checksum file (stored) and current
my %storedMtime = ();
my %storedCrc = ();
my %currentMtime = ();
my %currentCrc = ();

for my $d (sort keys %dir) {
	$checksumFile = "$d/$checksumFileName";
 	%storedMtime = ();
        %storedCrc = ();
	%currentMtime = ();
	%currentCrc = ();
	readChecksumFile();
	traverseDirs($d, $dir{$d}, 1);
	writeChecksumFile();
}
p("ccrc.pl done\n");
#sendEmail('Srv <mail@example.org>', 'from@address', 'ccrc: done', 'done');

# ---

sub traverseDirs {
	my $dir = shift;
	my $args = shift;
        my $isRecursive = 0;
	my $useMtime = 0;
        $isRecursive = 1 if ($args =~ /r/);
	$useMtime = 1 if ($args =~ /m/);
	my @dirsToTraverse = ($dir);
	$| = 1;
	p("--> $dir (r=$isRecursive, m=$useMtime)\n");
	while (scalar @dirsToTraverse > 0) {
		my $d = shift @dirsToTraverse;
		opendir D, $d or err("unable to open directory", $d);
		my @ls = readdir D or err("unable to read directory", $d);
		closedir D;
		for my $f (@ls) {
			next if ($f eq "." || $f eq "..");
			my $file = "$d/$f";
			next if ($file =~ /^$checksumFile/);
			if (-d $file) {
				unshift(@dirsToTraverse, $file) if ($isRecursive);
			} elsif (-f $file) {
				checkFile($file, $useMtime);
			} else {
				err("not file, not dir", $file);
			}
		}
	}
}

sub checkFile {
	my $f = shift;
	my $useMtime = shift;
	#p("$f ");
	my $mtime = (stat $f)[9];
        my $crc = getCrc($f);
	$currentMtime{$f} = $mtime;
	$currentCrc{$f} = $crc;
	if ($mtime eq $storedMtime{$f} || (!$useMtime && defined $storedCrc{$f})) {
                if ($crc ne $storedCrc{$f}) {
			# re-check
			$crc = getCrc($f);
		}
		if ($crc ne $storedCrc{$f}) {
			p(sprintf("\r%s %d %8s %5s %s\n", $f, $mtime, $crc, "<> $storedCrc{$f} ERROR", $f));
			err("CRC DOES NOT MATCH: $crc <> $storedCrc{$f}", $f);
		} else {
			#p(sprintf("\r%s %d %8s %5s %s\n", $f, $mtime, $crc, "MATCH", $f));
			return;
		}
	}
	#p(sprintf("\r%s %d %8s %5s %s\n", $mtime, $crc, "NEW", $f));
}

sub readChecksumFile {
	return if (!-f $checksumFile);
	open F, $checksumFile or err("unable to open checksum file", $checksumFile);
	while (<F>) {
		# format: <mtime_%s> <crc> <file>
		my $mtime, my $crc, my $f;
		if (/^; (\d+) (\w+) (.+)$/) {
			$mtime = $1;
			$crc = $2;
			$f = $3;
			$storedMtime{$f} = $mtime;
	                $storedCrc{$f} = $crc;
			#print "X $mtime $crc $f \n";
		}
	}
	close F;
}

sub writeChecksumFile {
	# backup old file
	if (-f $checksumFile) {
		rename $checksumFile, "$checksumFile.old" or err("unable to backup checksum file: " . $!, $checksumFile);
	}
	# write
	open F, ">".$checksumFile or err("unalbe to open checksum file for writing", $checksumFile);
	for my $f (sort keys %currentMtime) {
		my $mtime = $currentMtime{$f};
		my $crc = $currentCrc{$f};
		print F "; $mtime $crc $f\n";
	}
	for my $f (sort keys %currentMtime) {
                my $mtime = $currentMtime{$f};
                my $crc = $currentCrc{$f};
                print F "$f $crc\n";
        }
	close F;
}

sub getCrc {
	my $file = shift;
	sysopen(FH, $file, O_RDONLY) or err($!);
	binmode(FH);

	my $ctx = Digest::CRC->new(type=>"crc32");
	$ctx->addfile(*FH);
	#my $digest = $ctx->digest;
	my $digest = $ctx->hexdigest;
	close(FH) or err($!);
	return $digest;
}

sub err {
	my $msg = shift;
	my $file = shift;
	$exitNow++;
	return if ($exitNow > 1);
	my $output = $msg;
	$output .= " ($file)" if (defined $file);
	$output .= "\n";
	writeChecksumFile();
	sendEmail('Srv <mail@example.org>', 'from@example.com', 'ccrc: err', "Error: $output");
	print $output;
	die "too many errors" if ($errC++ >= 5);
}

sub p {
	my $msg = shift;
	print $msg if (!$quiet);
}

sub sendEmail {
  my $from = shift;
  my $recipients = shift;
  my $subject = shift;
  my $message = shift;

  use Email::Sender::Simple qw(sendmail);
  use Email::Sender::Transport::SMTP::TLS;
  use Try::Tiny;

  my $transport = Email::Sender::Transport::SMTP::TLS->new(
        host => 'smtp.exmaple.com',
        port => 587,
        username => 'mail@example.com',
        password => 'secret',
        helo => 'localdomain.com',  # insert your local host name here
  );

  use Email::MIME::CreateHTML; # or other Email::
  my $message = Email::MIME->create_html(
        header => [
            From    => $from,
            To      => $recipients,
            Subject => $subject,
        ],
        body => $message
  );

  try {
    sendmail($message, { transport => $transport });
  } catch {
    print "Error sending email\n $_";
  };
}

