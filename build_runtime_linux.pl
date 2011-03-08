use lib ('.', "../../Tools/perl_lib","perl_lib");
use Cwd;
use Cwd 'abs_path';
use File::Path;
use Getopt::Long;
use Tools qw(InstallNameTool);

my $root = getcwd();
my $monoroot = abs_path($root."/../Mono");
my $skipbuild=0;
my $debug = 0;
my $minimal = 0;

GetOptions(
   "skipbuild=i"=>\$skipbuild,
   "debug=i"=>\$debug,
   "minimal=i"=>\$minimal,
) or die ("illegal cmdline options");

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

my $bintarget = "$root/builds/monodistribution/bin-linux";
my $libtarget = "$root/builds/embedruntimes/linux";

if ($minimal)
{
	$libtarget = "$root/builds/embedruntimes/linux-minimal";
}
print("libtarget: $libtarget\n");

system("rm -f $bintarget/mono");
system("rm -f $libtarget/libmono.so");
system("rm -f $libtarget/libmono-static.a");

if (not $skipbuild)
{
	#rmtree($bintarget);
	#rmtree($libtarget);

	if ($debug)
	{
		$ENV{CFLAGS} = "-m32 -g -O0";
		$ENV{LDFLAGS} = "-m32";
	} else
	{
		$ENV{CFLAGS} = "-m32 -Os";  #optimize for size
		$ENV{LDFLAGS} = "-m32";
	}

	chdir("$monoroot") eq 1 or die ("Failed chdir 2");

	#this will fail on a fresh working copy, so don't die on it.
	system("make distclean");
	#were going to tell autogen to use a specific cache file, that we purposely remove before starting.
        #that way, autogen is forced to do all its config stuff again, which should make this buildscript
        #more robust if other targetplatforms have been built from this same workincopy
        system("rm linux.cache");

	system("autoreconf -i") eq 0 or die ("Failed autoreconfing mono");
	my @autogenparams = ();
	unshift(@autogenparams, "--cache-file=linux.cache");
	unshift(@autogenparams, "--disable-mcs-build");
	unshift(@autogenparams, "--with-glib=embedded");
	unshift(@autogenparams, "--disable-nls");  #this removes the dependency on gettext package
	unshift(@autogenparams, "--disable-parallel-mark");  #this causes crashes
	unshift(@autogenparams, "--build=i686-pc-linux-gnu");  #Force x86 build

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
	system("make -j4") eq 0 or die ("failing running make for mono");
}

mkpath($bintarget);
mkpath($libtarget);

print "Copying libmono.so\n";
system("cp", "$monoroot/mono/mini/.libs/libmono-2.0.so.0","$libtarget/libmono.so") eq 0 or die ("failed copying libmono.so.0");

print "Copying libmono.a\n";
system("cp", "$monoroot/mono/mini/.libs/libmono-2.0.a","$libtarget/libmono-static.a") eq 0 or die ("failed copying libmono.a");

if ($ENV{"UNITY_THISISABUILDMACHINE"})
{
	system("strip $libtarget/libmono.so") eq 0 or die("failed to strip libmono (shared)");
}

system("ln","-f","$monoroot/mono/mini/mono","$bintarget/mono") eq 0 or die("failed symlinking mono executable");
system("ln","-f","$monoroot/mono/metadata/pedump","$bintarget/pedump") eq 0 or die("failed symlinking pedump executable");
system("chmod","-R","755",$bintarget);
