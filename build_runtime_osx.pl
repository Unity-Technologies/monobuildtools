use lib ('.', "../../Tools/perl_lib","perl_lib");
use Cwd;
use Cwd 'abs_path';
use File::Path;
use Getopt::Long;
use Tools qw(InstallNameTool GitClone);

my $root = getcwd();
my $monoroot = abs_path($root."/../Mono");
my $skipbuild=0;
my $debug = 0;
my $minimal = 0;
my $iphone_simulator = 0;
my $skipclasslibs = 1;
my $llvm=0;
my $llvmstatic=0;
my $macversion = "10.5";
my $sdkversion = "10.5";

my $llvmCheckout = "$root/external/llvm";
my $llvmPrefix = "$root/tmp/llvmprefix";

GetOptions(
   "skipbuild=i"=>\$skipbuild,
   "debug=i"=>\$debug,
   "minimal=i"=>\$minimal,
   "iphone_simulator=i"=>\$iphone_simulator,
   "skipclasslibs=i"=>\$skipclasslibs,
   "llvm=i"=>\$llvm
) or die ("illegal cmdline options");

my $arch;
my $uname = `uname -p`;

my $teamcity=0;
if ($ENV{UNITY_THISISABUILDMACHINE})
{
	print "rmtree-ing $root/builds because we're on a buildserver, and want to make sure we don't include old artifacts\n";
	rmtree("$root/builds");
	$teamcity=1;
} else {
	print "not rmtree-ing $root/builds, as we're not on a buildmachine";
	if (($debug==0) && ($skipbuild==0))
	{
		print "\n\nARE YOU SURE YOU DONT WANT TO MAKE A DEBUG BUILD?!?!?!!!!!\n\n\n";
	}
}

#libtarget depends on the arch, as we can just link to a ppc dylib and to an i386 dylib and all is fine.
#bin does not depend on the arch, because we need a mono executable that is a universal binary. Unfortunattely
#we cannot create a mono universal binary, so we have to lipo that up in a teamcity buildstep

my $osx_gcc_arguments = " -isysroot /Developer/SDKs/MacOSX$sdkversion.sdk -mmacosx-version-min=$macversion ";

for $arch ('i386','x86_64') {
	my $bintarget = "$root/builds/monodistribution/bin-$arch";
	my $libtarget = "$root/builds/embedruntimes/osx-$arch";

	if ($minimal)
	{
		$libtarget = "$root/builds/embedruntimes/osx-minimal";
	}
	print("libtarget: $libtarget\n");

	system("rm $bintarget/mono");
	system("rm $libtarget/libmono.dylib");
	system("rm -rf $libtarget/libmono.dylib.dSYM");
	system("rm $libtarget/libmonosgen-2.0.0.dylib");
	system("rm -rf $libtarget/libmonosgen-2.0.0.dylib.dSYM");

	print "Building for architecture: $arch\n";

	if (not $skipbuild)
	{
		if ($llvm) {
			if (!$ENV{UNITY_THISISABUILDMACHINE}) {
				GitClone("git://github.com/mono/llvm.git", $llvmCheckout, "mono-2-10");
			}
			
			$ENV{CFLAGS} = "-mmacosx-version-min=10.5 -isysroot /Developer/SDKs/MacOSX10.5.sdk";
			$ENV{CXXFLAGS} = "-mmacosx-version-min=10.5 -isysroot /Developer/SDKs/MacOSX10.5.sdk";

			chdir("$llvmCheckout");
			my @configureparams = ();
			unshift(@configureparams, "--prefix=$llvmPrefix");
			unshift(@configureparams, "--host=i686-apple-darwin11");
			unshift(@configureparams, "--target=i686-apple-darwin11");
			unshift(@configureparams, "--build=i686-apple-darwin11");
			system("./configure", @configureparams) eq 0 or die ("Failed llvm configure");
			system("make") eq 0 or die ("Failed llvm make");
			system("make install") eq 0 or die ("Failed llvm make");
			
			$ENV{PATH} = "$llvmPrefix/bin" . ":" . $ENV{PATH};
		}	

		#rmtree($bintarget);
		#rmtree($libtarget);

		if ($iphone_simulator)
		{
			$ENV{CFLAGS} = "-D_XOPEN_SOURCE=1 -DTARGET_IPHONE_SIMULATOR -g -O0";
			$macversion = "10.6";
			$sdkversion = "10.6";
		}

		print "monoroot is $monoroot\n";	
		chdir("$monoroot") eq 1 or die ("failed to chdir 1");
		#this will fail on a fresh working copy, so don't die on it.
		system("make distclean");
		#were going to tell autogen to use a specific cache file, that we purposely remove before starting.
		#that way, autogen is forced to do all its config stuff again, which should make this buildscript
		#more robust if other targetplatforms have been built from this same workincopy
		system("rm osx.cache");

		chdir("$monoroot/eglib") eq 1 or die ("Failed chdir 1");
		
		#this will fail on a fresh working copy, so don't die on it.
		system("make distclean");
		system("autoreconf -i") eq 0 or die ("Failed autoreconfing eglib");
		chdir("$monoroot") eq 1 or die ("failed to chdir 2");
		system("autoreconf -i") eq 0 or die ("Failed autoreconfing mono");
		my @autogenparams = ();
		unshift(@autogenparams, "--cache-file=osx.cache");
		if ($skipclasslibs)
		{
			#rmtree($bintarget);
			#rmtree($libtarget);

			if ($debug)
			{
				$ENV{CFLAGS} = "-g -O0 -DMONO_DISABLE_SHM=1 -arch $arch";
				$ENV{LDFLAGS} = "-arch $arch";
			} else
			{
				$ENV{CFLAGS} = "-Os -DMONO_DISABLE_SHM=1 -arch $arch";  #optimize for size
				$ENV{LDFLAGS} = "-arch $arch";
			}

			$ENV{CFLAGS} = $ENV{CFLAGS}.$osx_gcc_arguments ;

			print "cflags = $ENV{CFLAGS}\n";

			print "monoroot is $monoroot\n";	
			chdir("$monoroot") eq 1 or die ("failed to chdir 1");
			#this will fail on a fresh working copy, so don't die on it.
			# system("make distclean");
			#were going to tell autogen to use a specific cache file, that we purposely remove before starting.
			#that way, autogen is forced to do all its config stuff again, which should make this buildscript
			#more robust if other targetplatforms have been built from this same workincopy
			system("rm osx.cache");

			system("autoreconf -i") eq 0 or die ("Failed autoreconfing mono");
			my @autogenparams = ();
			unshift(@autogenparams, "--cache-file=osx.cache");
			if ($skipclasslibs)
			{
				unshift(@autogenparams, "--disable-mcs-build");
			}
			unshift(@autogenparams, "--with-glib=embedded");
			unshift(@autogenparams, "--with-sgen=yes");
			unshift(@autogenparams, "--disable-nls");  #this removes the dependency on gettext package
			if (!$iphone_simulator)
			{
				unshift(@autogenparams, "--with-macversion=$macversion");
				if ($llvm)
				{
					unshift(@autogenparams, "--enable-llvm=yes");
					unshift(@autogenparams, "--enable-loadedllvm=yes");
				}
			}

			# From Massi: I was getting failures in install_name_tool about space
			# for the commands being too small, and adding here things like
			# $ENV{LDFLAGS} = '-headerpad_max_install_names' and
			# $ENV{LDFLAGS} = '-headerpad=0x40000' did not help at all (and also
			# adding them to our final gcc invocation to make the bundle).
			# Lucas noticed that I was lacking a Mono prefix, and having a long
			# one would give us space, so here is this silly looong prefix.
			# unshift(@autogenparams, "--prefix=/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890/1234567890");

			if ($minimal)
			{
				unshift(@autogenparams,"--enable-minimal=aot,logging,com,profiler,debug");
			}

			print("\n\n\n\nCalling configure with these parameters: ");
			system("echo", @autogenparams);
			print("\n\n\n\n\n");
			system("calling ./configure",@autogenparams);
			system("./configure", @autogenparams) eq 0 or die ("failing configuring mono");

			system("make clean") eq 0 or die ("failed make cleaning");
			if ($iphone_simulator)
			{
				system("perl -pi -e 's/#define HAVE_STRNDUP 1//' eglib/config.h");
			}
			system("make") eq 0 or die ("failing runnig make for mono");
		}

	chdir($root);

	mkpath($bintarget);
	mkpath($libtarget);

	my $cmdline = "gcc -arch $arch -bundle -reexport_library $monoroot/mono/mini/.libs/libmono-2.0.a $osx_gcc_arguments -all_load -framework CoreFoundation -liconv -o $libtarget/MonoBundleBinary";

	if ($llvmstatic) {
		$ENV{PATH} = "$llvmPrefix/bin" . ":" . $ENV{PATH};

		chop($llvmldflags = `llvm-config --ldflags`);
		chop($llvmlibs = `llvm-config --libs core bitwriter jit x86codegen`);

		$cmdline = "${cmdline} ${llvmldflags} ${llvmlibs} -lstdc++";
	}

	if (!$iphone_simulator)
	{
		print "About to call this cmdline to make a bundle:\n$cmdline\n";
		system($cmdline) eq 0 or die("failed to link libmono.a into mono bundle");

		print "Symlinking libmono.dylib\n";
		system("ln","-f", "$monoroot/mono/mini/.libs/libmono-2.0.dylib","$libtarget/libmono.0.dylib") eq 0 or die ("failed symlinking libmono-2.0.dylib");

		print "Symlinking libmono.a\n";
		system("ln", "-f", "$monoroot/mono/mini/.libs/libmono-2.0.a","$libtarget/libmono.a") eq 0 or die ("failed symlinking libmono-2.0.a");

		if (($arch eq 'i386') and (not $ENV{"UNITY_THISISABUILDMACHINE"}))
		{
			system("ln","-fs", "$monoroot/mono/mini/.libs/libmono-2.0.dylib.dSYM","$libtarget/libmono.0.dylib.dSYM") eq 0 or die ("failed symlinking libmono-2.0.dylib.dSYM");
		}

		print "Symlinking libmonosgen-2.0.0.dylib\n";
		system("ln","-f", "$monoroot/mono/mini/.libs/libmonosgen-2.0.0.dylib","$libtarget/libmonosgen-2.0.0.dylib") eq 0 or die ("failed symlinking libmonosgen-2.0.0.dylib");

		print "Symlinking libmonosgen-2.0.a\n";
		system("ln","-f", "$monoroot/mono/mini/.libs/libmonosgen-2.0.a","$libtarget/libmonosgen-2.0.a") eq 0 or die ("failed symlinking libmonosgen-2.0.a");

		if (($arch eq 'i386') and (not $ENV{"UNITY_THISISABUILDMACHINE"}))
		{
			system("ln","-fs", "$monoroot/mono/mini/.libs/libmonosgen-2.0.0.dylib.dSYM","$libtarget/libmonosgen-2.0.0.dylib.dSYM") eq 0 or die ("failed symlinking libmonosgen-2.0.0.dylib.dSYM");
		}


	if ($ENV{"UNITY_THISISABUILDMACHINE"})
	{
	#	system("strip $libtarget/libmono.0.dylib") eq 0 or die("failed to strip libmono");
	#	system("strip $libtarget/MonoBundleBinary") eq 0 or die ("failed to strip MonoBundleBinary");
		system("echo \"mono-runtime-osx = $ENV{'BUILD_VCS_NUMBER_mono_unity_2_10_2'}\" > $root/builds/versions.txt");
	}

	InstallNameTool("$libtarget/libmono.0.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/osx/libmono.0.dylib");
	InstallNameTool("$libtarget/libmonosgen-2.0.0.dylib", "\@executable_path/../Frameworks/MonoEmbedRuntime/osx/libmonosgen-2.0.0.dylib");

	system("ln","-f","$monoroot/mono/mini/mono","$bintarget/mono") eq 0 or die("failed symlinking mono executable");
	system("ln","-f","$monoroot/mono/mini/mono-sgen","$bintarget/mono-sgen") eq 0 or die("failed symlinking mono-sgen executable");
	system("ln","-f","$monoroot/mono/metadata/pedump","$bintarget/pedump") eq 0 or die("failed symlinking pedump executable");
}

# Create universal binaries
mkpath ("$root/builds/embedruntimes/osx");
mkpath ("$root/builds/monodistribution/bin");
for $file ('MonoBundleBinary','libmono.0.dylib','libmono.a') {
	system ('lipo', "$root/builds/embedruntimes/osx-i386/$file", "$root/builds/embedruntimes/osx-x86_64/$file", '-create', '-output', "$root/builds/embedruntimes/osx/$file");
}
for $file ('mono','mono-sgen','pedump') {
	system ('lipo', "$root/builds/monodistribution/bin-i386/$file", "$root/builds/monodistribution/bin-x86_64/$file", '-create', '-output', "$root/builds/monodistribution/bin/$file");
}
}
}
