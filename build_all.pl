use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;

system("source","~/.profile");
print ">>> PATH in Build All = $ENV{PATH}\n\n";

my $currentdir = getcwd();

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);

my $buildscriptsdir = "$monoroot/external/buildscripts";
my $monoprefix = "$monoroot/tmp/monoprefix";
my $buildsroot = "$monoroot/builds";
my $embeddir = "$buildsroot/embedruntimes";
my $distdir = "$buildsroot/monodistribution";
my $buildMachine = $ENV{UNITY_THISISABUILDMACHINE};

my $build=0;
my $clean=0;
my $jobs=8;
my $test=0;
my $artifact=0;
my $runRuntimeTests=1;
my $runClasslibTests=1;
my $existingMonoRootPath = '';
my $unityRoot = '';
my $sdk = '';
my $arch32 = 0;
my $winPerl = "";
my $winMonoRoot = "";
my $vsVersion = "10.0";

# TODO by Mike : Figure out how we want to handle building the different archs
my @arches = ('i386','x86_64', 'i686');

# Handy troubleshooting/niche options
my $skipMonoMake=0;

print(">>> Build All Args = @ARGV\n");

GetOptions(
	'build=i'=>\$build,
	'clean=i'=>\$clean,
	'test=i'=>\$test,
	'artifact=i'=>\$artifact,
	'runtimetests=i'=>\$runRuntimeTests,
	'classlibtests=i'=>\$runClasslibTests,
	'jobs=i'=>\$jobs,
	'sdk=s'=>\$sdk,
	'existingmono=s'=>\$existingMonoRootPath,
	'unityroot=s'=>\$unityRoot,
	'skipmonomake=i'=>\$skipMonoMake,
	'winperl=s'=>\$winPerl,
	'winmonoroot=s'=>\$winMonoRoot,
	'vsversion=s'=>\$vsVersion,
) or die ("illegal cmdline options");

print ">>> Mono checkout = $monoroot\n";

chdir("$monoroot") eq 1 or die ("failed to chdir 2");

# Do any settings agnostic per-platform stuff
if($^O eq "linux")
{
}
elsif($^O eq 'darwin')
{
}
else
{
	if (not $existingMonoRootPath =~ /^\/cygdrive/)
	{
		$existingMonoRootPath = `cygpath -u $existingMonoRootPath`;
		chomp($existingMonoRootPath);
	}
	
	$existingMonoRootPath =~ tr/\\//d;

	if (!(-d $existingMonoRootPath))
	{
		die("Existing mono not found at : $existingMonoRootPath\n");
	}
}

print(">>> Existing Mono = $existingMonoRootPath\n");

if ($build)
{
	my $platformflags = '';
	my $host = '';
	my $mcs = '';
	
	my @configureparams = ();
	#push @configureparams, "--cache-file=$cachefile";
	push @configureparams, "--disable-mcs-build";
	push @configureparams, "--with-glib=embedded";
	push @configureparams, "--disable-nls";  #this removes the dependency on gettext package
	push @configureparams, "--prefix=$monoprefix";
	push @configureparams, "--with-monotouch=no";
	push @configureparams, "--with-mcs-docs=no";
	#unshift(@configureparams, "--enable-minimal=aot,logging,com,profiler,debug") if $minimal;
	
	if($^O eq "linux")
	{
		push @configureparams, "--host=i686-pc-linux-gnu";
	}
	elsif($^O eq 'darwin')
	{
		# Set up mono for bootstrapping
		# Find the latest mono version and use that for boostrapping
		my $monoInstalls = '/Library/Frameworks/Mono.framework/Versions';
		my @monoVersions = ();
		
		opendir( my $DIR, $monoInstalls );
		while ( my $entry = readdir $DIR )
		{
			next unless -d $monoInstalls . '/' . $entry;
			next if $entry eq '.' or $entry eq '..' or $entry eq 'Current';
			push @monoVersions, $entry;
		}
		closedir $DIR;
		@monoVersions = sort @monoVersions;
		my $monoVersionToUse = pop @monoVersions;
		$existingMonoRootPath = "$monoInstalls/$monoVersionToUse";
		
		$mcs = "EXTERNAL_MCS=$existingMonoRootPath/bin/mcs";
		
		my $sdkPath = '';
		if ($sdk eq '')
		{
			$sdk='10.11';
		}
		
		my $xcodePath = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform';
		my $macversion = '10.8';
		
		if ($buildMachine)
		{
			if ($unityRoot eq "")
			{
				$unityRoot = abs_path("$monoroot/../../unity/build");
			}
			
			if (!(-d "$unityRoot"))
			{
				die("Could not fine Unity at : $unityRoot , match expected structure or use --unityroot=<path>\n");
			}
			
			# Set up clang toolchain
			$sdkPath = "$unityRoot/External/MacBuildEnvironment/builds/MacOSX$sdk.sdk";
			if (! -d $sdkPath)
			{
				print("Unzipping mac build toolchain\n");
				system("cd $unityRoot; ./jam EditorZips; cd $currentdir");
			}
			$ENV{'CC'} = "$sdkPath/../usr/bin/clang";
			$ENV{'CXX'} = "$sdkPath/../usr/bin/clang++";
			$ENV{'CFLAGS'} = $ENV{MACSDKOPTIONS} = "-D_XOPEN_SOURCE -I$unityRoot/External/MacBuildEnvironment/builds/usr/include -mmacosx-version-min=$macversion -isysroot $sdkPath";
		}
		else
		{
			$sdkPath = "$xcodePath/Developer/SDKs/MacOSX$sdkversion.sdk";
			$ENV{MACSDKOPTIONS} = "-D_XOPEN_SOURCE -mmacosx-version-min=$macversion -isysroot $sdkPath";
		}
		
		# Add OSX specific autogen args
		push @configureparams, "--host=$arch-apple-darwin12.2.0";
		
		die ('OSX not implemented');
	}
	else
	{
		push @configureparams, "--host=i686-pc-mingw32";
	}

	print ">>> Existing Mono : $existingMonoRootPath\n\n";
	$ENV{'PATH'} = "$existingMonoRootPath/bin:$ENV{'PATH'}";
	
	print ">>> PATH before Build = $ENV{PATH}\n\n";
	
	chdir("$monoroot") eq 1 or die ("failed to chdir 2");
	
	if (not $skipMonoMake)
	{
		if ($clean)
		{
			rmtree($monoprefix);
			
			# Avoid "source directory already configured" ...
			system('rm', '-f', 'config.status', 'eglib/config.status', 'libgc/config.status');

			print("\n>>> Calling autogen in mono\n");
			system('./autogen.sh', @configureparams) eq 0 or die ('failing autogenning mono');
			#system('./autogen.sh',"--prefix=$monoprefix", $host, '--with-monotouch=no', '--with-glib=embedded','--with-mcs-docs=no', '--disable-nls', $platformflags) eq 0 or die ('failing autogenning mono');
			print("\n>>> Calling make clean in mono\n");
			system("make","clean") eq 0 or die ("failed to make clean");
		}
		
		print("\n>>> Calling make\n");
		system("make $mcs -j$jobs") eq 0 or die ('Failed running make');
	}
	
	if ($^O eq "cygwin")
	{
		system("$winPerl", "$winMonoRoot/external/buildscripts/build_runtime_vs.pl", "--build=$build", "--arch32=$arch32", "--vsversion=$vsVersion") eq 0 or die ('failing building mono with VS');
	}
	
	print("\n>>> Calling make install\n");
	system("make install") eq 0 or die ("Failed running make install");
}
else
{
	print(">>> Skipping build\n");
}

if ($artifact)
{
	print ">>> rmtree-ing $buildsroot because we're on a buildserver, and want to make sure we don't include old artifacts\n";
	
	# CopyIgnoringHiddenFiles
	system("cp -R $buildscriptsdir/add_to_build_results/monodistribution/. $distdir/");
	
	$File::Copy::Recursive::CopyLink = 0;  #make sure we copy files as files and not as symlinks, as TC unfortunately doesn't pick up symlinks.

	my $distdirlibmono = "$distdir/lib/mono";
	my @profiles = ("2.0","3.5","4.0","4.5");
	system("mkdir -p $distdirlibmono");
	for my $profile (@profiles)
	{
		my $tmpdest = "$distdirlibmono/$profile";
		system("mkdir -p $tmpdest");
		system("cp -r $monoprefix/lib/mono/$profile $tmpdest");
		if ($buildMachine)
		{
			system("rm -f $tmpdest/*.mdb");
		}
	}
	system("cp -r $monoprefix/bin $distdir/") eq 0 or die ("failed copying bin folder");
	system("cp -r $monoprefix/etc $distdir/") eq 0 or die("failed copying etc folder");
	system("cp -r $monoprefix/lib/mono/gac $distdirlibmono") eq 0 or die("failed copying gac");
	system("cp -r $monoprefix/lib/mono/xbuild-frameworks $distdirlibmono") eq 0 or die("failed copying xbuild-frameworks");

	# TODO by Mike : Is this stuff needed anymore?
	# Fake support for unity and unity_web until we move completely to 4.0
	# system("rm -rf $monodistro/lib/mono/unity $monodistro/lib/mono/unity_web");
	# system("cp -R $monodistro/lib/mono/2.0 $monodistro/lib/mono/unity");
	# system("cp -R $monodistro/lib/mono/2.0 $monodistro/lib/mono/unity_web");

	# now remove nunit
	for my $profile (@profiles)
	{
		system("rm -rf $distdirlibmono/$profile/nunit*");
	}
	
	system("rm -rf $distdirlibmono/gac/nunit*");

	#zip up the results for teamcity
	chdir("$buildsroot");
	
	# TODO : DOes this make sense anymore?
	#system("tar -hpczf ../ZippedClasslibs.tar.gz *") && die("Failed to zip up classlibs for teamcity");
}

	
if ($test)
{
	# Do platform specific stuff to prepare for the tests to run
	if($^O eq "linux")
	{
	}
	elsif($^O eq 'darwin')
	{
		# TODO sym link in libgdi to required locations
	}
	else
	{
	}
	
	if ($runRuntimeTests)
	{
		my $runtimeTestsDir = "$monoroot/mono/mini";
		chdir("$runtimeTestsDir") eq 1 or die ("failed to chdir");
		print("\n>>> Calling make check in $runtimeTestsDir\n\n");
		system("make","check") eq 0 or die ("runtime tests failed\n");
	}
	
	else
	{
		print(">>> Skipping runtime unit tests\n");
	}
	
	if ($runClasslibTests)
	{
		my $classlibTestsDir = "$monoroot/mcs/class";
		chdir("$classlibTestsDir") eq 1 or die ("failed to chdir");
		print("\n>>> Calling make run-test in $runtimeTestsDir\n\n");
		system("make","run-test") eq 0 or die ("classlib tests failed\n");
	}
	else
	{
		print(">>> Skipping classlib unit tests\n");
	}
}
else
{
	print(">>> Skipping unit tests\n");
}

chdir ($currentdir);