use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);
my $buildScriptsRoot = "$monoroot/external/buildscripts";

my $build = 1;
my $clean = 1;

# Handy troubleshooting/niche options
my $shortPrefix = 0;

GetOptions(
   "build=i"=>\$build,
   "clean=i"=>\$clean,
   'shortprefix=i'=>\$shortPrefix,
) or die ("illegal cmdline options");

system(
	"perl",
	"$buildScriptsRoot/build.pl",
	"--build=$build",
	"--clean=$clean",
	"--artifact=1",
	"--artifactscommon=1",
	"--aotprofile=mobile_static",
	"--aotprofiledestname=unity_aot",
	"--buildusandboo=1",
	"--forcedefaultbuilddeps=1",
	"--shortprefix=$shortPrefix") eq 0 or die ("Failed builidng mono\n");