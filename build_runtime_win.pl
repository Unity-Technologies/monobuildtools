sub CompileVCProj;
use Cwd 'abs_path';
use File::Spec;
use File::Basename;
use File::Copy;
use File::Path;
my $root = File::Spec->rel2abs (dirname($0) . '/../..');
my $buildsroot = "$root/builds";
my $buildir = $root;

my $monoroot = $root;

if ($ENV{UNITY_THISISABUILDMACHINE})
{
	print "rmtree-ing $root/builds because we're on a buildserver, and want to make sure we don't include old artifacts\n";
	rmtree("$root/builds");
} else {
	print "not rmtree-ing $root/builds, as we're not on a buildmachine";
}

CompileVCProj("$monoroot/msvc/mono.sln","Release|Win32",0);

my $remove = "$buildsroot/embedruntimes/win32/libmono.bsc";
if (-e $remove)
{
	unlink($remove) or die("can't delete libmono.bsc");
}


#have a duplicate for now...
print("Copying $buildsroot/embedruntimes/win32/mono.dll to $buildsroot/monodistribution/bin/mono.dll\n");
copy("$buildsroot/embedruntimes/win32/mono.dll","$buildsroot/monodistribution/bin/mono.dll");
copy("$buildsroot/embedruntimes/win32/mono.pdb","$buildsroot/monodistribution/bin/mono.pdb");

if ($ENV{UNITY_THISISABUILDMACHINE})
{
	system("echo mono-runtime-win32 = $ENV{'BUILD_VCS_NUMBER'} > $buildsrootwin\\versions.txt");
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













