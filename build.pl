use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;
use lib ('external/buildscripts', "../../Tools/perl_lib","perl_lib", 'external/buildscripts/perl_lib');
use Tools qw(InstallNameTool);

system("source","~/.profile");
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
my $existingMonoRootPath = '';
my $unityRoot = '';
my $sdk = '';
my $arch32 = 0;
my $winPerl = "";
my $winMonoRoot = "";
my $msBuildVersion = "14.0";

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
) or die ("illegal cmdline options");

print ">>> Mono checkout = $monoroot\n";

chdir("$monoroot") eq 1 or die ("failed to chdir : $monoroot\n");

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
	
	my $monoHostArch = $arch32 ? "i686" : "x86_64";
	
	print(">>> Mono Arch = $monoHostArch\n");
	
	my @configureparams = ();
	#push @configureparams, "--cache-file=$cachefile";
	
	push @configureparams, "--disable-mcs-build" if($disableMcs);
	push @configureparams, "--with-glib=embedded";
	push @configureparams, "--disable-nls";  #this removes the dependency on gettext package
	push @configureparams, "--prefix=$monoprefix";
	push @configureparams, "--with-monotouch=no";
	push @configureparams, "--with-mcs-docs=no";
	
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
			$ENV{'CC'} = "clang";
			$ENV{'CXX'} = "clang++";
			
			$sdkPath = "$xcodePath/Developer/SDKs/MacOSX$sdkversion.sdk";
			$ENV{MACSDKOPTIONS} = "-D_XOPEN_SOURCE -mmacosx-version-min=$macversion -isysroot $sdkPath";
		}
		
		$ENV{CFLAGS} = "$ENV{CFLAGS} -g -O0" if $debug;
		$ENV{CFLAGS} = "$ENV{CFLAGS} -Os" if not $debug; #optimize for size
		
		$ENV{CC} = "$ENV{CC} -arch $monoHostArch";
		$ENV{CXX} = "$ENV{CXX} -arch $monoHostArch";
		
		# TODO by Mike : Copied from old implementation.  What's the purpose of clearing these?
		$ENV{mono_cv_uscore} = '';
		$ENV{mono_cv_clang} = '';
		$ENV{cv_mono_sizeof_sunpath} = '';
		$ENV{ac_cv_func_posix_getpwuid_r} = '';
		$ENV{ac_cv_func_backtrace_symbols} = '';
		
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
		system("cp $monoroot/msvc/$archNameForBuild/bin/mono-2.0.ilk $monoprefix/bin/.") eq 0 or die ("failed copying mono-2.0.ilk\n");
	}
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
	
	# CopyIgnoringHiddenFiles
	if ($artifactsCommon)
	{
		system("cp -R $addtoresultsdistdir/. $distdir/");
		
		$File::Copy::Recursive::CopyLink = 0;  #make sure we copy files as files and not as symlinks, as TC unfortunately doesn't pick up symlinks.

		my $distdirlibmono = "$distdir/lib/mono";
		my @profiles = ("2.0","3.5","4.0","4.5");
		system("mkdir -p $distdirlibmono");
		for my $profile (@profiles)
		{
			system("mkdir -p $distdirlibmono");
			system("cp -r $monoprefix/lib/mono/$profile $distdirlibmono");
			if ($buildMachine)
			{
				system("rm -f $distdirlibmono/$profile/*.mdb");
			}
		}
		
		#TODO by Mike : Deal with copying to expected structure
		
		system("cp -r $monoprefix/bin $distdir/") eq 0 or die ("failed copying bin folder\n");
		system("cp -r $monoprefix/etc $distdir/") eq 0 or die("failed copying etc folder\n");
		system("cp -r $monoprefix/lib/mono/gac $distdirlibmono") eq 0 or die("failed copying gac\n");
		system("cp -r $monoprefix/lib/mono/xbuild-frameworks $distdirlibmono") eq 0 or die("failed copying xbuild-frameworks\n");

		# now remove nunit
		for my $profile (@profiles)
		{
			system("rm -rf $distdirlibmono/$profile/nunit*");
		}
		
		system("rm -rf $distdirlibmono/gac/nunit*");
	}
	
	# Do the platform specific logic to create the builds output structure that we want
	
	my $embedDirRoot = "$buildsroot/embedruntimes";
	my $embedDirArchDestination = "";
	my $distDirArchBin = "";
	if($^O eq "linux")
	{
		$embedDirArchDestination = $arch32 ? "$embedDirRoot/linux32" : "$embedDirRoot/linux64";
		$distDirArchBin = $arch32 ? "$distdir/bin-linux32" : "$distdir/bin-linux64";
	}
	elsif($^O eq 'darwin')
	{
		# Note these tmp directories will get merged into a single 'osx' directory later by a parent script
		$embedDirArchDestination = $arch32 ? "$embedDirRoot/osx-tmp-i686" : "$embedDirRoot/osx-tmp-x86_64";
		$distDirArchBin = $arch32 ? "$distdir/bin-osx-tmp-i686" : "$distdir/bin-osx-tmp-x86_64";
	}
	else
	{
		$embedDirArchDestination = $arch32 ? "$embedDirRoot/win32" : "$embedDirRoot/win64";
		$distDirArchBin = $arch32 ? "$distdir/bin" : "$distdir/bin-x64";
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
	
		# TODO : Jon thinking about these two
		# InstallNameTool("$libtarget/libmono.0.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/$os/libmono.0.dylib");
		# InstallNameTool("$libtarget/libMonoPosixHelper.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/$os/libMonoPosixHelper.dylib");
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
		system("chmod", "-R", "755", $distDirArchBin);
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
	
	# TODO by Mike : Is this needed?
	# if ($buildMachine)
	# {
	# 	system("echo mono-runtime-$platform = $ENV{'BUILD_VCS_NUMBER'} > $buildsroot\\versions.txt");
	# }
}
else
{
	print(">>> Skipping artifact creation\n");
}

if ($test)
{
	# Do platform specific stuff to prepare for the tests to run
	if($^O eq "linux")
	{
	}
	elsif($^O eq 'darwin')
	{
		# TODO by Mike : Remove if the --with-libgdiplus argument works
		# Need to copy in libgdi into a few places so that the unit tests can pass because of Apple's SIP
		# my $libgdiSource = "$addtoresultsdistdir/lib/libgdiplus.dylib";
		# copy("$libgdiSource", "$monoroot/mcs/class/Microsoft.Build.Tasks/libgdiplus.dylib");
		# copy("$libgdiSource", "$monoroot/mcs/class/System.Drawing/libgdiplus.dylib");
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