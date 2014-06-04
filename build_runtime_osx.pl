use strict;

use lib ('external/buildscripts', "../../Tools/perl_lib","perl_lib", 'external/buildscripts/perl_lib');
use Cwd;
use Cwd 'abs_path';
use File::Path;
use Getopt::Long;
use Tools qw(InstallNameTool);
use File::Copy::Recursive qw(dircopy);

require "build_classlibs.pm";

my $root = getcwd();
my $monopath = $root;

my $buildsroot = "$root/builds";
my $buildir = $root;
my $embeddir = "$buildsroot/embedruntimes";
my $distdir = "$buildsroot/monodistribution";
my $skipbuild=0;
my $debug = 0;
my $minimal = 0;
my $cleanpath = 0;
my $cleanbuild = 1;
my $reconfigure = 1;
my $dobuild = 'osx';
my $jobs = 4;
my $xcodePath = '/Applications/Xcode.app';
my $cleanbuildopt = 'full';
my $unityPath = "$root/../unity";

GetOptions(
   "skipbuild=i"=>\$skipbuild,
   "debug=i"=>\$debug,
   "minimal=i"=>\$minimal,
   "cleanpath=i"=>\$cleanpath,
   "cleanbuild=s"=>\$cleanbuildopt,
   "build=s"=>\$dobuild,
   "j=i"=>\$jobs,
   "xcodepath=s"=>\$xcodePath,
   "reconfigure=i"=>\$reconfigure
) or die<<EOF
illegal cmdline options.

Usage:
   -skipbuild[=1] - skips the build step (default: 0/false)
   -debug[=1] - do a debug build (default: 0/false)
   -minimal[=1] - do a minimal build (default: 0/false)
   -cleanpath[=1] - cleans the PATH env var so other things don't conflict with the build (default: 0/false)
   -cleanbuild=[no/partial/full] - partial runs configure but not make clean, full cleans everything
   -build=... - build type: osx, runtime, cross, simulator, iphone, classlibs
   -j=# - number of jobs to pass to make -j
   -xcodepath=... - path to xcode (default: /Applications/Xcode.app)
   -reconfigure[=1] - reconfigures the source (default: 1/true)
EOF
;

$cleanbuild = 0 if ($cleanbuildopt ne 'full');
$reconfigure = 0 if ($cleanbuildopt eq 'no');

$monopath = abs_path($monopath) if (-d $monopath);
die ("Cannot find mono checkout in $monopath") unless (-d $monopath);

$xcodePath = "$xcodePath/Contents/Developer/Platforms";

my $teamcity=0;
if ($ENV{UNITY_THISISABUILDMACHINE})
{
	print "rmtree-ing $buildsroot because we're on a buildserver, and want to make sure we don't include old artifacts\n";
	rmtree("$buildsroot");
	$teamcity=1;
	$jobs = "";
} else {
	print "not rmtree-ing $buildsroot, as we're not on a buildmachine\n";
	if (($debug==0) && ($skipbuild==0))
	{
		print "\n\nARE YOU SURE YOU DONT WANT TO MAKE A DEBUG BUILD?!?!?!!!!!\n\n\n";
	}

	$ENV{"PATH"} = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/X11/bin" if $cleanpath;
	$jobs = "-j$jobs";
}


# From Massi: I was getting failures in install_name_tool about space
# for the commands being too small, and adding here things like
# $ENV{LDFLAGS} = '-headerpad_max_install_names' and
# $ENV{LDFLAGS} = '-headerpad=0x40000' did not help at all (and also
# adding them to our final gcc invocation to make the bundle).
# Lucas noticed that I was lacking a Mono prefix, and having a long
# one would give us space, so here is this silly looong prefix.
my $prefix = "$buildsroot/tmp/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting/scripting";


my $savedpath = $ENV{PATH};
my $savedcinclude = $ENV{C_INCLUDE_PATH};
my $savedcppinclude = $ENV{CPLUS_INCLUDE_PATH};
my $savedcflags = $ENV{CFLAGS};
my $savedcxxflags = $ENV{CXXFLAGS};
my $savedcc = $ENV{CC};
my $savedcxx = $ENV{CXX};
my $savedcpp = $ENV{CPP};
my $savedcxxpp = $ENV{CXXPP};
my $savedld = $ENV{LD};
my $savedldflags = $ENV{LDFLAGS};
my $savedfallbacklibpath = $ENV{'DYLD_FALLBACK_LIBRARY_PATH'};
my $savedlibpath = $ENV{'LD_LIBRARY_PATH'};
my $savedacinclude = $ENV{'ACLOCAL_PATH'};
my $savedpkgconfig = $ENV{'PKG_CONFIG_PATH'};



sub setenv
{
	my $envpath = shift;
	my $envcinclude = shift;
	my $envcppinclude = shift;
	my $envcflags = shift;
	my $envcxxflags = shift;
	my $envcc = shift;
	my $envcxx = shift;
	my $envcpp = shift;
	my $envcxxpp = shift;
	my $envld = shift;
	my $envldflags = shift;

	$ENV{PATH} = $savedpath;
	$ENV{C_INCLUDE_PATH} = $savedcinclude;
	$ENV{CPLUS_INCLUDE_PATH} = $savedcppinclude;
	$ENV{CFLAGS} = $savedcflags;
	$ENV{CXXFLAGS} = $savedcxxflags;
	$ENV{CC} = $savedcc;
	$ENV{CXX} = $savedcxx;
	$ENV{CPP} = $savedcpp;
	$ENV{CXXPP} = $savedcxxpp;
	$ENV{LD} = $savedld;
	$ENV{LDFLAGS} = $savedldflags;
	$ENV{DYLD_FALLBACK_LIBRARY_PATH} = $savedfallbacklibpath;
	$ENV{LD_LIBRARY_PATH} = $savedlibpath;
	$ENV{ACLOCAL_PATH} = $savedacinclude;
	$ENV{PKG_CONFIG_PATH} = $savedpkgconfig;
	$ENV{MACSDKOPTIONS} = '';
	$ENV{MACSYSROOT} = '';
	$ENV{PLATFORM_IPHONE_XCOMP} = '';

	$ENV{mono_cv_uscore} = '';
	$ENV{mono_cv_clang} = '';
	$ENV{cv_mono_sizeof_sunpath} = '';
	$ENV{ac_cv_func_posix_getpwuid_r} = '';
	$ENV{ac_cv_func_backtrace_symbols} = '';


	$ENV{PATH} = "$envpath:".$ENV{PATH} if $envpath;
	$ENV{C_INCLUDE_PATH} = $envcinclude if $envcinclude;
	$ENV{CPLUS_INCLUDE_PATH} = $envcppinclude if $envcppinclude;
	$ENV{CFLAGS} = $envcflags if $envcflags;
	$ENV{CXXFLAGS} = $envcxxflags if $envcxxflags;
	$ENV{CC} = $envcc if $envcc;
	$ENV{CXX} = $envcxx if $envcxx;
	$ENV{CPP} = $envcpp if $envcpp;
	$ENV{CXXPP} = $envcxxpp if $envcxxpp;
	$ENV{LD} = $envld if $envld;
	$ENV{LDFLAGS} = $envldflags if $envldflags;

	print "\n";
	print "Setting environment:\n";
	print "PATH = ".$ENV{PATH}."\n";
	print "C_INCLUDE_PATH = ".$ENV{C_INCLUDE_PATH}."\n";
	print "CPLUS_INCLUDE_PATH = ".$ENV{CPLUS_INCLUDE_PATH}."\n";
	print "CFLAGS = ".$ENV{CFLAGS}."\n";
	print "CXXFLAGS = ".$ENV{CXXFLAGS}."\n";
	print "CC = ".$ENV{CC}."\n";
	print "CXX = ".$ENV{CXX}."\n";
	print "CPP = ".$ENV{CPP}."\n";
	print "CXXPP = ".$ENV{CXXPP}."\n";
	print "LD = ".$ENV{LD}."\n";
	print "LDFLAGS = ".$ENV{LDFLAGS}."\n";
	print "\n";

}

sub detect_sdk
{
	my $type = shift;
	my $sdkversion = shift;
	return ("/Developer", "/Developer/SDKs/$type") if (-d "/Developer/SDKs" and $sdkversion eq '10.6');
	return ("$xcodePath/$type.platform/Developer", "$xcodePath/$type.platform/Developer/SDKs/$type");
}

sub detect_iphonesim_sdk
{
	my $sdkversion = shift;
	my $detectedsdk = $sdkversion;
	my ($sdkroot, $sdkpath) = detect_sdk ("iPhoneSimulator", $sdkversion);

	$detectedsdk = "5.1" unless (-d "$sdkpath$detectedsdk.sdk");
	$detectedsdk = "6.0" unless (-d "$sdkpath$detectedsdk.sdk");
	$detectedsdk = "NaN" unless (-d "$sdkpath$detectedsdk.sdk");

	die ("Requested iPhone Simulator SDK version was $sdkversion but no SDK could be found in $sdkroot/SDKs") if ($detectedsdk eq 'NaN');
	warn ("Requested iPhone Simulator SDK version was $sdkversion but detected SDK is $detectedsdk. Things might not work as intended.") if ($sdkversion != $detectedsdk);

	$sdkversion = $detectedsdk;

	print ("Detected iPhoneSimulator SDK at $sdkpath$sdkversion.sdk\n");

	return ($sdkversion, $sdkroot, "$sdkpath$sdkversion.sdk");
}

sub detect_osx_sdk
{
	my $sdkversion = shift;
	my $detectedsdk = $sdkversion;
	my ($sdkroot, $sdkpath) = detect_sdk ("MacOSX", $sdkversion);
	if($teamcity)
	{
		return ($sdkversion, "$unityPath/External/MacBuildEnvironment/builds", "$unityPath/External/MacBuildEnvironment/builds/MacOSX10.6.sdk");
	}

	$detectedsdk = "10.7" unless (-d "$sdkpath$detectedsdk.sdk");
	$detectedsdk = "10.8" unless (-d "$sdkpath$detectedsdk.sdk");
	$detectedsdk = "NaN" unless (-d "$sdkpath$detectedsdk.sdk");

	die ("Requested MacOSX SDK version was $sdkversion but no SDK could be found in $sdkroot/SDKs/") if ($detectedsdk eq 'NaN');
	warn ("Requested MacOSX SDK version was $sdkversion but detected SDK is $detectedsdk. Things might not work as intended.") if ($sdkversion != $detectedsdk);

	$sdkversion = $detectedsdk;

	print ("Detected MacOSX SDK at $sdkpath$sdkversion.sdk\n");

	return ($sdkversion, $sdkroot, "$sdkpath$sdkversion.sdk");
}

sub setenv_osx
{
	my $arch = shift;
	my $cachefile = shift;
	my $macversion = shift;
	my $sdkversion = shift;
	my $sdkroot = shift;
	my $sdkpath = shift;

	my $path;

	my $cinclude;
	my $cppinclude;

	my $cflags = "-D_XOPEN_SOURCE=1 -arch $arch -DMONO_DISABLE_SHM=1 -DDISABLE_SHARED_HANDLES=1";
	if($teamcity)
	{
		$cflags = "$cflags -I$unityPath/External/MacBuildEnvironment/builds/usr/include";
	}
	$cflags = "$cflags -g -O0" if $debug;
	$cflags = "$cflags -Os" if not $debug; #optimize for size

	my $cxxflags = "$cflags";

	my $cc = "$unityPath/External/MacBuildEnvironment/builds/usr/bin/clang";
	my $cxx = "$unityPath/External/MacBuildEnvironment/builds/usr/bin/clang++";
	$cc = "$cc -arch $arch";
	$cxx = "$cxx -arch $arch";

	my $cpp;
	my $cxxpp;
	my $ld;
	my $ldflags;

	my @configureparams = ();
	unshift(@configureparams, "--cache-file=$cachefile");
	unshift(@configureparams, "--disable-mcs-build");
	unshift(@configureparams, "--with-glib=embedded");
	unshift(@configureparams, "--disable-nls");  #this removes the dependency on gettext package
	unshift(@configureparams, "--prefix=$prefix");
	unshift(@configureparams, "--enable-minimal=aot,logging,com,profiler,debug") if $minimal;

	setenv ($path, $cinclude, $cppinclude, $cflags, $cxxflags, $cc, $cxx, $cpp, $cxxpp, $ld, $ldflags);

	$ENV{mono_cv_uscore} = "";
	$ENV{mono_cv_clang} = "";
	$ENV{cv_mono_sizeof_sunpath} = "";
	$ENV{ac_cv_func_posix_getpwuid_r} = "";
	$ENV{ac_cv_func_backtrace_symbols} = "";

	$ENV{MACSDKOPTIONS} = "-mmacosx-version-min=$macversion -isysroot $sdkpath";

	return (@configureparams);
}

sub setenv_iphone_simulator
{
	my $arch = shift;
	my $cachefile = shift;
	my $sdkversion = shift;
	my $sdkroot = shift;
	my $sdkpath = shift;

	$debug = 1;

	my $path;
	my $macsysroot = "-isysroot $sdkpath";
	my $macsdkoptions = "-miphoneos-version-min=3.0 $macsysroot";

	my $cinclude;
	my $cppinclude;

	my $cflags = "-D_XOPEN_SOURCE=1 -DTARGET_IPHONE_SIMULATOR";
	$cflags = "$cflags -g -O0" if $debug;
	$cflags = "$cflags -Os" if not $debug; #optimize for size

	my $cxxflags = "$cflags";

	my $cc = "$sdkroot/usr/bin/gcc -arch $arch";
	my $cxx = "$sdkroot/usr/bin/g++ -arch $arch";

	my $cpp = "$cc -E";
	my $cxxpp;
	my $ld;
	my $ldflags;


	my @configureparams = ();
	unshift(@configureparams, "--cache-file=$cachefile");
	unshift(@configureparams, "--disable-mcs-build");
	unshift(@configureparams, "--with-glib=embedded");
	unshift(@configureparams, "--disable-nls");  #this removes the dependency on gettext package
	unshift(@configureparams, "--prefix=$prefix");

	setenv ($path, $cinclude, $cppinclude, $cflags, $cxxflags, $cc, $cxx, $cpp, $cxxpp, $ld, $ldflags);

	$ENV{mono_cv_uscore} = "yes";
	$ENV{mono_cv_clang} = "no";
	$ENV{cv_mono_sizeof_sunpath} = "104";
	$ENV{ac_cv_func_posix_getpwuid_r} = "yes";
	$ENV{ac_cv_func_backtrace_symbols} = "no";

	$ENV{MACSDKOPTIONS} = $macsdkoptions;
	$ENV{MACSYSROOT} = $macsysroot;

	return (@configureparams);
}


sub build_mono
{
	my $arch = shift;
	my $buildtarget = shift;
	my $cachefile = shift;

	my $os = shift;
	my @configureparams = @{$_[0]};

	print("buildtarget: $buildtarget\n");

	my $saved_skipbuild = $skipbuild;
	my $saved_cleanbuild = $cleanbuild;

	if ($cleanbuild == 1) {
		system("rm $cachefile");
		my $i;
		foreach $i (qw(eglib libgc mono ikvm-native support))
		{
			system('make', '-C', $i, 'clean');
		}
	}

	if ($cleanbuild == 1 || $reconfigure == 1) {
		# Avoid "source directory already configured" ...
		system('rm', '-f', 'config.status', 'eglib/config.status', 'libgc/config.status');

		print("\n\nCalling autogen with these parameters: ");
		system("echo", @configureparams);
		print("\n\n");
		system("calling ./autogen.sh on $buildtarget",@configureparams);

		system("$monopath/autogen.sh", @configureparams) eq 0 or die ("failing configuring mono");

		system("perl -pi -e 's/MONO_SIZEOF_SUNPATH 0/MONO_SIZEOF_SUNPATH 104/' config.h") if ($arch eq 'armv6' || $arch eq 'armv7');
		system("perl -pi -e 's/#define HAVE_FINITE 1//' config.h") if ($arch eq 'armv6' || $arch eq 'armv7');
		system("perl -pi -e 's/#define HAVE_CURSES_H 1//' config.h") if ($arch eq 'armv6' || $arch eq 'armv7');
		system("perl -pi -e 's/#define HAVE_STRNDUP 1//' eglib/config.h") if ($os eq 'iphone' || $os eq 'crosscompiler');
	}

	system("make $jobs") eq 0 or die ("failing running make for mono");

	$skipbuild = $saved_skipbuild;
	$cleanbuild = $saved_cleanbuild;

}


sub build_osx
{
	my $os = "osx";
	my @arches = ('i386','x86_64');
	for my $arch (@arches) {
		print "\nBuilding $os for architecture: $arch\n";

		my $macversion = '10.5';
		$macversion = '10.6' if $arch eq 'x86_64';
		if($teamcity)
		{
		}
		my ($sdkversion, $sdkroot, $sdkpath) = detect_osx_sdk ('10.6');

		# Make architecture-specific targets and lipo at the end
		my $bintarget = "$distdir/bin-$arch";
		my $libtarget = "$embeddir/$os-$arch";
		my $buildtarget = "$buildir/$os-$arch";
		my $cachefile = "$buildir/$os-$arch.cache";
		$libtarget = "$embeddir/$os-minimal" if $minimal;

		print("bintarget: $bintarget\n");
		print("libtarget: $libtarget\n");
		print("buildtarget: $buildtarget\n");

		system("rm -f $bintarget/mono");
		system("rm -f $libtarget/libmono.0.dylib");
		system("rm -f $libtarget/libMonoPosixHelper.dylib");
		system("rm -rf $libtarget/libmono.0.dylib.dSYM");

		if (not $skipbuild)
		{
			my @configureparams = setenv_osx ($arch, $cachefile, $macversion, $sdkversion, $sdkroot, $sdkpath);
			build_mono ($arch, $buildtarget, $cachefile, $os, \@configureparams)
		}

		mkpath($bintarget);
		mkpath($libtarget);

		if ($ENV{"UNITY_THISISABUILDMACHINE"})
		{
		#	system("strip $libtarget/libmono.0.dylib") eq 0 or die("failed to strip libmono");
		#	system("strip $libtarget/MonoBundleBinary") eq 0 or die ("failed to strip MonoBundleBinary");
			system("echo \"mono-runtime-osx = $ENV{'BUILD_VCS_NUMBER'}\" > $buildsroot/versions.txt");
		}

		my $cmdline = "clang -arch $arch -bundle -Wl,-reexport_library $root/mono/mini/.libs/libmonoboehm-2.0.a -isysroot $sdkpath -mmacosx-version-min=$macversion -all_load -liconv -o $libtarget/MonoBundleBinary";
		print "About to call this cmdline to make a bundle:\n$cmdline\n";
		#system($cmdline) eq 0 or die("failed to link libmonoboehm-2.0.a into mono bundle");

		print "Hardlinking libmono.dylib\n";
		system("ln","-f", "$root/mono/mini/.libs/libmonoboehm-2.0.1.dylib","$libtarget/libmono.0.dylib") eq 0 or die ("failed symlinking libmono.0.dylib");

		print "Hardlinking libmono.a\n";
		system("ln", "-f", "$root/mono/mini/.libs/libmonoboehm-2.0.a","$libtarget/libmono.a") eq 0 or die ("failed symlinking libmono.a");

		print "Hardlinking libMonoPosixHelper.dylib\n";
		system("ln","-f", "$root/support/.libs/libMonoPosixHelper.dylib","$libtarget/libMonoPosixHelper.dylib") eq 0 or die ("failed symlinking $libtarget/libMonoPosixHelper.dylib");

		InstallNameTool("$libtarget/libmono.0.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/$os/libmono.0.dylib");
		InstallNameTool("$libtarget/libMonoPosixHelper.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/$os/libMonoPosixHelper.dylib");

		system("ln","-f","$root/mono/mini/mono","$bintarget/mono") eq 0 or die("failed hardlinking mono executable");
		system("ln","-f","$root/mono/metadata/pedump","$bintarget/pedump") eq 0 or die("failed hardlinking pedump executable");
	}



	mkpath ("$embeddir/$os");

	# Create universal binaries
	for my $file ('libmono.0.dylib','libmono.a','libMonoPosixHelper.dylib') {
		system ('lipo', "$embeddir/$os-i386/$file", "$embeddir/$os-x86_64/$file", '-create', '-output', "$embeddir/$os/$file");
	}

	if (not $ENV{"UNITY_THISISABUILDMACHINE"})
	{
		for my $file ('libmono.0.dylib','libMonoPosixHelper.dylib') {
			rmtree ("$embeddir/$os/$file.dSYM");
			system ('dsymutil', "$embeddir/$os/$file") eq 0 or warn ("Failed creating $embeddir/$os/$file.dSYM");
		}
	}

	#system('cp', "$embeddir/$os-i386/MonoBundleBinary", "$embeddir/$os/MonoBundleBinary");

	mkpath ("$distdir/bin");
	for my $file ('mono','pedump') {
		system ('lipo', "$distdir/bin-i386/$file", '-create', '-output', "$distdir/bin/$file");
		# Don't add 64bit executables for now...
		# system ('lipo', "$buildsroot/monodistribution/bin-i386/$file", "$buildsroot/monodistribution/bin-x86_64/$file", '-create', '-output', "$buildsroot/monodistribution/bin/$file");
	}

	mkpath ("$distdir/lib");
	# Create universal binaries
	for my $file ('libMonoPosixHelper.dylib') {
		system ('lipo', "$embeddir/$os-i386/$file", "$embeddir/$os-x86_64/$file", '-create', '-output', "$distdir/lib/$file");
	}

	if ($ENV{"UNITY_THISISABUILDMACHINE"}) {
		for my $arch (@arches) {
			# Clean up temporary arch-specific directories
			rmtree("$embeddir/$os-$arch");
			rmtree("$distdir/bin-$arch");
		}
	}
}

sub build_iphone_simulator
{
	my $os = "iphone";
	mkpath ("$embeddir/$os");


	for my $arch ('i386') {
		my $buildtarget = "$buildir/$os-$arch";
		my $cachefile = "$buildir/$os-$arch.cache";


		print "\nBuilding $os for architecture: $arch\n";

		my $macversion = '10.6';
		my ($sdkversion, $sdkroot, $sdkpath) = detect_iphonesim_sdk ('5.0');

		print("buildtarget: $buildtarget\n");

		if (not $skipbuild)
		{
			my @configureparams = setenv_iphone_simulator ($arch, $cachefile, $sdkversion, $sdkroot, $sdkpath);
			build_mono ($arch, $buildtarget, $cachefile, $os, \@configureparams);
		}

		print "Copying iPhone static lib to final destination\n";
		system("ln","-f","$buildtarget/mono/mini/.libs/libmono.a","$embeddir/$os/libmono-$arch.a") eq 0 or die("failed symlinking libmono-$arch.a");
	}

}

my $doiphones;
my $doosx;

$doiphones = 1 if $dobuild eq 'simulator';
$doosx = 1 if $dobuild eq 'osx';

print "build type: osx:$doosx simulator:$doiphones\n";

build_iphone_simulator if $doiphones;
build_osx if $doosx;
