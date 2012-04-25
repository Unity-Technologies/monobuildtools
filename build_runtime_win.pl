sub CompileVCProj;
use File::Spec;
use File::Basename;
use File::Copy;
use File::Path;
use Getopt::Long;
my $root = File::Spec->rel2abs( dirname($0) );
my $monoroot = File::Spec->rel2abs( dirname($0) . "/../mono" );

my $skipbuild=0;
my $debug = 0;
my $build64 = 0;

GetOptions(
   "skipbuild=i"=>\$skipbuild,
   "debug=i"=>\$debug,
   "build64=i"=>\$build64,
) or die ("illegal cmdline options");

if ($ENV{UNITY_THISISABUILDMACHINE})
{
	print "rmtree-ing $root/builds because we're on a buildserver, and want to make sure we don't include old artifacts\n";
	rmtree("$root/builds");
} else {
	print "not rmtree-ing $root/builds, as we're not on a buildmachine";
}

my $config = "Release";
my $platform = "Win32";
my $embedDir = "win32";
my $binDirectory = "bin";

if ($debug)
{
	$config = "Debug";
}

if ($build64)
{
	$platform = "x64";
	$embedDir = "win64";
	$binDirectory = "bin-x64";
}

if (not $skipbuild)
{
	CompileVCProj("$monoroot/msvc/mono.sln","$config|$platform",0);
	my $remove = "$root/builds/embedruntimes/$embedDir/libmono.bsc";
	if (-e $remove)
	{
		unlink($remove) or die("can't delete libmono.bsc");
	}
}

mkpath("$root/builds/embedruntimes/$embedDir");
mkpath("$root/builds/monodistribution/$binDirectory");
copy("$monoroot/msvc/$platform/bin/mono-2.0.dll","$root/builds/embedruntimes/$embedDir/mono.dll");
copy("$monoroot/msvc/$platform/bin/mono-2.0.pdb","$root/builds/embedruntimes/$embedDir/mono.pdb");
copy("$monoroot/msvc/$platform/bin/mono.exe","$root/builds/monodistribution/$binDirectory/mono.exe");
copy("$monoroot/msvc/$platform/bin/mono-2.0.dll","$root/builds/monodistribution/$binDirectory/");
copy("$monoroot/msvc/$platform/bin/mono-2.0.pdb","$root/builds/monodistribution/$binDirectory/");

if ($ENV{UNITY_THISISABUILDMACHINE})
{
	system("echo mono-runtime-$embedDir = $ENV{'BUILD_VCS_NUMBER'} > $root\\builds\\versions.txt");
}

sub CompileVCProj
{
	my $sln = shift(@_);
	my $slnconfig = shift(@_);
	my $incremental = shift(@_);
	my $projectname = shift(@_);
	my @optional = @_;
	
	
	my @devenvlocations = ($ENV{"PROGRAMFILES(X86)"}."/Microsoft Visual Studio 10.0/Common7/IDE/devenv.com",
		       "$ENV{PROGRAMFILES}/Microsoft Visual Studio 10.0/Common7/IDE/devenv.com",
		       "$ENV{REALVSPATH}/Common7/IDE/devenv.com");
	
	my $devenv;
	foreach my $devenvoption (@devenvlocations)
	{
		if (-e $devenvoption) {
			$devenv = $devenvoption;
		}
	}
	
	my $buildcmd = $incremental ? "/build" : "/rebuild";
	
        if (defined $projectname)
        {
            print "devenv.exe $sln $buildcmd $slnconfig /project $projectname @optional \n\n";
            system($devenv, $sln, $buildcmd, $slnconfig, '/project', $projectname, @optional) eq 0
                    or die("VisualStudio failed to build $sln");
        } else {
            print "devenv.exe $sln $buildcmd $slnconfig\n\n";
            system($devenv, $sln, $buildcmd, $slnconfig) eq 0
                    or die("VisualStudio failed to build $sln");
        }
}













