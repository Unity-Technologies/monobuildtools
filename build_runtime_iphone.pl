use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);
my $buildScriptsRoot = "$monoroot/external/buildscripts";

my $clean = 1;
my $runtime = 0;
my $xcomp = 0;
my $simulator = 0;

GetOptions(
   "clean=i"=>\$clean,
   "runtime=i"=>\$runtime,
   "xcomp=i"=>\$xcomp,
   "simulator=i"=>\$simulator,
) or die ("illegal cmdline options");

# Build everything by default
if (!$runtime && !$xcomp && !simulator)
{
	$runtime = 1;
	$xcomp = 1;
	$simulator = 1;
}


if ($runtime)
{
	system("perl", "$buildScriptsRoot/build.pl", "--build=1", "--clean=$clean", "--artifact=1", "--arch32=1", "--iphoneArch=armv7", "--forcedefaultbuilddeps=1") eq 0 or die ("Failed builidng mono for iphone\n");
}

if ($xcomp)
{
	system("perl", "$buildScriptsRoot/build.pl", "--build=1", "--clean=$clean", "--artifact=1", "--arch32=1", "--iphonecross=1", "--forcedefaultbuilddeps=1") eq 0 or die ("Failed builidng iphone cross compiler\n");
}

if ($simulator)
{
	system("perl", "$buildScriptsRoot/build.pl", "--build=1", "--clean=$clean", "--artifact=1", "--arch32=1", "--iphonesimulator=1", "--forcedefaultbuilddeps=1") eq 0 or die ("Failed builidng iphone simulator\n");
}