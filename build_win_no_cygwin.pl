use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;
use File::Copy;
use lib ('external/buildscripts', "../../Tools/perl_lib","perl_lib", 'external/buildscripts/perl_lib');
use Tools qw(InstallNameTool);

print ">>> PATH in Build All = $ENV{PATH}\n\n";

my $currentdir = getcwd();

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);

$monoroot =~ tr{/}{\\};

print ">>> monoroot = $monoroot\n";

my $buildscriptsdir = "$monoroot\\external\\buildscripts";
my $addtoresultsdistdir = "$buildscriptsdir\\add_to_build_results\\monodistribution";
my $monoprefix = "$monoroot\\tmp\\monoprefix";
my $buildsroot = "$monoroot\\builds";
my $distdir = "$buildsroot\\monodistribution";
my $buildMachine = $ENV{UNITY_THISISABUILDMACHINE};

my $build=0;
my $clean=0;
my $artifact=0;
my $debug=0;
my $checkoutOnTheFly=0;
my $forceDefaultBuildDeps=0;
my $existingMonoRootPath = '';
my $arch32 = 0;
my $winPerl = "perl";
my $winMonoRoot = $monoroot;
my $msBuildVersion = "14.0";
my $buildDeps = "";

print(">>> Build All Args = @ARGV\n");

GetOptions(
	'build=i'=>\$build,
	'clean=i'=>\$clean,
	'artifact=i'=>\$artifact,
	'debug=i'=>\$debug,
	'arch32=i'=>\$arch32,
	'existingmono=s'=>\$existingMonoRootPath,
	'winperl=s'=>\$winPerl,
	'winmonoroot=s'=>\$winMonoRoot,
	'msbuildversion=s'=>\$msBuildVersion,
	'checkoutonthefly=i'=>\$checkoutOnTheFly,
	'builddeps=s'=>\$buildDeps,
	'forcedefaultbuilddeps=i'=>\$forceDefaultBuildDeps,
) or die ("illegal cmdline options");

my $monoRevision = `git rev-parse HEAD`;
chdir("$buildscriptsdir") eq 1 or die ("failed to chdir : $buildscriptsdir\n");
my $buildScriptsRevision = `git rev-parse HEAD`;
chdir("$monoroot") eq 1 or die ("failed to chdir : $monoroot\n");

print(">>> Mono Revision = $monoRevision\n");
print(">>> Build Scripts Revision = $buildScriptsRevision\n");

# Do any settings agnostic per-platform stuff
my $externalBuildDeps = "";

if ($buildDeps ne "" && not $forceDefaultBuildDeps)
{
	$externalBuildDeps = $buildDeps;
}
else
{
	$externalBuildDeps = "$monoroot/../../mono-build-deps/build";
}

my $existingExternalMonoRoot = "$externalBuildDeps\\mono";
my $existingExternalMono = "$existingExternalMonoRoot\\win";

if ($clean)
{
	print(">>> Cleaning $monoprefix\n");
	rmtree($monoprefix);

	print(">>> Cleaning $buildsroot\n");
	rmtree($buildsroot);
}

# *******************  Build Stage  **************************

if ($build)
{
	if ($existingMonoRootPath eq "")
	{
		print(">>> No existing mono supplied.  Checking for external...\n");
		
		if (!(-d "$externalBuildDeps"))
		{
			if (not $checkoutonthefly)
			{
				print(">>> No external build deps found.  Might as well try to check them out.  If it fails, we'll continue and trust mono is in your PATH\n");
			}

			# Check out on the fly
			print(">>> Checking out mono build dependencies to : $externalBuildDeps\n");
			my $repo = "https://ono.unity3d.com/unity-extra/mono-build-deps";
			print(">>> Cloning $repo at $externalBuildDeps\n");
			my $checkoutResult = system("hg", "clone", $repo, "$externalBuildDeps");

			if ($checkoutOnTheFly && $checkoutResult ne 0)
			{
				die("failed to checkout mono build dependencies\n");
			}
		}
		
		if (-d "$existingExternalMono")
		{
			print(">>> External mono found at : $existingExternalMono\n");
			
			if (-d "$existingExternalMono/builds")
			{
				print(">>> Mono already extracted at : $existingExternalMono/builds\n");
			}
			
			if (!(-d "$existingExternalMono/builds"))
			{
				# We need to extract builds.zip
				print(">>> Extracting mono builds.zip...\n");
				my $SevenZip = "$externalBuildDeps/7z/win64/7za.exe";
				print(">>> Using 7z : $SevenZip\n");
				system("$SevenZip", "x", "$existingExternalMono/builds.zip", "-o$existingExternalMono") eq 0 or die("Failed extracting mono builds.zip\n");
			}
			
			$existingMonoRootPath = "$existingExternalMono/builds";
		}
		else
		{
			print(">>> No external mono found.  Trusting a new enough mono is in your PATH.\n");
		}
	}
	
	if ($existingMonoRootPath ne "" && !(-d $existingMonoRootPath))
	{
		die("Existing mono not found at : $existingMonoRootPath\n");
	}

	system("$winPerl", "$winMonoRoot/external/buildscripts/build_runtime_vs.pl", "--build=$build", "--arch32=$arch32", "--msbuildversion=$msBuildVersion", "--clean=$clean", "--debug=$debug") eq 0 or die ('failing building mono with VS\n');

	if (!(-d "$monoroot\\tmp"))
	{
		print(">>> Creating directory $monoroot\\tmp\n");
		system("mkdir $monoroot\\tmp") eq 0 or die ("failing creating $monoroot\\tmp\n");;
	}

	if (!(-d "$monoprefix"))
	{
		print(">>> Creating directory $monoprefix\n");
		system("mkdir $monoprefix") eq 0 or die ("failing creating $monoprefix\n");;
	}

	if (!(-d "$monoprefix\\bin"))
	{
		print(">>> Creating directory $monoprefix\\bin\n");
		system("mkdir $monoprefix\\bin") eq 0 or die ("failing creating $monoprefix\\bin\n");;
	}

	# Copy over the VS built stuff that we want to use instead into the prefix directory
	my $archNameForBuild = $arch32 ? 'Win32' : 'x64';
	my $configDirName = $debug ? "Debug" : "Release";
	copy("$monoroot/msvc/$archNameForBuild/bin/$configDirName/mono.exe", "$monoprefix/bin/.") or die ("failed copying mono.exe\n");
	copy("$monoroot/msvc/$archNameForBuild/bin/$configDirName/mono-2.0.dll", "$monoprefix/bin/.") or die ("failed copying mono-2.0.dll\n");
	copy("$monoroot/msvc/$archNameForBuild/bin/$configDirName/mono-2.0.pdb", "$monoprefix/bin/.") or die ("failed copying mono-2.0.pdb\n");
	copy("$monoroot/msvc/$archNameForBuild/bin/$configDirName/mono-2.0.ilk", "$monoprefix/bin/.") or die ("failed copying mono-2.0.ilk\n");

	system("xcopy /y /f $addtoresultsdistdir\\bin\\*.* $monoprefix\\bin\\") eq 0 or die ("Failed copying $addtoresultsdistdir/bin to $monoprefix/bin\n");
}

# *******************  Artifact Stage  **************************

if ($artifact)
{
	print(">>> Creating artifact...\n");
	
	# Do the platform specific logic to create the builds output structure that we want
	
	my $embedDirRoot = "$buildsroot\\embedruntimes";

	my $embedDirArchDestination = $arch32 ? "$embedDirRoot\\win32" : "$embedDirRoot\\win64";
	my $distDirArchBin = $arch32 ? "$distdir\\bin" : "$distdir\\bin-x64";
	my $versionsOutputFile = $arch32 ? "$buildsroot\\versions-win32.txt" : "$buildsroot\\versions-win64.txt";
	
	# Make sure the directory for our architecture is clean before we copy stuff into it
	if (-d "$embedDirArchDestination")
	{
		print(">>> Cleaning $embedDirArchDestination\n");
		rmtree($embedDirArchDestination);
	}

	if (-d "$distDirArchBin")
	{
		print(">>> Cleaning $distDirArchBin\n");
		rmtree($distDirArchBin);
	}

	if (!(-d "$buildsroot"))
	{
		print(">>> Creating directory $buildsroot\n");
		system("mkdir $buildsroot") eq 0 or die("failed to create directory $buildsroot\n");
	}

	if (!(-d "$embedDirRoot"))
	{
		print(">>> Creating directory $embedDirRoot\n");
		system("mkdir $embedDirRoot") eq 0 or die("failed to create directory $embedDirRoot\n");
	}

	if (!(-d "$distdir"))
	{
		print(">>> Creating directory $distdir\n");
		system("mkdir $distdir") eq 0 or die("failed to create directory $distdir\n");
	}
	
	print(">>> Creating directory $embedDirArchDestination\n");
	system("mkdir $embedDirArchDestination") eq 0 or die("failed to create directory $embedDirArchDestination\n");

	print(">>> Creating directory $distDirArchBin\n");
	system("mkdir $distDirArchBin") eq 0 or die("failed to create directory $distDirArchBin\n");
	
	# embedruntimes directory setup
	print(">>> Creating embedruntimes directory : $embedDirArchDestination\n");
	copy("$monoprefix/bin/mono-2.0.dll", "$embedDirArchDestination/mono-2.0.dll") or die ("failed copying mono-2.0.dll\n");
	copy("$monoprefix/bin/mono-2.0.pdb", "$embedDirArchDestination/mono-2.0.pdb") or die ("failed copying mono-2.0.pdb\n");
	
	# monodistribution directory setup
	print(">>> Creating monodistribution directory\n");
	copy("$monoprefix/bin/mono-2.0.dll", "$distDirArchBin/mono-2.0.dll") or die ("failed copying mono-2.0.dll\n");
	copy("$monoprefix/bin/mono-2.0.pdb", "$distDirArchBin/mono-2.0.pdb") or die ("failed copying mono-2.0.pdb\n");
	copy("$monoprefix/bin/mono.exe", "$distDirArchBin/mono.exe") or die ("failed copying mono.exe\n");
	
	# Output version information
	print(">>> Creating version file : $versionsOutputFile\n");
	open(my $fh, '>', $versionsOutputFile) or die "Could not open file '$versionsOutputFile' $!";
	say $fh "mono-version =";
	my $monoVersionInfo = `$distDirArchBin\\mono --version`;
	say $fh "$monoVersionInfo";
	say $fh "unity-mono-revision = $monoRevision";
	say $fh "unity-mono-build-scripts-revision = $buildScriptsRevision";
	my $tmp = `date /T`;
	say $fh "$tmp";
	close $fh;
}
else
{
	print(">>> Skipping artifact creation\n");
}