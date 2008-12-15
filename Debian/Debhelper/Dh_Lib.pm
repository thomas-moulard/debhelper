#!/usr/bin/perl -w
#
# Library functions for debhelper programs, perl version.
#
# Joey Hess, GPL copyright 1997-2008.

package Debian::Debhelper::Dh_Lib;
use strict;

use Exporter;
use vars qw(@ISA @EXPORT %dh);
@ISA=qw(Exporter);
@EXPORT=qw(&init &doit &complex_doit &verbose_print &error &warning &tmpdir
	    &pkgfile &pkgext &pkgfilename &isnative &autoscript &filearray
	    &filedoublearray &getpackages &basename &dirname &xargs %dh
	    &compat &addsubstvar &delsubstvar &excludefile &package_arch
	    &is_udeb &udeb_filename &debhelper_script_subst &escape_shell
	    &inhibit_log);

my $max_compat=7;

sub init {
	my %params=@_;

	# Check to see if an option line starts with a dash,
	# or DH_OPTIONS is set.
	# If so, we need to pass this off to the resource intensive 
	# Getopt::Long, which I'd prefer to avoid loading at all if possible.
	if ((defined $ENV{DH_OPTIONS} && length $ENV{DH_OPTIONS}) ||
	    grep /^-/, @ARGV) {
		eval "use Debian::Debhelper::Dh_Getopt";
		error($@) if $@;
		Debian::Debhelper::Dh_Getopt::parseopts($params{options});
	}

	# Another way to set excludes.
	if (exists $ENV{DH_ALWAYS_EXCLUDE} && length $ENV{DH_ALWAYS_EXCLUDE}) {
		push @{$dh{EXCLUDE}}, split(":", $ENV{DH_ALWAYS_EXCLUDE});
	}
	
	# Generate EXCLUDE_FIND.
	if ($dh{EXCLUDE}) {
		$dh{EXCLUDE_FIND}='';
		foreach (@{$dh{EXCLUDE}}) {
			my $x=$_;
			$x=escape_shell($x);
			$x=~s/\./\\\\./g;
			$dh{EXCLUDE_FIND}.="-regex .\\*$x.\\* -or ";
		}
		$dh{EXCLUDE_FIND}=~s/ -or $//;
	}
	
	# Check to see if DH_VERBOSE environment variable was set, if so,
	# make sure verbose is on.
	if (defined $ENV{DH_VERBOSE} && $ENV{DH_VERBOSE} ne "") {
		$dh{VERBOSE}=1;
	}

	# Check to see if DH_NO_ACT environment variable was set, if so, 
	# make sure no act mode is on.
	if (defined $ENV{DH_NO_ACT} && $ENV{DH_NO_ACT} ne "") {
		$dh{NO_ACT}=1;
	}

	my @allpackages=getpackages();
	# Get the name of the main binary package (first one listed in
	# debian/control). Only if the main package was not set on the
	# command line.
	if (! exists $dh{MAINPACKAGE} || ! defined $dh{MAINPACKAGE}) {
		$dh{MAINPACKAGE}=$allpackages[0];
	}

	# Check if packages to build have been specified, if not, fall back to
	# the default, doing them all.
	if (! defined $dh{DOPACKAGES} || ! @{$dh{DOPACKAGES}}) {
		if ($dh{DOINDEP} || $dh{DOARCH} || $dh{DOSAME}) {
			error("You asked that all arch in(dep) packages be built, but there are none of that type.");
		}
		push @{$dh{DOPACKAGES}},@allpackages;
	}

	# Check to see if -P was specified. If so, we can only act on a single
	# package.
	if ($dh{TMPDIR} && $#{$dh{DOPACKAGES}} > 0) {
		error("-P was specified, but multiple packages would be acted on (".join(",",@{$dh{DOPACKAGES}}).").");
	}

	# Figure out which package is the first one we were instructed to build.
	# This package gets special treatement: files and directories specified on
	# the command line may affect it.
	$dh{FIRSTPACKAGE}=${$dh{DOPACKAGES}}[0];

	# If no error handling function was specified, just propigate
	# errors out.
	if (! exists $dh{ERROR_HANDLER} || ! defined $dh{ERROR_HANDLER}) {
		$dh{ERROR_HANDLER}='exit \$?';
	}
}

# Run at exit. Add the command to the log files for the packages it acted
# on, if it's exiting successfully.
my $write_log=1;
sub END {
	if ($? == 0 && $write_log) {
		my $cmd=basename($0);
		foreach my $package (@{$dh{DOPACKAGES}}) {
			my $ext=pkgext($package);
			my $log="debian/${ext}debhelper.log";
			open(LOG, ">>", $log) || error("failed to write to ${log}: $!");
			print LOG $cmd."\n";
			close LOG;
		}
	}
}

sub inhibit_log {
	$write_log=0;
}

# Pass it an array containing the arguments of a shell command like would
# be run by exec(). It turns that into a line like you might enter at the
# shell, escaping metacharacters and quoting arguments that contain spaces.
sub escape_shell {
	my @args=@_;
	my $line="";
	my @ret;
	foreach my $word (@args) {
		if ($word=~/\s/) {
			# Escape only a few things since it will be quoted.
			# Note we use double quotes because you cannot
			# escape ' in single quotes, while " can be escaped
			# in double.
			# This does make -V"foo bar" turn into "-Vfoo bar",
			# but that will be parsed identically by the shell
			# anyway..
			$word=~s/([\n`\$"\\])/\\$1/g;
			push @ret, "\"$word\"";
		}
		else {
			# This list is from _Unix in a Nutshell_. (except '#')
			$word=~s/([\s!"\$()*+#;<>?@\[\]\\`|~])/\\$1/g;
			push @ret,$word;
		}
	}
	return join(' ', @ret);
}

# Run a command, and display the command to stdout if verbose mode is on.
# All commands that modifiy files in $TMP should be ran via this 
# function.
#
# Note that this cannot handle complex commands, especially anything
# involving redirection. Use complex_doit instead.
sub doit {
	verbose_print(escape_shell(@_));

	if (! $dh{NO_ACT}) {
		my $ret=system(@_);
		$ret == 0 || error("command returned error code $ret");
	}
}

# Run a command and display the command to stdout if verbose mode is on.
# Use doit() if you can, instead of this function, because this function
# forks a shell. However, this function can handle more complicated stuff
# like redirection.
sub complex_doit {
	verbose_print(join(" ",@_));
	
	if (! $dh{NO_ACT}) {
		# The join makes system get a scalar so it forks off a shell.
		system(join(" ",@_)) == 0
			|| error("command returned error code");
	}			
}

# Run a command that may have a huge number of arguments, like xargs does.
# Pass in a reference to an array containing the arguments, and then other
# parameters that are the command and any parameters that should be passed to
# it each time.
sub xargs {
	my $args=shift;

        # The kernel can accept command lines up to 20k worth of characters.
	my $command_max=20000; # LINUX SPECIFIC!!
			# I could use POSIX::ARG_MAX, but that would be slow.

	# Figure out length of static portion of command.
	my $static_length=0;
	foreach (@_) {
		$static_length+=length($_)+1;
	}
	
	my @collect=();
	my $length=$static_length;
	foreach (@$args) {
		if (length($_) + 1 + $static_length > $command_max) {
			error("This command is greater than the maximum command size allowed by the kernel, and cannot be split up further. What on earth are you doing? \"@_ $_\"");
		}
		$length+=length($_) + 1;
		if ($length < $command_max) {
			push @collect, $_;
		}
		else {
			doit(@_,@collect) if $#collect > -1;
			@collect=($_);
			$length=$static_length + length($_) + 1;
		}
	}
	doit(@_,@collect) if $#collect > -1;
}

# Print something if the verbose flag is on.
sub verbose_print {
	my $message=shift;
	
	if ($dh{VERBOSE}) {
		print "\t$message\n";
	}
}

# Output an error message and exit.
sub error {
	my $message=shift;

	warning($message);
	exit 1;
}

# Output a warning.
sub warning {
	my $message=shift;
	
	print STDERR basename($0).": $message\n";
}

# Returns the basename of the argument passed to it.
sub basename {
	my $fn=shift;

	$fn=~s/\/$//g; # ignore trailing slashes
	$fn=~s:^.*/(.*?)$:$1:;
	return $fn;
}

# Returns the directory name of the argument passed to it.
sub dirname {
	my $fn=shift;
	
	$fn=~s/\/$//g; # ignore trailing slashes
	$fn=~s:^(.*)/.*?$:$1:;
	return $fn;
}

# Pass in a number, will return true iff the current compatibility level
# is less than or equal to that number.
{
	my $warned_compat=0;
	my $c;

	sub compat {
		my $num=shift;
	
		if (! defined $c) {
			$c=1;
			if (defined $ENV{DH_COMPAT}) {
				$c=$ENV{DH_COMPAT};
			}
			elsif (-e 'debian/compat') {
				# Try the file..
				open (COMPAT_IN, "debian/compat") || error "debian/compat: $!";
				my $l=<COMPAT_IN>;
				if (! defined $l || ! length $l) {
					warning("debian/compat is empty, assuming level $c");
				}
				else {
					chomp $l;
					$c=$l;
				}
			}
		}

		if ($c < 4 && ! $warned_compat) {
			warning("Compatibility levels before 4 are deprecated.");
			$warned_compat=1;
		}
	
		if ($c > $max_compat) {
			error("Sorry, but $max_compat is the highest compatibility level supported by this debhelper.");
		}

		return ($c <= $num);
	}
}

# Pass it a name of a binary package, it returns the name of the tmp dir to
# use, for that package.
sub tmpdir {
	my $package=shift;

	if ($dh{TMPDIR}) {
		return $dh{TMPDIR};
	}
	elsif (compat(1) && $package eq $dh{MAINPACKAGE}) {
		# This is for back-compatibility with the debian/tmp tradition.
		return "debian/tmp";
	}
	else {
		return "debian/$package";
	}
}

# Pass this the name of a binary package, and the name of the file wanted
# for the package, and it will return the actual existing filename to use.
#
# It tries several filenames:
#   * debian/package.filename.buildarch
#   * debian/package.filename
#   * debian/file (if the package is the main package)
# If --name was specified then tonly the first two are tried, and they must
# have the name after the pacage name:
#   * debian/package.name.filename.buildarch
#   * debian/package.name.filename
sub pkgfile {
	my $package=shift;
	my $filename=shift;

	if (defined $dh{NAME}) {
		$filename="$dh{NAME}.$filename";
	}
	
	my @try=("debian/$package.$filename.".buildarch(),
		 "debian/$package.$filename");
	if ($package eq $dh{MAINPACKAGE}) {
		push @try, "debian/$filename";
	}
	
	foreach my $file (@try) {
		if (-f $file &&
		    (! $dh{IGNORE} || ! exists $dh{IGNORE}->{$file})) {
			return $file;
		}

	}

	return "";

}

# Pass it a name of a binary package, it returns the name to prefix to files
# in debian/ for this package.
sub pkgext {
	my $package=shift;

	if (compat(1) and $package eq $dh{MAINPACKAGE}) {
		return "";
	}
	return "$package.";
}

# Pass it the name of a binary package, it returns the name to install
# files by in eg, etc. Normally this is the same, but --name can override
# it.
sub pkgfilename {
	my $package=shift;

	if (defined $dh{NAME}) {
		return $dh{NAME};
	}
	return $package;
}

# Returns 1 if the package is a native debian package, null otherwise.
# As a side effect, sets $dh{VERSION} to the version of this package.
{
	# Caches return code so it only needs to run dpkg-parsechangelog once.
	my %isnative_cache;
	
	sub isnative {
		my $package=shift;

		return $isnative_cache{$package} if defined $isnative_cache{$package};
		
		# Make sure we look at the correct changelog.
		my $isnative_changelog=pkgfile($package,"changelog");
		if (! $isnative_changelog) {
			$isnative_changelog="debian/changelog";
		}
		# Get the package version.
		my $version=`dpkg-parsechangelog -l$isnative_changelog`;
		($dh{VERSION})=$version=~m/Version:\s*(.*)/m;
		# Did the changelog parse fail?
		if (! defined $dh{VERSION}) {
			error("changelog parse failure");
		}

		# Is this a native Debian package?
		if ($dh{VERSION}=~m/.*-/) {
			return $isnative_cache{$package}=0;
		}
		else {
			return $isnative_cache{$package}=1;
		}
	}
}

# Automatically add a shell script snippet to a debian script.
# Only works if the script has #DEBHELPER# in it.
#
# Parameters:
# 1: package
# 2: script to add to
# 3: filename of snippet
# 4: sed to run on the snippet. Ie, s/#PACKAGE#/$PACKAGE/
sub autoscript {
	my $package=shift;
	my $script=shift;
	my $filename=shift;
	my $sed=shift || "";

	# This is the file we will modify.
	my $outfile="debian/".pkgext($package)."$script.debhelper";

	# Figure out what shell script snippet to use.
	my $infile;
	if (defined($ENV{DH_AUTOSCRIPTDIR}) && 
	    -e "$ENV{DH_AUTOSCRIPTDIR}/$filename") {
		$infile="$ENV{DH_AUTOSCRIPTDIR}/$filename";
	}
	else {
		if (-e "/usr/share/debhelper/autoscripts/$filename") {
			$infile="/usr/share/debhelper/autoscripts/$filename";
		}
		else {
			error("/usr/share/debhelper/autoscripts/$filename does not exist");
		}
	}

	if (-e $outfile && ($script eq 'postrm' || $script eq 'prerm')
	   && !compat(5)) {
		# Add fragments to top so they run in reverse order when removing.
		complex_doit("echo \"# Automatically added by ".basename($0)."\"> $outfile.new");
		complex_doit("sed \"$sed\" $infile >> $outfile.new");
		complex_doit("echo '# End automatically added section' >> $outfile.new");
		complex_doit("cat $outfile >> $outfile.new");
		complex_doit("mv $outfile.new $outfile");
	}
	else {
		complex_doit("echo \"# Automatically added by ".basename($0)."\">> $outfile");
		complex_doit("sed \"$sed\" $infile >> $outfile");
		complex_doit("echo '# End automatically added section' >> $outfile");
	}
}

# Removes a whole substvar line.
sub delsubstvar {
	my $package=shift;
	my $substvar=shift;

	my $ext=pkgext($package);
	my $substvarfile="debian/${ext}substvars";

	if (-e $substvarfile) {
		complex_doit("grep -s -v '^${substvar}=' $substvarfile > $substvarfile.new || true");
		doit("mv", "$substvarfile.new","$substvarfile");
	}
}
				
# Adds a dependency on some package to the specified
# substvar in a package's substvar's file.
sub addsubstvar {
	my $package=shift;
	my $substvar=shift;
	my $deppackage=shift;
	my $verinfo=shift;
	my $remove=shift;

	my $ext=pkgext($package);
	my $substvarfile="debian/${ext}substvars";
	my $str=$deppackage;
	$str.=" ($verinfo)" if defined $verinfo && length $verinfo;

	# Figure out what the line will look like, based on what's there
	# now, and what we're to add or remove.
	my $line="";
	if (-e $substvarfile) {
		my %items;
		open(SUBSTVARS_IN, "$substvarfile") || error "read $substvarfile: $!";
		while (<SUBSTVARS_IN>) {
			chomp;
			if (/^\Q$substvar\E=(.*)/) {
				%items = map { $_ => 1} split(", ", $1);
				
				last;
			}
		}
		close SUBSTVARS_IN;
		if (! $remove) {
			$items{$str}=1;
		}
		else {
			delete $items{$str};
		}
		$line=join(", ", sort keys %items);
	}
	elsif (! $remove) {
		$line=$str;
	}

	if (length $line) {
		 complex_doit("(grep -s -v ${substvar} $substvarfile; echo ".escape_shell("${substvar}=$line").") > $substvarfile.new");
		 doit("mv", "$substvarfile.new", $substvarfile);
	}
	else {
		delsubstvar($package,$substvar);
	}
}

# Reads in the specified file, one line at a time. splits on words, 
# and returns an array of arrays of the contents.
# If a value is passed in as the second parameter, then glob
# expansion is done in the directory specified by the parameter ("." is
# frequently a good choice).
sub filedoublearray {
	my $file=shift;
	my $globdir=shift;

	my @ret;
	open (DH_FARRAY_IN, $file) || error("cannot read $file: $1");
	while (<DH_FARRAY_IN>) {
		chomp;
		# Only ignore comments and empty lines in v5 mode.
		if (! compat(4)) {
			next if /^#/ || /^$/;
		}
		my @line;
		# Only do glob expansion in v3 mode.
		#
		# The tricky bit is that the glob expansion is done
		# as if we were in the specified directory, so the
		# filenames that come out are relative to it.
		if (defined $globdir && ! compat(2)) {
			for (map { glob "$globdir/$_" } split) {
				s#^$globdir/##;
				push @line, $_;
			}
		}
		else {
			@line = split;
		}
		push @ret, [@line];
	}
	close DH_FARRAY_IN;
	
	return @ret;
}

# Reads in the specified file, one word at a time, and returns an array of
# the result. Can do globbing as does filedoublearray.
sub filearray {
	return map { @$_ } filedoublearray(@_);
}

# Passed a filename, returns true if -X says that file should be excluded.
sub excludefile {
        my $filename = shift;
        foreach my $f (@{$dh{EXCLUDE}}) {
                return 1 if $filename =~ /\Q$f\E/;
        }
        return 0;
}

# Returns the build architecture. (Memoized)
{
	my $arch;
	
	sub buildarch {
  		return $arch if defined $arch;

		$arch=`dpkg-architecture -qDEB_HOST_ARCH 2>/dev/null` || error("dpkg-architecture failed");
		chomp $arch;
		return $arch;
	}
}

# Passed an arch and a list of arches to match against, returns true if matched
sub samearch {
	my $arch=shift;
	my @archlist=split(/\s+/,shift);

	foreach my $a (@archlist) {
		system("dpkg-architecture", "-a$arch", "-i$a") == 0 && return 1;
	}

	return 0;
}

# Returns a list of packages in the control file.
# Must pass "arch" or "indep" or "same" to specify arch-dependant or
# -independant or same arch packages. If nothing is specified, returns all
# packages.
# As a side effect, populates %package_arches and %package_types with the
# types of all packages (not only those returned).
my (%package_types, %package_arches);
sub getpackages {
	my $type=shift;

	%package_types=();
	%package_arches=();
	
	$type="" if ! defined $type;
	
	# Look up the build arch if we need to.
	my $buildarch='';
	if ($type eq 'same') {
		$buildarch=buildarch();
	}

	my $package="";
	my $arch="";
	my $package_type;
	my @list=();
	my %seen;
	open (CONTROL, 'debian/control') ||
		error("cannot read debian/control: $!\n");
	while (<CONTROL>) {
		chomp;
		s/\s+$//;
		if (/^Package:\s*(.*)/) {
			$package=$1;
			# Detect duplicate package names in the same control file.
			if (! $seen{$package}) {
				$seen{$package}=1;
			}
			else {
				error("debian/control has a duplicate entry for $package");
			}
			$package_type="deb";
		}
		if (/^Architecture:\s*(.*)/) {
			$arch=$1;
		}
		if (/^(?:X[BC]*-)?Package-Type:\s*(.*)/) {
			$package_type=$1;
		}
		
		if (!$_ or eof) { # end of stanza.
			if ($package) {
				$package_types{$package}=$package_type;
				$package_arches{$package}=$arch;
			}
			if ($package &&
			    (($type eq 'indep' && $arch eq 'all') ||
			     ($type eq 'arch' && $arch ne 'all') ||
			     ($type eq 'same' && ($arch eq 'any' || samearch($buildarch, $arch))) ||
			     ! $type)) {
				push @list, $package;
				$package="";
				$arch="";
			}
		}
	}
	close CONTROL;

	return @list;
}

# Returns the arch a package will build for.
sub package_arch {
	my $package=shift;
	
	if (! exists $package_arches{$package}) {
		warning "package $package is not in control info";
		return buildarch();
	}
	return $package_arches{$package} eq 'all' ? "all" : buildarch();
}

# Return true if a given package is really a udeb.
sub is_udeb {
	my $package=shift;
	
	if (! exists $package_types{$package}) {
		warning "package $package is not in control info";
		return 0;
	}
	return $package_types{$package} eq 'udeb';
}

# Generates the filename that is used for a udeb package.
sub udeb_filename {
	my $package=shift;
	
	my $filearch=package_arch($package);
	isnative($package); # side effect
	my $version=$dh{VERSION};
	$version=~s/^[0-9]+://; # strip any epoch
	return "${package}_${version}_$filearch.udeb";
}

# Handles #DEBHELPER# substitution in a script; also can generate a new
# script from scratch if none exists but there is a .debhelper file for it.
sub debhelper_script_subst {
	my $package=shift;
	my $script=shift;
	
	my $tmp=tmpdir($package);
	my $ext=pkgext($package);
	my $file=pkgfile($package,$script);

	if ($file ne '') {
		if (-f "debian/$ext$script.debhelper") {
			# Add this into the script, where it has #DEBHELPER#
			complex_doit("perl -pe 's~#DEBHELPER#~qx{cat debian/$ext$script.debhelper}~eg' < $file > $tmp/DEBIAN/$script");
		}
		else {
			# Just get rid of any #DEBHELPER# in the script.
			complex_doit("sed s/#DEBHELPER#// < $file > $tmp/DEBIAN/$script");
		}
		doit("chown","0:0","$tmp/DEBIAN/$script");
		doit("chmod",755,"$tmp/DEBIAN/$script");
	}
	elsif ( -f "debian/$ext$script.debhelper" ) {
		complex_doit("printf '#!/bin/sh\nset -e\n' > $tmp/DEBIAN/$script");
		complex_doit("cat debian/$ext$script.debhelper >> $tmp/DEBIAN/$script");
		doit("chown","0:0","$tmp/DEBIAN/$script");
		doit("chmod",755,"$tmp/DEBIAN/$script");
	}
}

1
