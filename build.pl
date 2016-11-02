use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;
use lib ('external/buildscripts', "../../Tools/perl_lib","perl_lib", 'external/buildscripts/perl_lib');
use Tools qw(InstallNameTool);
use PrepareAndroidSDK;

print ">>> PATH in Build All = $ENV{PATH}\n\n";

my $currentdir = getcwd();

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);

my $buildscriptsdir = "$monoroot/external/buildscripts";
my $addtoresultsdistdir = "$buildscriptsdir/add_to_build_results/monodistribution";
my $buildsroot = "$monoroot/builds";
my $distdir = "$buildsroot/monodistribution";
my $buildMachine = $ENV{UNITY_THISISABUILDMACHINE};

# This script should not be ran on windows, if it is, kindly call the wrapper
# to switch over to cygwin
if ($^O eq "MSWin32")
{
	print(">>> build.pl called from Windows.  Switching over to cygwin\n");
	system("perl", "$buildscriptsdir/build_win_wrapper.pl", @ARGV) eq 0 or die("\n");
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
my $sdk = '';
my $arch32 = 0;
my $winPerl = "";
my $winMonoRoot = "";
my $msBuildVersion = "14.0";
my $buildDeps = "";
my $android=0;
my $androidArch = "";
my $iphone=0;
my $iphoneArch = "";
my $iphoneCross=0;
my $iphoneSimulator=0;
my $iphoneSimulatorArch="";

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
	'skipmonomake=i'=>\$skipMonoMake,
	'winperl=s'=>\$winPerl,
	'winmonoroot=s'=>\$winMonoRoot,
	'msbuildversion=s'=>\$msBuildVersion,
	'checkoutonthefly=i'=>\$checkoutOnTheFly,
	'builddeps=s'=>\$buildDeps,
	'forcedefaultbuilddeps=i'=>\$forceDefaultBuildDeps,
	'android=i'=>\$android,
	'androidarch=s'=>\$androidArch,
	'iphone=i'=>\$iphone,
	'iphonearch=s'=>\$iphoneArch,
	'iphonecross=i'=>\$iphoneCross,
	'iphonesimulator=i'=>\$iphoneSimulator,
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

if ($androidArch ne "")
{
	$android = 1;
}

if ($iphoneArch ne "")
{
	$iphone = 1;
}

if($iphoneSimulator)
{
	if ($arch32)
	{
		$iphoneSimulatorArch = "i386";
	}
	else
	{
		$iphoneSimulatorArch = "x86_64";
	}
}

my $isDesktopBuild = 1;
if ($android || $iphone || $iphoneCross || $iphoneSimulator)
{
	$isDesktopBuild = 0;

	# Disable building of the class libraries by default when building the android runtime
	# since we don't care about a class library build in this situation (as of writing this at least)
	# but only if the test flag is not set.  If the test flag was set, we'd need to build the classlibs 
	# in order to run the tests
	$disableMcs = 1 if(!($test));
}

# Do any settings agnostic per-platform stuff
my $externalBuildDeps = "";

if ($buildDeps ne "" && not $forceDefaultBuildDeps)
{
	$externalBuildDeps = $buildDeps;
}
else
{
	$externalBuildDeps = "$monoroot/../../mono-build-deps/build";
}

$externalBuildDeps = abs_path($externalBuildDeps);

my $existingExternalMonoRoot = "$externalBuildDeps/mono";
my $existingExternalMono = "";
my $monoHostArch = "";
my $monoprefix = "$monoroot/tmp";
my $runningOnWindows=0;
if($^O eq "linux")
{
	$monoHostArch = $arch32 ? "i686" : "x86_64";
	$existingExternalMono = "$existingExternalMonoRoot/linux";
}
elsif($^O eq 'darwin')
{
	$monoHostArch = $arch32 ? "i386" : "x86_64";
	$existingExternalMono = "$existingExternalMonoRoot/osx";

	# From Massi: I was getting failures in install_name_tool about space
	# for the commands being too small, and adding here things like
	# $ENV{LDFLAGS} = '-headerpad_max_install_names' and
	# $ENV{LDFLAGS} = '-headerpad=0x40000' did not help at all (and also
	# adding them to our final gcc invocation to make the bundle).
	# Lucas noticed that I was lacking a Mono prefix, and having a long
	# one would give us space, so here is this silly looong prefix.
	$monoprefix = "$monoroot/tmp/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting";
}
else
{
	$monoHostArch = "i686";
	$existingExternalMono = "$existingExternalMonoRoot/win";
	$runningOnWindows = 1;
	
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

if ($runningOnWindows)
{
	# Fixes a line ending issue that happens on windows when we try to run autogen.sh
	$ENV{'SHELLOPTS'} = "igncr";
}

print(">>> Existing Mono = $existingMonoRootPath\n");
print(">>> Mono Arch = $monoHostArch\n");

if ($build)
{
	my $platformflags = '';
	my $host = '';
	my $mcs = '';

	my $iphoneCrossAbi = "arm-apple-darwin10";
	my $iphoneCrossMonoBinToUse = "$monoroot/builds/monodistribution/bin";

	my @configureparams = ();

	# TODO by Mike : Add back.  The android build script was using it
	#push @configureparams, "--cache-file=$cachefile";
	
	push @configureparams, "--disable-mcs-build" if($disableMcs);
	push @configureparams, "--with-glib=embedded";
	push @configureparams, "--disable-nls";  #this removes the dependency on gettext package
	push @configureparams, "--disable-btls";  #this removes the dependency on cmake to build btls for now
	push @configureparams, "--with-mcs-docs=no";
	push @configureparams, "--prefix=$monoprefix";

	if ($isDesktopBuild)
	{
		push @configureparams, "--with-monotouch=no";
	}
	
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

	my $macSdkPath = "";
	my $macversion = '10.8';
	my $darwinVersion = "9";
	if ($^O eq 'darwin')
	{
		if ($sdk eq '')
		{
			$sdk='10.11';
		}

		my $macBuildEnvDir = "$externalBuildDeps/MacBuildEnvironment";
		$macSdkPath = "$macBuildEnvDir/builds/MacOSX$sdk.sdk";
		if (! -d $macSdkPath)
		{
			print(">>> Unzipping mac build toolchain\n");
			system("$externalBuildDeps/unzip", '-qd', "$macBuildEnvDir", "$macBuildEnvDir/builds.zip") eq 0 or die ("failed unzipping mac build toolchain\n");
		}
	}

	if ($iphone || $iphoneSimulator)
	{
		if ($runningOnWindows)
		{
			die("This build is not supported on Windows\n");
		}

		my $iosBuildEnvDir = "$externalBuildDeps/iOSBuildEnvironment";
		my $iosXcodeDefaultToolchainRoot = "$iosBuildEnvDir/builds/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain";

		if (! -d "$iosBuildEnvDir/builds")
		{
			print(">>> Unzipping ios build toolchain\n");
			system("$externalBuildDeps/unzip", '-qd', "$iosBuildEnvDir/builds", "$iosBuildEnvDir/builds.zip") eq 0 or die ("failed unzipping ios build toolchain\n");
		}

		$ENV{PATH} = "$iosXcodeDefaultToolchainRoot/usr/bin:$iosBuildEnvDir/builds/Xcode.app/Contents/Developer/usr/bin:$ENV{PATH}";
		# Need to keep our libtool in front
		$ENV{PATH} = "$externalBuildDeps/built-tools/bin:$ENV{PATH}";

		if ($iphone)
		{
			my $iosSdkVersion = "9.3";
			my $iphoneOsMinVersion = "3.0";
			my $iosSdkRoot = "$iosBuildEnvDir/builds/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS$iosSdkVersion.sdk";

			print(">>> iOS Build Environment = $iosBuildEnvDir\n");
			print(">>> iOS SDK Version = $iosSdkVersion\n");
			print(">>> iOS SDK Root = $iosSdkRoot\n");
			print(">>> iPhone Arch = $iphoneArch\n");

			$ENV{PATH} = "$iosSdkRoot/usr/bin:$ENV{PATH}";

			$ENV{C_INCLUDE_PATH} = "$iosSdkRoot/usr/include";
			$ENV{CPLUS_INCLUDE_PATH} = "$iosSdkRoot/usr/include";

			$ENV{CC} = "$iosBuildEnvDir/builds/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -arch $iphoneArch";
			$ENV{CXX} = "$iosBuildEnvDir/builds/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -arch $iphoneArch";
			$ENV{LD} = "$iosBuildEnvDir/builds/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld";

			$ENV{CFLAGS} = "-DHAVE_ARMV6=1 -DHOST_IOS -DARM_FPU_VFP=1 -miphoneos-version-min=$iphoneOsMinVersion -mno-thumb -Os -isysroot $iosSdkRoot";
			$ENV{CXXFLAGS} = "$ENV{CFLAGS} -U__powerpc__ -U__i386__ -D__arm__";
			$ENV{CPPFLAGS} = $ENV{CXXFLAGS};

			$ENV{LDFLAGS} = "-arch $iphoneArch -liconv -lobjc -lc++ -Wl,-syslibroot,$iosSdkRoot";

			print "\n";
			print ">>> Environment:\n";
			print ">>> \tCC = $ENV{CC}\n";
			print ">>> \tCXX = $ENV{CXX}\n";
			print ">>> \tLD = $ENV{LD}\n";
			print ">>> \tCFLAGS = $ENV{CFLAGS}\n";
			print ">>> \tCXXFLAGS = $ENV{CXXFLAGS}\n";
			print ">>> \tCPPFLAGS = $ENV{CPPFLAGS}\n";
			print ">>> \tLDFLAGS = $ENV{LDFLAGS}\n";
			print ">>> \tCPLUS_INCLUDE_PATH = $ENV{CPLUS_INCLUDE_PATH}\n";
			print ">>> \tC_INCLUDE_PATH = $ENV{C_INCLUDE_PATH}\n";

			push @configureparams, "--host=arm-apple-darwin$darwinVersion";

			push @configureparams, "--with-sigaltstack=no";
			push @configureparams, "--disable-shared-handles";
			push @configureparams, "--with-tls=pthread";
			push @configureparams, "--disable-boehm";

			push @configureparams, "--enable-llvm-runtime";
			push @configureparams, "--with-bitcode=yes";

			push @configureparams, "--with-lazy-gc-thread-creation=yes";
			push @configureparams, "--without-ikvm-native";
			push @configureparams, "--enable-icall-export";
			push @configureparams, "--disable-icall-tables";
			push @configureparams, "--disable-executables";
			push @configureparams, "--disable-visibility-hidden";
			push @configureparams, "--enable-dtrace=no";
			
			push @configureparams, "--enable-minimal=ssa,com,jit,reflection_emit_save,reflection_emit,portability,assembly_remapping,attach,verifier,full_messages,appdomains,security,sgen_remset,sgen_marksweep_par,sgen_marksweep_fixed,sgen_marksweep_fixed_par,sgen_copying,logging,remoting,shared_perfcounters";
			
			push @configureparams, "mono_cv_uscore=yes";
			push @configureparams, "cv_mono_sizeof_sunpath=104";
			push @configureparams, "ac_cv_func_posix_getpwuid_r=yes";
			push @configureparams, "ac_cv_func_backtrace_symbols=no";
			push @configureparams, "ac_cv_func_finite=no";
			push @configureparams, "ac_cv_header_curses_h=no";

			# TODO by Mike : What to do about this stuff?
			#system("perl", "-pi", "-e", "'s/#define HAVE_STRNDUP 1//'", "eglib/config.h") eq 0 or die ("failed to tweak eglib/config.h\n");
		}
		elsif ($iphoneSimulator)
		{
			my $iosSdkVersion = "9.3";
			my $iosSimMinVersion = "4.3";
			my $iosSdkRoot = "$iosBuildEnvDir/builds/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator$iosSdkVersion.sdk";

			print(">>> iOS Sim Build Environment = $iosBuildEnvDir\n");
			print(">>> iOS Sim SDK Version = $iosSdkVersion\n");
			print(">>> iOS Sim SDK Root = $iosSdkRoot\n");
			print(">>> iOS Sim Arch = $iphoneSimulatorArch\n");

			$ENV{PATH} = "$iosSdkRoot/usr/bin:$ENV{PATH}";

			$ENV{MACSDKOPTIONS} = "-D_XOPEN_SOURCE=1 -g -O0 -DHOST_IOS -DTARGET_IPHONE_SIMULATOR -mios-simulator-version-min=$iosSimMinVersion -isysroot $iosSdkRoot";
			$ENV{CFLAGS} = "-arch $iphoneSimulatorArch $ENV{MACSDKOPTIONS}";
			$ENV{CXXFLAGS} = "$ENV{CFLAGS}";
			$ENV{CPPFLAGS} = "$ENV{CFLAGS}";
			$ENV{CC} = "$iosBuildEnvDir/builds/Xcode.app/Contents/Developer/usr/bin/gcc -arch $iphoneSimulatorArch";
			$ENV{CXX} = "$iosBuildEnvDir/builds/Xcode.app/Contents/Developer/usr/bin/g++ -arch $iphoneSimulatorArch";

			print "\n";
			print ">>> Environment:\n";
			print ">>> \tCC = $ENV{CC}\n";
			print ">>> \tCXX = $ENV{CXX}\n";
			print ">>> \tLD = $ENV{LD}\n";
			print ">>> \tCFLAGS = $ENV{CFLAGS}\n";
			print ">>> \tCXXFLAGS = $ENV{CXXFLAGS}\n";
			print ">>> \tCPPFLAGS = $ENV{CPPFLAGS}\n";
			print ">>> \tMACSDKOPTIONS = $ENV{MACSDKOPTIONS}\n";

			push @configureparams, "--host=$iphoneSimulatorArch-apple-darwin$darwinVersion";

			push @configureparams, "--with-tls=pthread";
			push @configureparams, "--disable-boehm";

			push @configureparams, "--without-ikvm-native";;
			push @configureparams, "--disable-executables";
			push @configureparams, "--disable-visibility-hidden";
			
			push @configureparams, "--enable-minimal=com,remoting,shared_perfcounters";
			
			push @configureparams, "mono_cv_uscore=yes";
			push @configureparams, "ac_cv_func_clock_nanosleep=no";
		}
		else
		{
			die("This should not be hit\n");
		}
	}
	elsif ($iphoneCross)
	{
		if ($runningOnWindows)
		{
			die("Not implemented\n");
		}
		else
		{
			$ENV{CFLAGS} = "-DARM_FPU_VFP=1 -DUSE_MUNMAP -DPLATFORM_IPHONE_XCOMP -DMONOTOUCH -mmacosx-version-min=$macversion";
			$ENV{CXXFLAGS} = "-mmacosx-version-min=$macversion -stdlib=libc++";
			$ENV{CPPFLAGS} = "$ENV{CFLAGS} -mmacosx-version-min=$macversion";

			$ENV{CC} = "$macSdkPath/../usr/bin/clang -arch i386";
			$ENV{CXX} = "$macSdkPath/../usr/bin/clang++ -arch i386";
			$ENV{CPP} = "$ENV{CC} -E";
			$ENV{LD} = $ENV{CC};
			$ENV{LDFLAGS} = "-stdlib=libc++";
			$ENV{MACSDKOPTIONS} = "-mmacosx-version-min=$macversion -isysroot $macSdkPath";

			print "\n";
			print ">>> Environment:\n";
			print ">>> \tCC = $ENV{CC}\n";
			print ">>> \tCXX = $ENV{CXX}\n";
			print ">>> \tLD = $ENV{LD}\n";
			print ">>> \tCFLAGS = $ENV{CFLAGS}\n";
			print ">>> \tCXXFLAGS = $ENV{CXXFLAGS}\n";
			print ">>> \tCPPFLAGS = $ENV{CPPFLAGS}\n";
			print ">>> \tLDFLAGS = $ENV{LDFLAGS}\n";
			print ">>> \tMACSDKOPTIONS = $ENV{MACSDKOPTIONS}\n";

			push @configureparams, "--with-sigaltstack=no";
			push @configureparams, "--disable-shared-handles";
			push @configureparams, "--with-tls=pthread";

			push @configureparams, "--target=arm-darwin";
			push @configureparams, "--with-macversion=$macversion";
			push @configureparams, "--with-cross-offsets=$iphoneCrossAbi.h";

			# New ones trying out
			push @configureparams, "--disable-boehm";
			push @configureparams, "--build=i386-apple-darwin10";
			push @configureparams, "--disable-libraries";
			push @configureparams, "--enable-icall-symbol-map";
			push @configureparams, "--enable-minimal=com,remoting";
			
			#push @configureparams, "--enable-llvm";
			#push @configureparams, "--with-llvm=llvm/usr";

			# TODO by Mike : What to do about this ?
			#perl -pi -e 's/#define HAVE_STRNDUP 1//' eglib/config.h

			my @mcsArgs = ();
			push @mcsArgs, "$monoroot/tools/offsets-tool/MonoAotOffsetsDumper.cs";
			push @mcsArgs, "$monoroot/mcs/class/Mono.Options/Mono.Options/Options.cs";
			push @mcsArgs, "/r:$externalBuildDeps/CppSharpBinaries/CppSharp.AST.dll";
			push @mcsArgs, "/r:$externalBuildDeps/CppSharpBinaries/CppSharp.Generator.dll";
			push @mcsArgs, "/r:$externalBuildDeps/CppSharpBinaries/CppSharp.Parser.CSharp.dll";
			push @mcsArgs, "/r:$externalBuildDeps/CppSharpBinaries/CppSharp.dll";
			push @mcsArgs, "/debug";
			push @mcsArgs, "/nowarn:0436";
			push @mcsArgs, "/out:$monoroot/tools/offsets-tool/MonoAotOffsetsDumper.exe";

			print ">>> Compiling MonoAotOffsetDumper : $iphoneCrossMonoBinToUse/mcs @mcsArgs\n";
			system("$iphoneCrossMonoBinToUse/mcs", @mcsArgs) eq 0 or die("failed to compile MonoAotOffsetsDumper\n");

			# clean up any pre-existing offset header just in case
			if (-f "$monoroot/$iphoneCrossAbi.h")
			{
				system("rm", "-rf", "$iphoneCrossAbi.h");
			}
		}
	}
	elsif ($android)
	{
		my $ndkVersion = "r10e";
		my $isArmArch = 1;
		my $toolchainName = "";
		my $platformRootPostfix = "";
		my $useKraitPatch = 1;
		my $kraitPatchPath = abs_path("$monoroot/../../android_krait_signal_handler/build");
		my $toolChainExtension = "";
		my $useBuildDepsForNDK = 1;

		$isArmArch = 0 if ($androidArch eq "x86");
		
		$ENV{ANDROID_PLATFORM} = "android-9";
		$ENV{GCC_VERSION} = "4.8";

		if ($isArmArch)
		{
			$ENV{GCC_PREFIX} = "arm-linux-androideabi-";
			$toolchainName = "$ENV{GCC_PREFIX}$ENV{GCC_VERSION}";
			$platformRootPostfix = "arm";
		}
		else
		{
			$ENV{GCC_PREFIX} = "i686-linux-android-";
			$toolchainName = "x86-$ENV{GCC_VERSION}";
			$platformRootPostfix = "x86";
			$useKraitPatch = 0;
		}

		if ($^O eq "linux")
		{
			$ENV{HOST_ENV} = "linux";
		}
		elsif ($^O eq 'darwin')
		{
			$ENV{HOST_ENV} = "darwin";
		}
		else
		{
			$ENV{HOST_ENV} = "windows";
		}

		print "\n";
		print(">>> Android Platform = $ENV{ANDROID_PLATFORM}\n");
		print(">>> Android NDK Version = $ndkVersion\n");
		print(">>> Android GCC Prefix = $ENV{GCC_PREFIX}\n");
		print(">>> Android GCC Version = $ENV{GCC_VERSION}\n");

		if ($useBuildDepsForNDK)
		{
			my $ndkName = "";
			if($^O eq "linux")
			{
				$ndkName = "android-ndk-$ndkVersion-linux-x86.bin";
			}
			elsif($^O eq "darwin")
			{
				$ndkName = "android-ndk-$ndkVersion-darwin-x86_64.bin";
			}
			else
			{
				$ndkName = "android-ndk-$ndkVersion-windows-x86.exe";
			}

			my $depsNdkArchive = "$externalBuildDeps/$ndkName";
			my $depsNdkFinal = "$externalBuildDeps/android-ndk-$ndkVersion";

			print(">>> Android NDK Archive = $depsNdkArchive\n");
			print(">>> Android NDK Extraction Destination = $depsNdkFinal\n");
			print("\n");

			$ENV{ANDROID_NDK_ROOT} = "$depsNdkFinal";

			if (-d $depsNdkFinal)
			{
				print(">>> Android NDK already extracted\n");
			}
			else
			{
				print(">>> Android NDK needs to be extracted\n");

				if ($runningOnWindows)
				{
					my $sevenZip = "$externalBuildDeps/7z/win64/7za.exe";
					my $winDepsNdkArchive = `cygpath -w $depsNdkArchive`;
					my $winDepsNdkExtract = `cygpath -w $externalBuildDeps`;

					# clean up trailing new lines that end up in the output from cygpath.  If left, they cause problems down the line
					# for 7zip
					$winDepsNdkArchive =~ s/\n+$//;
					$winDepsNdkExtract =~ s/\n+$//;

					system($sevenZip, "x", "$winDepsNdkArchive", "-o$winDepsNdkExtract");
				}
				else
				{
					my ($name,$path,$suffix) = fileparse($depsNdkArchive, qr/\.[^.]*/);

					print(">>> Android NDK Extension = $suffix\n");

					# Versions after r11 use .zip extension.  Currently we use r10e, but let's support the .zip extension in case
					# we upgrade down the road
					if (lc $suffix eq '.zip')
					{
						system("unzip", "-q", $depsNdkArchive, "-d", $externalBuildDeps);
					}
					elsif (lc $suffix eq '.bin')
					{	chmod(0755, $depsNdkArchive);
						system($depsNdkArchive, "-o$externalBuildDeps");
					}
					else
					{
						die "Unknown file extension '" . $suffix . "'\n";
					}
				}
			}

			if (!(-f "$ENV{ANDROID_NDK_ROOT}/ndk-build"))
			{
				die("Something went wrong with the NDK extraction\n");
			}
		}
		else
		{
			PrepareAndroidSDK::GetAndroidSDK("", "", $ndkVersion, "envsetup.sh", $externalBuildDeps, $monoroot);
		}

		my $androidNdkRoot = $ENV{ANDROID_NDK_ROOT};
		my $androidPlatformRoot = "$androidNdkRoot/platforms/$ENV{ANDROID_PLATFORM}/arch-$platformRootPostfix";
		my $androidToolchain = "$androidNdkRoot/toolchains/$toolchainName/prebuilt/$ENV{HOST_ENV}";

		if (!(-d "$androidToolchain"))
		{
			if (-d "$androidToolchain-x86")
			{
				$androidToolchain = "$androidToolchain-x86";
			}
			else
			{
				$androidToolchain = "$androidToolchain-x86_64";
			}
		}

		if ($runningOnWindows)
		{
			$toolChainExtension = ".exe";

			$androidPlatformRoot = `cygpath -w $androidPlatformRoot`;
			# clean up trailing new lines that end up in the output from cygpath.
			$androidPlatformRoot =~ s/\n+$//;
			# Switch over to forward slashes.  They propagate down the toolchain correctly
			$androidPlatformRoot =~ s/\\/\//g;

			# this will get passed as a path to the linker, so we need to windows-ify the path
			$kraitPatchPath = `cygpath -w $kraitPatchPath`;
			$kraitPatchPath =~ s/\n+$//;
			$kraitPatchPath =~ s/\\/\//g;
		}

		print(">>> Android Arch = $androidArch\n");
		print(">>> Android NDK Root = $androidNdkRoot\n");
		print(">>> Android Platform Root = $androidPlatformRoot\n");
		print(">>> Android Toolchain = $androidToolchain\n");

		if (!(-d "$androidToolchain"))
		{
			die("Failed to locate android toolchain\n");
		}

		if (!(-d "$androidPlatformRoot"))
		{
			die("Failed to locate android platform root\n");
		}

		if ("$androidArch" eq 'armv5')
		{
			$ENV{CFLAGS} = "-DARM_FPU_NONE=1 -march=armv5te -mtune=xscale -msoft-float";
		}
		elsif ("$androidArch" eq 'armv6_vfp')
		{
			$ENV{CFLAGS} = "-DARM_FPU_VFP=1  -march=armv6 -mtune=xscale -msoft-float -mfloat-abi=softfp -mfpu=vfp -DHAVE_ARMV6=1";
		}
		elsif ("$androidArch" eq 'armv7a')
		{
			$ENV{CFLAGS} = "-DARM_FPU_VFP=1  -march=armv7-a -mfloat-abi=softfp -mfpu=vfp -DHAVE_ARMV6=1";
			$ENV{LDFLAGS} = "-Wl,--fix-cortex-a8";
		}
		elsif ("$androidArch" eq 'x86')
		{
			$ENV{LDFLAGS} = "-lgcc"
		}
		else
		{
			die("Unsupported android arch : $androidArch\n");
		}

		if ($isArmArch)
		{
			$ENV{CFLAGS} = "-funwind-tables $ENV{CFLAGS}";
			$ENV{LDFLAGS} = "-Wl,-rpath-link=$androidPlatformRoot/usr/lib $ENV{LDFLAGS}";
		}

		$ENV{PATH} = "$androidToolchain/bin:$ENV{PATH}";
		$ENV{CC} = "$androidToolchain/bin/$ENV{GCC_PREFIX}gcc$toolChainExtension --sysroot=$androidPlatformRoot";
		$ENV{CXX} = "$androidToolchain/bin/$ENV{GCC_PREFIX}g++$toolChainExtension --sysroot=$androidPlatformRoot";
		$ENV{CPP} = "$androidToolchain/bin/$ENV{GCC_PREFIX}cpp$toolChainExtension";
		$ENV{CXXCPP} = "$androidToolchain/bin/$ENV{GCC_PREFIX}cpp$toolChainExtension";
		$ENV{CPATH} = "$androidPlatformRoot/usr/include";
		$ENV{LD} = "$androidToolchain/bin/$ENV{GCC_PREFIX}ld$toolChainExtension";
		$ENV{AS} = "$androidToolchain/bin/$ENV{GCC_PREFIX}as$toolChainExtension";
		$ENV{AR} = "$androidToolchain/bin/$ENV{GCC_PREFIX}ar$toolChainExtension";
		$ENV{RANLIB} = "$androidToolchain/bin/$ENV{GCC_PREFIX}ranlib$toolChainExtension";
		$ENV{STRIP} = "$androidToolchain/bin/$ENV{GCC_PREFIX}strip$toolChainExtension";

		$ENV{CFLAGS} = "-DANDROID -DPLATFORM_ANDROID -DLINUX -D__linux__ -DHAVE_USR_INCLUDE_MALLOC_H -DPAGE_SIZE=0x1000 -D_POSIX_PATH_MAX=256 -DS_IWRITE=S_IWUSR -DHAVE_PTHREAD_MUTEX_TIMEDLOCK -fpic -g -ffunction-sections -fdata-sections $ENV{CFLAGS}";
		$ENV{CXXFLAGS} = $ENV{CFLAGS};
		$ENV{CPPFLAGS} = $ENV{CFLAGS};

		if ($useKraitPatch)
		{
			$ENV{LDFLAGS} = "-Wl,--wrap,sigaction -L$kraitPatchPath/obj/local/armeabi -lkrait-signal-handler $ENV{LDFLAGS}";
		}

		$ENV{LDFLAGS} = "-Wl,--no-undefined -Wl,--gc-sections -ldl -lm -llog -lc $ENV{LDFLAGS}";

		print "\n";
		print ">>> Environment:\n";
		print ">>> \tCC = $ENV{CC}\n";
		print ">>> \tCXX = $ENV{CXX}\n";
		print ">>> \tCPP = $ENV{CPP}\n";
		print ">>> \tCXXCPP = $ENV{CXXCPP}\n";
		print ">>> \tCPATH = $ENV{CPATH}\n";
		print ">>> \tLD = $ENV{LD}\n";
		print ">>> \tAS = $ENV{AS}\n";
		print ">>> \tAR = $ENV{AR}\n";
		print ">>> \tRANLIB = $ENV{RANLIB}\n";
		print ">>> \tSTRIP = $ENV{STRIP}\n";
		print ">>> \tCFLAGS = $ENV{CFLAGS}\n";
		print ">>> \tCXXFLAGS = $ENV{CXXFLAGS}\n";
		print ">>> \tCPPFLAGS = $ENV{CPPFLAGS}\n";
		print ">>> \tLDFLAGS = $ENV{LDFLAGS}\n";

		if ($useKraitPatch)
		{
			my $kraitPatchRepo = "git://github.com/Unity-Technologies/krait-signal-handler.git";
			if (-d "$kraitPatchPath")
			{
				print ">>> Krait patch repository already cloned"
			}
			else
			{
				system("git", "clone", "--branch", "master", "$kraitPatchRepo", "$kraitPatchPath") eq 0 or die ('failing cloning Krait patch');
			}

			chdir("$kraitPatchPath") eq 1 or die ("failed to chdir to krait patch directory\n");
			system("perl", "build.pl") eq 0 or die ('failing to build Krait patch');
			chdir("$monoroot") eq 1 or die ("failed to chdir to $monoroot\n");
		}

		if ($isArmArch)
		{
			push @configureparams, "--host=armv5-linux-androideabi";
		}
		elsif ("$androidArch" eq 'x86')
		{
			push @configureparams, "--host=i686-linux-android";
		}
		else
		{
			die("Unsupported android arch : $androidArch\n");
		}

		push @configureparams, "--disable-parallel-mark";
		push @configureparams, "--disable-shared-handles";
		push @configureparams, "--with-sigaltstack=no";
		push @configureparams, "--with-tls=pthread";
		push @configureparams, "--disable-boehm";
		push @configureparams, "--disable-visibility-hidden";
		push @configureparams, "mono_cv_uscore=yes";
		push @configureparams, "ac_cv_header_zlib_h=no" if($runningOnWindows);
	}
	elsif($^O eq "linux")
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

		$ENV{'CC'} = "$macSdkPath/../usr/bin/clang";
		$ENV{'CXX'} = "$macSdkPath/../usr/bin/clang++";
		$ENV{'CFLAGS'} = $ENV{MACSDKOPTIONS} = "-D_XOPEN_SOURCE -I$macBuildEnvDir/builds/usr/include -mmacosx-version-min=$macversion -isysroot $macSdkPath";
		
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
			print("\n");
			print("\n>>> Configure parameters are : @configureparams\n");
			print("\n");

			system('./autogen.sh', @configureparams) eq 0 or die ('failing autogenning mono');

			print("\n>>> Calling make clean in mono\n");
			system("make","clean") eq 0 or die ("failed to make clean\n");
		}

		# this step needs to run after configure
		if ($iphoneCross)
		{
			# This step generates the arm_dpimacros.h file, which is needed by the offset dumper
			chdir("$monoroot/mono/arch/arm");
			system("make") eq 0 or die("failed to make in $monoroot/mono/arch/arm\n");
			chdir("$monoroot");

			my @monoArgs = ();
			push @monoArgs, "$monoroot/tools/offsets-tool/MonoAotOffsetsDumper.exe";
			push @monoArgs, "--abi";
			push @monoArgs, "$iphoneCrossAbi";
			push @monoArgs, "--out";
			push @monoArgs, "$monoroot";
			push @monoArgs, "--mono";
			push @monoArgs, "$monoroot";
			push @monoArgs, "--maccore";
			push @monoArgs, "$monoroot";

			$ENV{MONO_PATH} = "$externalBuildDeps/CppSharpBinaries";
			# Need to use 32bit mono because there is a native CppSharp dylib that will be used and there's only a 32bit version of it
			print ">>> Running MonoAotOffsetDumper : arch -i386 $iphoneCrossMonoBinToUse/mono @monoArgs\n";
			system("arch", "-i386", "$iphoneCrossMonoBinToUse/mono", @monoArgs) eq 0 or die("failed to run MonoAotOffsetsDumper\n");
		}

		print("\n>>> Calling make\n");
		system("make $mcs -j$jobs") eq 0 or die ('Failed to make\n');
		
		if ($isDesktopBuild)
		{
			print("\n>>> Calling make install\n");
			system("make install") eq 0 or die ("Failed to make install\n");
		}
		else
		{
			if ($disableMcs)
			{
				print(">>> Skipping make install.  We don't need to run this step when building the runtime on non-desktop platforms.\n");
			}
			else
			{
				# Note by Mike : make install on Windows for android runtime runs into more cygwin path issues.  The one I hit was related to ranlib.exe being passed cygwin linux paths
				# and as a result not being able to find stuff.  The previous build scripts didn't run make install for android or iOS, so I think we are fine to skip this step.
				# However, if we were to build the class libs for these cases, then we probably would need to run make install.  If that day comes, we'll have to figure out what to do here.
				print(">>> Attempting to build class libs for a non-desktop platform.  The `make install` step is probably needed, but it has cygwin path related problems on Windows for android\n");
				die("Blocking this code path until we need it.  It probably should be looked at more closely before letting it proceed\n");
			}
		}
	}
	
	if ($isDesktopBuild)
	{
		if ($^O eq "cygwin")
		{
			system("$winPerl", "$winMonoRoot/external/buildscripts/build_runtime_vs.pl", "--build=$build", "--arch32=$arch32", "--msbuildversion=$msBuildVersion", "--clean=$clean", "--debug=$debug") eq 0 or die ('failing building mono with VS\n');
			
			# Copy over the VS built stuff that we want to use instead into the prefix directory
			my $archNameForBuild = $arch32 ? 'Win32' : 'x64';
			my $config = $debug ? "Debug" : "Release";
			system("cp $monoroot/msvc/$archNameForBuild/bin/$config/mono.exe $monoprefix/bin/.") eq 0 or die ("failed copying mono.exe\n");
			system("cp $monoroot/msvc/$archNameForBuild/bin/$config/mono-2.0.dll $monoprefix/bin/.") eq 0 or die ("failed copying mono-2.0.dll\n");
			system("cp $monoroot/msvc/$archNameForBuild/bin/$config/mono-2.0.pdb $monoprefix/bin/.") eq 0 or die ("failed copying mono-2.0.pdb\n");
		}
		
		system("cp -R $addtoresultsdistdir/bin/. $monoprefix/bin/") eq 0 or die ("Failed copying $addtoresultsdistdir/bin to $monoprefix/bin\n");
	}
}
else
{
	print(">>> Skipping build\n");
}

if ($buildUsAndBoo)
{
	print(">>> Building Unity Script and Boo...\n");
	system("perl", "$buildscriptsdir/build_us_and_boo.pl", "--monoprefix=$monoprefix") eq 0 or die ("Failed builidng Unity Script and Boo\n");
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
		
		if($^O ne 'darwin')
		{
			# On OSX we build a universal binary for 32-bit and 64-bit in the mono executable. The class library build
			# only creates the 64-bit slice, so we don't want to end up with a single slice binary in the output.
			# If we do, it will step on the universal binary produced but the OSX runtime build.
			system("cp -r $monoprefix/bin $distdir/") eq 0 or die ("failed copying bin folder\n");
		}
		system("cp -r $monoprefix/etc $distdir/") eq 0 or die("failed copying etc folder\n");

		system("cp -R $externalBuildDeps/reference-assemblies/unity $distdirlibmono/unity");
 		system("cp -R $externalBuildDeps/reference-assemblies/unity_web $distdirlibmono/unity_web");

 		system("cp -R $externalBuildDeps/reference-assemblies/unity/Boo*.dll $distdirlibmono/2.0-api");
 		system("cp -R $externalBuildDeps/reference-assemblies/unity/UnityScript*.dll $distdirlibmono/2.0-api");

 		system("cp -R $externalBuildDeps/reference-assemblies/unity/Boo*.dll $distdirlibmono/4.0-api");
 		system("cp -R $externalBuildDeps/reference-assemblies/unity/UnityScript*.dll $distdirlibmono/4.0-api");

		system("cp -R $externalBuildDeps/reference-assemblies/unity/Boo*.dll $distdirlibmono/4.5-api");
		system("cp -R $externalBuildDeps/reference-assemblies/unity/UnityScript*.dll $distdirlibmono/4.5-api");

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
	my $crossCompilerRoot = "$buildsroot/crosscompiler";
	my $crossCompilerDestination = "";
	if ($iphone)
	{
		$embedDirArchDestination = "$embedDirRoot/iphone/$iphoneArch";
		$versionsOutputFile = "$buildsroot/versions-iphone-$iphoneArch.txt";
	}
	elsif ($iphoneCross)
	{
		$crossCompilerDestination = "$buildsroot/crosscompiler/iphone";
		$versionsOutputFile = "$buildsroot/versions-iphone-xcompiler.txt";
	}
	elsif ($iphoneSimulator)
	{
		$embedDirArchDestination = "$embedDirRoot/iphone/$iphoneSimulatorArch";
		$versionsOutputFile = "$buildsroot/versions-iphone-$iphoneSimulatorArch.txt";
	}
	elsif ($android)
	{
		$embedDirArchDestination = "$embedDirRoot/android/$androidArch";
		$versionsOutputFile = "$buildsroot/versions-android-$androidArch.txt";
	}
	elsif($^O eq "linux")
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

	system("mkdir -p $embedDirArchDestination") if ($embedDirArchDestination ne "");
	system("mkdir -p $distDirArchBin") if ($distDirArchBin ne "");
	system("mkdir -p $crossCompilerDestination") if ($crossCompilerDestination ne "");

	# embedruntimes directory setup
	print(">>> Creating embedruntimes directory : $embedDirArchDestination\n");
	if ($iphone)
	{
		print ">>> Copying libmonosgen-2.0\n";
		system("cp", "$monoroot/mono/mini/.libs/libmonosgen-2.0.a","$embedDirArchDestination/libmonosgen-2.0.a") eq 0 or die ("failed copying libmonosgen-2.0.a\n");
	}
	elsif ($iphoneCross)
	{
		# Nothing to do
	}
	elsif ($iphoneSimulator)
	{
		print ">>> Copying libmonosgen-2.0\n";
		system("cp", "$monoroot/mono/mini/.libs/libmonosgen-2.0.a","$embedDirArchDestination/libmonosgen-2.0.a") eq 0 or die ("failed copying libmonosgen-2.0.a\n");
	}
	elsif ($android)
	{
		print ">>> Copying libmonosgen-2.0\n";
		system("cp", "$monoroot/mono/mini/.libs/libmonosgen-2.0.so","$embedDirArchDestination/libmonosgen-2.0.so") eq 0 or die ("failed copying libmonosgen-2.0.so\n");
		system("cp", "$monoroot/mono/mini/.libs/libmonosgen-2.0.a","$embedDirArchDestination/libmonosgen-2.0.a") eq 0 or die ("failed copying libmonosgen-2.0.a\n");
	}
	elsif($^O eq "linux")
	{
		print ">>> Copying libmonosgen-2.0\n";
		system("cp", "$monoroot/mono/mini/.libs/libmonoboehm-2.0.so","$embedDirArchDestination/libmonoboehm-2.0.so") eq 0 or die ("failed copying libmonoboehm-2.0.so\n");
		system("cp", "$monoroot/mono/mini/.libs/libmonosgen-2.0.so","$embedDirArchDestination/libmonosgen-2.0.so") eq 0 or die ("failed copying libmonosgen-2.0.so\n");

		print ">>> Copying libMonoPosixHelper.so\n";
		system("cp", "$monoroot/support/.libs/libMonoPosixHelper.so","$embedDirArchDestination/libMonoPosixHelper.so") eq 0 or die ("failed copying libMonoPosixHelper.so\n");
		
		if ($buildMachine)
		{
			system("strip $embedDirArchDestination/libmonoboehm-2.0.so") eq 0 or die("failed to strip libmonoboehm-2.0.so (shared)\n");
			system("strip $embedDirArchDestination/libmonosgen-2.0.so") eq 0 or die("failed to strip libmonosgen-2.0.so (shared)\n");
			system("strip $embedDirArchDestination/libMonoPosixHelper.so") eq 0 or die("failed to strip libMonoPosixHelper (shared)\n");
		}
	}
	elsif($^O eq 'darwin')
	{
		# embedruntimes directory setup
 		print ">>> Hardlinking libmonosgen-2.0\n";

		system("ln","-f", "$monoroot/mono/mini/.libs/libmonoboehm-2.0.dylib","$embedDirArchDestination/libmonoboehm-2.0.dylib") eq 0 or die ("failed symlinking libmonoboehm-2.0.dylib\n");
		system("ln","-f", "$monoroot/mono/mini/.libs/libmonosgen-2.0.dylib","$embedDirArchDestination/libmonosgen-2.0.dylib") eq 0 or die ("failed symlinking libmonosgen-2.0.dylib\n");
		 
		print "Hardlinking libMonoPosixHelper.dylib\n";
		system("ln","-f", "$monoroot/support/.libs/libMonoPosixHelper.dylib","$embedDirArchDestination/libMonoPosixHelper.dylib") eq 0 or die ("failed symlinking $libtarget/libMonoPosixHelper.dylib\n");
	
		InstallNameTool("$embedDirArchDestination/libmonoboehm-2.0.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/osx/libmonoboehm-2.0.dylib");
		InstallNameTool("$embedDirArchDestination/libmonosgen-2.0.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/osx/libmonosgen-2.0.dylib");
		InstallNameTool("$embedDirArchDestination/libMonoPosixHelper.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/osx/libMonoPosixHelper.dylib");
	}
	else
	{
		# embedruntimes directory setup
		system("cp", "$monoprefix/bin/mono-2.0.dll", "$embedDirArchDestination/mono-2.0.dll") eq 0 or die ("failed copying mono-2.0.dll\n");
		system("cp", "$monoprefix/bin/mono-2.0.pdb", "$embedDirArchDestination/mono-2.0.pdb") eq 0 or die ("failed copying mono-2.0.pdb\n");
	}
	
	# monodistribution directory setup
	print(">>> Creating monodistribution directory\n");
	if ($android || $iphone || $iphoneCross || $iphoneSimulator)
	{
		# Nothing to do
	}
	elsif($^O eq "linux")
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
		system("ln", "-f", "$monoroot/tools/pedump/pedump","$distDirArchBin/pedump") eq 0 or die("failed symlinking pedump executable\n");
		system('cp', "$monoroot/data/config","$distDirArchEtc/mono/config") eq 0 or die("failed to copy config\n");
	}
	elsif($^O eq 'darwin')
	{
		system("ln", "-f", "$monoroot/mono/mini/mono","$distDirArchBin/mono") eq 0 or die("failed hardlinking mono executable\n");
		system("ln", "-f", "$monoroot/tools/pedump/pedump","$distDirArchBin/pedump") eq 0 or die("failed hardlinking pedump executable\n");
	}
	else
	{
		system("cp", "$monoprefix/bin/mono-2.0.dll", "$distDirArchBin/mono-2.0.dll") eq 0 or die ("failed copying mono-2.0.dll\n");
		system("cp", "$monoprefix/bin/mono-2.0.pdb", "$distDirArchBin/mono-2.0.pdb") eq 0 or die ("failed copying mono-2.0.pdb\n");
		system("cp", "$monoprefix/bin/mono.exe", "$distDirArchBin/mono.exe") eq 0 or die ("failed copying mono.exe\n");
	}

	# cross compiler directory setup
	if ($iphoneCross)
	{
		print ">>> Copying mono-xcompiler\n";
		system("cp", "$monoroot/mono/mini/mono","$crossCompilerDestination/mono-xcompiler") eq 0 or die ("failed copying mono-xcompiler\n");
	}
	
	# Not all build configurations output to the distro dir, so only chmod it if it exists
	system("chmod", "-R", "755", $distDirArchBin) if (-d "$distDirArchBin");
	
	# Output version information
	print(">>> Creating version file : $versionsOutputFile\n");
	system("echo \"mono-version =\" > $versionsOutputFile");

	# Not all build configurations output to the distro dir, only try to output version info if there is a distro dir
	system("$distDirArchBin/mono --version >> $versionsOutputFile") if (-d "$distDirArchBin");

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