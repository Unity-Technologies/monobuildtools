use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;
use lib ('external/buildscripts', "../../Tools/perl_lib","perl_lib", 'external/buildscripts/perl_lib');
use Tools qw(InstallNameTool);

print ">>> PATH in Build All = $ENV{PATH}\n\n";

my $currentdir = getcwd();

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);

my $buildscriptsdir = "$monoroot/external/buildscripts";
my $addtoresultsdistdir = "$buildscriptsdir/add_to_build_results/monodistribution";
my $monoprefix = "$monoroot/tmp/monoprefix";
my $buildsroot = "$monoroot/builds";
my $distdir = "$buildsroot/monodistribution";
my $buildMachine = $ENV{UNITY_THISISABUILDMACHINE};

# This script should not be ran on windows, if it is, kindly call the wrapper
# to switch over to cygwin
if ($^O eq "MSWin32")
{
	print(">>> build.pl called from Windows.  Switching over to cygwin\n");
	system("$buildscriptsdir/build_win_wrapper.pl", @ARGV) eq 0 or die("\n");
	exit 0;
}

system("source","~/.profile");

my $build=0;
my $clean=0;
my $jobs=8;
my $test=0;
my $artifact=0;
my $debug=0;
my $disableMcs=0;
my $buildUsAndBoo=0;
my $artifactsCommon=0;
my $runRuntimeTests=1;
my $runClasslibTests=1;
my $checkoutOnTheFly=0;
my $forceDefaultBuildDeps=0;
my $existingMonoRootPath = '';
my $unityRoot = '';
my $sdk = '';
my $arch32 = 0;
my $winPerl = "";
my $winMonoRoot = "";
my $msBuildVersion = "14.0";
my $buildDeps = "";

# Handy troubleshooting/niche options
my $skipMonoMake=0;

print(">>> Build All Args = @ARGV\n");

GetOptions(
	'build=i'=>\$build,
	'clean=i'=>\$clean,
	'test=i'=>\$test,
	'artifact=i'=>\$artifact,
	'artifactscommon=i'=>\$artifactsCommon,
	'debug=i'=>\$debug,
	'disablemcs=i'=>\$disableMcs,
	'buildusandboo=i'=>\$buildUsAndBoo,
	'runtimetests=i'=>\$runRuntimeTests,
	'classlibtests=i'=>\$runClasslibTests,
	'arch32=i'=>\$arch32,
	'jobs=i'=>\$jobs,
	'sdk=s'=>\$sdk,
	'existingmono=s'=>\$existingMonoRootPath,
	'unityroot=s'=>\$unityRoot,
	'skipmonomake=i'=>\$skipMonoMake,
	'winperl=s'=>\$winPerl,
	'winmonoroot=s'=>\$winMonoRoot,
	'msbuildversion=s'=>\$msBuildVersion,
	'checkoutonthefly=i'=>\$checkoutOnTheFly,
	'builddeps=s'=>\$buildDeps,
	'forcedefaultbuilddeps=i'=>\$forceDefaultBuildDeps,
) or die ("illegal cmdline options");

print ">>> Mono checkout = $monoroot\n";

print(">> System Info : \n");
system("uname", "-a");

my $monoRevision = `git rev-parse HEAD`;
chdir("$buildscriptsdir") eq 1 or die ("failed to chdir : $buildscriptsdir\n");
my $buildScriptsRevision = `git rev-parse HEAD`;
chdir("$monoroot") eq 1 or die ("failed to chdir : $monoroot\n");

print(">>> Mono Revision = $monoRevision\n");
print(">>> Build Scripts Revision = $buildScriptsRevision\n");

# Do any settings agnostic per-platform stuff
my $externalBuildDeps = "";

if ($buildDeps ne "" && not $forceDefaultBuildDeps)
{
	$externalBuildDeps = $buildDeps;
}
else
{
	$externalBuildDeps = "$monoroot/external/mono-build-deps";
}

my $existingExternalMonoRoot = "$externalBuildDeps/mono";
my $existingExternalMono = "";
my $monoHostArch = "";
if($^O eq "linux")
{
	$monoHostArch = $arch32 ? "i686" : "x86_64";
	$existingExternalMono = "$existingExternalMonoRoot/linux";
}
elsif($^O eq 'darwin')
{
	$monoHostArch = $arch32 ? "i386" : "x86_64";
	$existingExternalMono = "$existingExternalMonoRoot/osx";
}
else
{
	$monoHostArch = "i686";
	$existingExternalMono = "$existingExternalMonoRoot/win";
	
	# We only care about an existing mono if we need to build.
	# So only do this path clean up if we are building.
	if ($build)
	{
		if ($existingMonoRootPath ne "" && not $existingMonoRootPath =~ /^\/cygdrive/)
		{
			$existingMonoRootPath = `cygpath -u $existingMonoRootPath`;
			chomp($existingMonoRootPath);
		}
		
		$existingMonoRootPath =~ tr/\\//d;
	}
}

print(">>> Existing Mono = $existingMonoRootPath\n");
print(">>> Mono Arch = $monoHostArch\n");

if ($build)
{
	my $platformflags = '';
	my $host = '';
	my $mcs = '';
	
	my @configureparams = ();
	#push @configureparams, "--cache-file=$cachefile";
	
	push @configureparams, "--disable-mcs-build" if($disableMcs);
	push @configureparams, "--with-glib=embedded";
	push @configureparams, "--disable-nls";  #this removes the dependency on gettext package
	push @configureparams, "--prefix=$monoprefix";
	push @configureparams, "--with-monotouch=no";
	push @configureparams, "--with-mcs-docs=no";
	
	if ($existingMonoRootPath eq "")
	{
		print(">>> No existing mono supplied.  Checking for external...\n");
		
		if (!(-d "$externalBuildDeps"))
		{
			if (not $checkoutonthefly)
			{
				print(">>> No external build deps found.  Might as well try to check them out.  If it fails, we'll continue and trust mono is in your PATH\n");
			}

			# Check out on the fly
			print(">>> Checking out mono build dependencies to : $externalBuildDeps\n");
			my $repo = "https://ono.unity3d.com/unity-extra/mono-build-deps";
			print(">>> Cloning $repo at $externalBuildDeps\n");
			my $checkoutResult = system("hg", "clone", $repo, "$externalBuildDeps");

			if ($checkoutOnTheFly && $checkoutResult ne 0)
			{
				die("failed to checkout mono build dependencies\n");
			}
		}
		
		if (-d "$existingExternalMono")
		{
			print(">>> External mono found at : $existingExternalMono\n");
			
			if (-d "$existingExternalMono/builds")
			{
				print(">>> Mono already extracted at : $existingExternalMono/builds\n");
			}
			
			if (!(-d "$existingExternalMono/builds"))
			{
				# We need to extract builds.zip
				print(">>> Extracting mono builds.zip...\n");
				system("unzip", "$existingExternalMono/builds.zip", "-d", "$existingExternalMono") eq 0 or die("failed to extract mono builds.zip\n");
			}
			
			$existingMonoRootPath = "$existingExternalMono/builds";
		}
		else
		{
			print(">>> No external mono found.  Trusting a new enough mono is in your PATH.\n");
		}
	}
	
	if ($existingMonoRootPath ne "" && !(-d $existingMonoRootPath))
	{
		die("Existing mono not found at : $existingMonoRootPath\n");
	}
	
	if($^O eq "linux")
	{
		push @configureparams, "--host=$monoHostArch-pc-linux-gnu";
		
		push @configureparams, "--disable-parallel-mark";  #this causes crashes
		
		my $archflags = '';
		if ($arch32)
		{
			$archflags = '-m32';
		}
		
		if ($debug)
		{
			$ENV{CFLAGS} = "$archflags -g -O0";
		}
		else
		{
			$ENV{CFLAGS} = "$archflags -Os";  #optimize for size
		}
	}
	elsif($^O eq 'darwin')
	{
		# Set up mono for bootstrapping
		if ($existingMonoRootPath eq "")
		{
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
		}
		
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
			$ENV{'CC'} = "clang";
			$ENV{'CXX'} = "clang++";
			
			$sdkPath = "$xcodePath/Developer/SDKs/MacOSX$sdkversion.sdk";
			$ENV{MACSDKOPTIONS} = "-D_XOPEN_SOURCE -mmacosx-version-min=$macversion -isysroot $sdkPath";
		}

		if ($externalBuildDeps ne "")
		{
			print "\n";
			print ">>> Building autoconf, automake, and libtool if needed...\n";
			my $autoconfVersion = "2.69";
			my $automakeVersion = "1.15";
			my $libtoolVersion = "2.4.6";
			my $autoconfDir = "$externalBuildDeps/autoconf-$autoconfVersion";
			my $automakeDir = "$externalBuildDeps/automake-$automakeVersion";
			my $libtoolDir = "$externalBuildDeps/libtool-$libtoolVersion";
			my $builtToolsDir = "$externalBuildDeps/built-tools";

			$ENV{PATH} = "$builtToolsDir/bin:$ENV{PATH}";

			if (!(-d "$autoconfDir"))
			{
				chdir("$externalBuildDeps") eq 1 or die ("failed to chdir to external directory\n");
				system("tar xzf autoconf-$autoconfVersion.tar.gz") eq 0  or die ("failed to extract autoconf\n");

				chdir("$autoconfDir") eq 1 or die ("failed to chdir to autoconf directory\n");
				system("./configure --prefix=$builtToolsDir") eq 0 or die ("failed to configure autoconf\n");
				system("make") eq 0 or die ("failed to make autoconf\n");
				system("make install") eq 0 or die ("failed to make install autoconf\n");

				chdir("$monoroot") eq 1 or die ("failed to chdir to $monoroot\n");
			}

			if (!(-d "$automakeDir"))
			{
				chdir("$externalBuildDeps") eq 1 or die ("failed to chdir to external directory\n");
				system("tar xzf automake-$automakeVersion.tar.gz") eq 0  or die ("failed to extract automake\n");

				chdir("$automakeDir") eq 1 or die ("failed to chdir to automake directory\n");
				system("./configure --prefix=$builtToolsDir") eq 0 or die ("failed to configure automake\n");
				system("make") eq 0 or die ("failed to make automake\n");
				system("make install") eq 0 or die ("failed to make install automake\n");

				chdir("$monoroot") eq 1 or die ("failed to chdir to $monoroot\n");

			}

			if (!(-d "$libtoolDir"))
			{
				chdir("$externalBuildDeps") eq 1 or die ("failed to chdir to external directory\n");
				system("tar xzf libtool-$libtoolVersion.tar.gz") eq 0  or die ("failed to extract libtool\n");
			
				chdir("$libtoolDir") eq 1 or die ("failed to chdir to libtool directory\n");
				system("./configure --prefix=$builtToolsDir") eq 0 or die ("failed to configure libtool\n");
				system("make") eq 0 or die ("failed to make libtool\n");
				system("make install") eq 0 or die ("failed to make install libtool\n");

				chdir("$monoroot") eq 1 or die ("failed to chdir to $monoroot\n");
			}

			$ENV{'LIBTOOLIZE'} = "$builtToolsDir/bin/libtoolize";
			$ENV{'LIBTOOL'} = "$builtToolsDir/bin/libtool";
		}
		
		$ENV{CFLAGS} = "$ENV{CFLAGS} -g -O0" if $debug;
		$ENV{CFLAGS} = "$ENV{CFLAGS} -Os" if not $debug; #optimize for size
		
		$ENV{CC} = "$ENV{CC} -arch $monoHostArch";
		$ENV{CXX} = "$ENV{CXX} -arch $monoHostArch";
		
		# Add OSX specific autogen args
		push @configureparams, "--host=$monoHostArch-apple-darwin12.2.0";
		
		# Need to define because Apple's SIP gets in the way of us telling mono where to find this
		push @configureparams, "--with-libgdiplus=$addtoresultsdistdir/lib/libgdiplus.dylib";
		
		print "\n";
		print ">>> Setting environment:\n";
		print ">>> PATH = ".$ENV{PATH}."\n";
		print ">>> C_INCLUDE_PATH = ".$ENV{C_INCLUDE_PATH}."\n";
		print ">>> CPLUS_INCLUDE_PATH = ".$ENV{CPLUS_INCLUDE_PATH}."\n";
		print ">>> CFLAGS = ".$ENV{CFLAGS}."\n";
		print ">>> CXXFLAGS = ".$ENV{CXXFLAGS}."\n";
		print ">>> CC = ".$ENV{CC}."\n";
		print ">>> CXX = ".$ENV{CXX}."\n";
		print ">>> CPP = ".$ENV{CPP}."\n";
		print ">>> CXXPP = ".$ENV{CXXPP}."\n";
		print ">>> LD = ".$ENV{LD}."\n";
		print ">>> LDFLAGS = ".$ENV{LDFLAGS}."\n";
		print "\n";
	}
	else
	{
		# Fixes a line ending issue that happens on windows when we try to run autogen.sh
		$ENV{'SHELLOPTS'} = "igncr";
			
		push @configureparams, "--host=$monoHostArch-pc-mingw32";
	}

	print ">>> Existing Mono : $existingMonoRootPath\n\n";
	$ENV{'PATH'} = "$existingMonoRootPath/bin:$ENV{'PATH'}";
	
	print ">>> PATH before Build = $ENV{PATH}\n\n";
	
	print(">>> mcs Information : \n");
	system("which", "mcs");
	system("mcs", "--version");
	print("\n");

	print ">>> Checking on some tools...\n";
	system("which", "autoconf");
	system("autoconf", "--version");

	system("which", "automake");
	system("automake", "--version");

	system("which", "libtool");
	system("libtool", "--version");

	system("which", "libtoolize");
	system("libtoolize", "--version");
	print("\n");

	print ">>> LIBTOOLIZE before Build = $ENV{LIBTOOLIZE}\n";
	print ">>> LIBTOOL before Build = $ENV{LIBTOOL}\n";
	
	chdir("$monoroot") eq 1 or die ("failed to chdir 2\n");
	
	if (not $skipMonoMake)
	{
		if ($clean)
		{
			print(">>> Cleaning $monoprefix\n");
			rmtree($monoprefix);
			
			# Avoid "source directory already configured" ...
			system('rm', '-f', 'config.status', 'eglib/config.status', 'libgc/config.status');

			print("\n>>> Calling autogen in mono\n");
			system('./autogen.sh', @configureparams) eq 0 or die ('failing autogenning mono');
			
			print("\n>>> Calling make clean in mono\n");
			system("make","clean") eq 0 or die ("failed to make clean\n");
		}
		
		print("\n>>> Calling make\n");
		system("make $mcs -j$jobs") eq 0 or die ('Failed to make\n');
		
		print("\n>>> Calling make install\n");
		system("make install") eq 0 or die ("Failed to make install\n");
	}
	
	if ($^O eq "cygwin")
	{
		system("$winPerl", "$winMonoRoot/external/buildscripts/build_runtime_vs.pl", "--build=$build", "--arch32=$arch32", "--msbuildversion=$msBuildVersion", "--clean=$clean", "--debug=$debug") eq 0 or die ('failing building mono with VS\n');
		
		# Copy over the VS built stuff that we want to use instead into the prefix directory
		my $archNameForBuild = $arch32 ? 'Win32' : 'x64';
		system("cp $monoroot/msvc/$archNameForBuild/bin/mono.exe $monoprefix/bin/.") eq 0 or die ("failed copying mono.exe\n");
		system("cp $monoroot/msvc/$archNameForBuild/bin/mono-2.0.dll $monoprefix/bin/.") eq 0 or die ("failed copying mono-2.0.dll\n");
		system("cp $monoroot/msvc/$archNameForBuild/bin/mono-2.0.pdb $monoprefix/bin/.") eq 0 or die ("failed copying mono-2.0.pdb\n");
	}
	
	system("cp -R $addtoresultsdistdir/bin/. $monoprefix/bin/") eq 0 or die ("Failed copying $addtoresultsdistdir/bin to $monoprefix/bin\n");
}
else
{
	print(">>> Skipping build\n");
}

if ($buildUsAndBoo)
{
	print(">>> Building Unity Script and Boo...\n");
	system("perl", "$buildscriptsdir/build_us_and_boo.pl") eq 0 or die ("Failed builidng Unity Script and Boo\n");
}
else
{
	print(">>> Skipping build Unity Script and Boo\n");
}

if ($artifact)
{
	print(">>> Creating artifact...\n");

	if ($artifactsCommon)
	{
		print(">>> Creating common artifacts...\n");
		print(">>> distribution directory = $distdir\n");
		
		if (!(-d "$distdir"))
		{
			system("mkdir -p $distdir") eq 0 or die("failed to make directory $distdir\n");
		}
		
		system("cp -R $addtoresultsdistdir/. $distdir/") eq 0 or die ("Failed copying $addtoresultsdistdir to $distdir\n");
		
		$File::Copy::Recursive::CopyLink = 0;  #make sure we copy files as files and not as symlinks, as TC unfortunately doesn't pick up symlinks.

		my $distdirlibmono = "$distdir/lib/mono";
		system("cp -r $monoprefix/lib/mono $distdir/lib");
		
		system("cp -r $monoprefix/bin $distdir/") eq 0 or die ("failed copying bin folder\n");
		system("cp -r $monoprefix/etc $distdir/") eq 0 or die("failed copying etc folder\n");

		system("cp -R $externalBuildDeps/reference-assemblies/unity $distdirlibmono/unity");
 		system("cp -R $externalBuildDeps/reference-assemblies/unity_web $distdirlibmono/unity_web");

		# now remove nunit from a couple places (but not all, we need some of them)
		system("rm -rf $distdirlibmono/2.0/nunit*");
		system("rm -rf $distdirlibmono/gac/nunit*");
		
		if (-f "$monoroot/ZippedClasslibs.tar.gz")
		{
			system("rm -f $monoroot/ZippedClasslibs.tar.gz") eq 0 or die("Failed to clean existing ZippedClasslibs.tar.gz\n");
		}
		
		print(">>> Creating ZippedClasslibs.tar.gz\n");
		print(">>> Changing directory to : $buildsroot\n");
		chdir("$buildsroot");
		system("tar -hpczf ../ZippedClasslibs.tar.gz *") eq 0 or die("Failed to zip up classlibs\n");
		print(">>> Changing directory back to : $currentdir\n");
		chdir("$currentdir");
	}
	
	# Do the platform specific logic to create the builds output structure that we want
	
	my $embedDirRoot = "$buildsroot/embedruntimes";
	my $embedDirArchDestination = "";
	my $distDirArchBin = "";
	my $versionsOutputFile = "";
	if($^O eq "linux")
	{
		$embedDirArchDestination = $arch32 ? "$embedDirRoot/linux32" : "$embedDirRoot/linux64";
		$distDirArchBin = $arch32 ? "$distdir/bin-linux32" : "$distdir/bin-linux64";
		$versionsOutputFile = $arch32 ? "$buildsroot/versions-linux32.txt" : "$buildsroot/versions-linux64.txt";
	}
	elsif($^O eq 'darwin')
	{
		# Note these tmp directories will get merged into a single 'osx' directory later by a parent script
		$embedDirArchDestination = "$embedDirRoot/osx-tmp-$monoHostArch";
		$distDirArchBin = "$distdir/bin-osx-tmp-$monoHostArch";
		$versionsOutputFile = $arch32 ? "$buildsroot/versions-osx32.txt" : "$buildsroot/versions-osx64.txt";
	}
	else
	{
		$embedDirArchDestination = $arch32 ? "$embedDirRoot/win32" : "$embedDirRoot/win64";
		$distDirArchBin = $arch32 ? "$distdir/bin" : "$distdir/bin-x64";
		$versionsOutputFile = $arch32 ? "$buildsroot/versions-win32.txt" : "$buildsroot/versions-win64.txt";
	}
	
	# Make sure the directory for our architecture is clean before we copy stuff into it
	if (-d "$embedDirArchDestination")
	{
		print(">>> Cleaning $embedDirArchDestination\n");
		rmtree($embedDirArchDestination);
	}

	if (-d "$distDirArchBin")
	{
		print(">>> Cleaning $distDirArchBin\n");
		rmtree($distDirArchBin);
	}
	
	system("mkdir -p $embedDirArchDestination");
	system("mkdir -p $distDirArchBin");
	
	# embedruntimes directory setup
	print(">>> Creating embedruntimes directory : $embedDirArchDestination\n");
	if($^O eq "linux")
	{
		print ">>> Copying libmono.so\n";
		system("cp", "$monoroot/mono/mini/.libs/libmonoboehm-2.0.so","$embedDirArchDestination/libmono.so") eq 0 or die ("failed copying libmonoboehm-2.0.so\n");

		print ">>> Copying libmono-static.a\n";
		system("cp", "$monoroot/mono/mini/.libs/libmonoboehm-2.0.a","$embedDirArchDestination/libmono-static.a") eq 0 or die ("failed copying libmonoboehm-2.0.a\n");

		print ">>> Copying libMonoPosixHelper.so\n";
		system("cp", "$monoroot/support/.libs/libMonoPosixHelper.so","$embedDirArchDestination/libMonoPosixHelper.so") eq 0 or die ("failed copying libMonoPosixHelper.so\n");
		
		if ($buildMachine)
		{
			system("strip $embedDirArchDestination/libmono.so") eq 0 or die("failed to strip libmono (shared)\n");
			system("strip $embedDirArchDestination/libMonoPosixHelper.so") eq 0 or die("failed to strip libMonoPosixHelper (shared)\n");
		}
	}
	elsif($^O eq 'darwin')
	{
		# embedruntimes directory setup
 		print ">>> Hardlinking libmono.dylib\n";
 		system("ln","-f", "$monoroot/mono/mini/.libs/libmonoboehm-2.0.1.dylib","$embedDirArchDestination/libmono.0.dylib") eq 0 or die ("failed symlinking libmono.0.dylib\n");

 		print ">>> Hardlinking libmono.a\n";
 		system("ln", "-f", "$monoroot/mono/mini/.libs/libmonoboehm-2.0.a","$embedDirArchDestination/libmono.a") eq 0 or die ("failed symlinking libmono.a\n");
		 
		print "Hardlinking libMonoPosixHelper.dylib\n";
		system("ln","-f", "$monoroot/support/.libs/libMonoPosixHelper.dylib","$embedDirArchDestination/libMonoPosixHelper.dylib") eq 0 or die ("failed symlinking $libtarget/libMonoPosixHelper.dylib\n");
	
		InstallNameTool("$embedDirArchDestination/libmono.0.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/osx/libmono.0.dylib");
		InstallNameTool("$embedDirArchDestination/libMonoPosixHelper.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/osx/libMonoPosixHelper.dylib");
	}
	else
	{
		# embedruntimes directory setup
		system("cp", "$monoprefix/bin/mono-2.0.dll", "$embedDirArchDestination/mono-2.0.dll") eq 0 or die ("failed copying mono-2.0.dll\n");
		system("cp", "$monoprefix/bin/mono-2.0.pdb", "$embedDirArchDestination/mono-2.0.pdb") eq 0 or die ("failed copying mono-2.0.pdb\n");
		system("cp", "$monoprefix/bin/mono-2.0.ilk", "$embedDirArchDestination/mono-2.0.ilk") eq 0 or die ("failed copying mono-2.0.ilk\n");
	}
	
	# monodistribution directory setup
	print(">>> Creating monodistribution directory\n");
	if($^O eq "linux")
	{
		my $distDirArchEtc = $arch32 ? "$distdir/etc-linux32" : "$distdir/etc-linux64";

		if (-d "$distDirArchEtc")
		{
			print(">>> Cleaning $distDirArchEtc\n");
			rmtree($distDirArchEtc);
		}
		
		system("mkdir -p $distDirArchBin");
		system("mkdir -p $distDirArchEtc");
		system("mkdir -p $distDirArchEtc/mono");
		
		system("ln", "-f", "$monoroot/mono/mini/mono-boehm","$distDirArchBin/mono") eq 0 or die("failed symlinking mono executable\n");
		system("ln", "-f", "$monoroot/mono/metadata/pedump","$distDirArchBin/pedump") eq 0 or die("failed symlinking pedump executable\n");
		system('cp', "$monoroot/data/config","$distDirArchEtc/mono/config") eq 0 or die("failed to copy config\n");
	}
	elsif($^O eq 'darwin')
	{
		system("ln", "-f", "$monoroot/mono/mini/mono","$distDirArchBin/mono") eq 0 or die("failed hardlinking mono executable\n");
		system("ln", "-f", "$monoroot/mono/metadata/pedump","$distDirArchBin/pedump") eq 0 or die("failed hardlinking pedump executable\n");
	}
	else
	{
		system("cp", "$monoprefix/bin/mono-2.0.dll", "$distDirArchBin/mono-2.0.dll") eq 0 or die ("failed copying mono-2.0.dll\n");
		system("cp", "$monoprefix/bin/mono-2.0.pdb", "$distDirArchBin/mono-2.0.pdb") eq 0 or die ("failed copying mono-2.0.pdb\n");
		system("cp", "$monoprefix/bin/mono.exe", "$distDirArchBin/mono.exe") eq 0 or die ("failed copying mono.exe\n");
	}
	
	system("chmod", "-R", "755", $distDirArchBin);
	
	# Output version information
	print(">>> Creating version file : $versionsOutputFile\n");
	system("echo \"mono-version =\" > $versionsOutputFile");
	system("$distDirArchBin/mono --version >> $versionsOutputFile");
	system("echo \"unity-mono-revision = $monoRevision\" >> $versionsOutputFile");
	system("echo \"unity-mono-build-scripts-revision = $buildScriptsRevision\" >> $versionsOutputFile");
	my $tmp = `date`;
	system("echo \"build-date = $tmp\" >> $versionsOutputFile");
}
else
{
	print(">>> Skipping artifact creation\n");
}

if ($test)
{
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
		if ($disableMcs)
		{
			print(">>> Skipping classlib unit tests because building the class libs was disabled\n");
		}
		else
		{
			my $classlibTestsDir = "$monoroot/mcs/class";
			chdir("$classlibTestsDir") eq 1 or die ("failed to chdir");
			print("\n>>> Calling make run-test in $runtimeTestsDir\n\n");
			system("make","run-test") eq 0 or die ("classlib tests failed\n");
		}
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