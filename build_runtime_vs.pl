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
	CompileVCProj("$monoroot/msvc/mono.sln","Release|$archNameForBuild", 0, $vsVersion);
}

my $remove = "$buildsroot/embedruntimes/$archNameForDir/libmono.bsc";
if (-e $remove)
{
	unlink($remove) or die("can't delete libmono.bsc");
}


#have a duplicate for now...
print("Copying $buildsroot/embedruntimes/$archNameForDir/mono.dll to $buildsroot/monodistribution/$archNameForBinDir/mono.dll\n");
copy("$buildsroot/embedruntimes/$archNameForDir/mono.dll","$buildsroot/monodistribution/$archNameForBinDir/mono.dll");
copy("$buildsroot/embedruntimes/$archNameForDir/mono.pdb","$buildsroot/monodistribution/$archNameForBinDir/mono.pdb");

if ($buildMachine)
{
	system("echo mono-runtime-win32 = $ENV{'BUILD_VCS_NUMBER'} > $buildsrootwin\\versions.txt");
}

sub CompileVCProj
{
	my $sln = shift(@_);
	my $slnconfig = shift(@_);
	my $incremental = shift(@_);
	my $version = shift(@_);
	my $projectname = shift(@_);
	my @optional = @_;
	
	
	my @devenvlocations = ($ENV{"ProgramFiles(x86)"}."/Microsoft Visual Studio $version/Common7/IDE/devenv.com",
			"$ENV{ProgramFiles}/Microsoft Visual Studio $version/Common7/IDE/devenv.com",
			"$ENV{REALVSPATH}/Common7/IDE/devenv.com");
	
	my $devenv;
	foreach my $devenvoption (@devenvlocations)
	{
		print ("$devenvoption\n");
		if (-e $devenvoption) {
			$devenv = $devenvoption;
		}
	}
	
	my $buildcmd = $incremental ? "/build" : "/rebuild";
	
	if (defined $projectname)
	{
		print ">>> $devenv $sln $buildcmd $slnconfig /project $projectname @optional \n\n";
		system($devenv, $sln, $buildcmd, $slnconfig, '/project', $projectname, @optional) eq 0
				or die("VisualStudio failed to build $sln\n");
	}
	else
	{
		print ">>> $devenv $sln $buildcmd $slnconfig\n\n";
		system($devenv, $sln, $buildcmd, $slnconfig) eq 0
				or die("VisualStudio failed to build $sln\n");
	}
}













