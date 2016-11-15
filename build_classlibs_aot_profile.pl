use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);
my $buildScriptsRoot = "$monoroot/external/buildscripts";

my $clean = 1;
my $disableNormalProfile = 1;

# Handy troubleshooting/niche options
my $shortPrefix = 0;

GetOptions(
   "clean=i"=>\$clean,
   'disablenormalprofile=i'=>\$disableNormalProfile,
   'shortprefix=i'=>\$shortPrefix,
) or die ("illegal cmdline options");

system("perl", "$buildScriptsRoot/build.pl", "--build=1", "--clean=$clean", "--artifact=1", "--artifactscommon=1", "--aotprofile=1", "--forcedefaultbuilddeps=1", "--shortprefix=$shortPrefix", "--disablenormalprofile=$disableNormalProfile") eq 0 or die ("Failed builidng aot profile\n");