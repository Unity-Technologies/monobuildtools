sub CompileVCProj;
use Cwd 'abs_path';
use Getopt::Long;
use File::Spec;
use File::Basename;
use File::Copy;
use File::Path;

print ">>> PATH in Build VS = $ENV{PATH}\n\n";

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);
my $buildsroot = "$monoroot/builds";
my $buildMachine = $ENV{UNITY_THISISABUILDMACHINE};

my $build = 0;
my $arch32 = 0;
my $debug = 0;
my $vsVersion = "";

GetOptions(
	'build=i'=>\$build,
	'arch32=i'=>\$arch32,
	'vsversion=s'=>\$vsVersion,
) or die ("illegal cmdline options");

my $archNameForBuild = $arch32 ? 'Win32' : 'x64';
my $archNameForDir = $arch32 ? 'win32' : 'win64';
my $archNameForBinDir = $arch32 ? 'bin' : 'bin-x64';

if ($build)
{
	CompileVCProj("$monoroot/msvc/mono.sln","Release|$archNameForBuild", 0);
}

if ($buildMachine)
{
	system("echo mono-runtime-win32 = $ENV{'BUILD_VCS_NUMBER'} > $buildsrootwin\\versions.txt");
}

sub CompileVCProj
{
	my $sln = shift(@_);
	my $slnconfig = shift(@_);
	my $incremental = shift(@_);
	my @optional = @_;
	
	my $msbuild = $ENV{"ProgramFiles(x86)"}."/MSBuild/$vsVersion/Bin/MSBuild.exe";
	
	my $config = $debug ? "Debug" : "Release";
	my $arch = $arch32 ? "Win32" : "x64";
	my $target = "/t:Clean,Build";
	my $properties = "/p:Configuration=$config;Platform=$arch";
	
	print ">>> $devenv $properties $target $sln\n\n";
	system($msbuild, $properties, $target, $sln) eq 0
			or die("VisualStudio failed to build $sln\n");
}













