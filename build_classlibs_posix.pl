use lib ('.', 'perl_lib', 'external/buildscripts/perl_lib');
use Cwd ;
use Cwd 'abs_path';
use File::Path;
use File::Copy::Recursive qw(dircopy);
use Getopt::Long;
use File::Basename;
use Tools qw(GitClone);

system("source","~/.profile");
print "My Path: $ENV{PATH}\n";

my $root = getcwd();

my $monoroot = $root;
my $monodistro = "$root/builds/monodistribution";
my $lib = "$monodistro/lib";
my $libmono = "$lib/mono";
my $monoprefix = "$root/tmp/monoprefix";
my $buildscriptsdir = "$root/external/buildscripts";

my $dependencyBranchToUse = "unity3.0";

if ($ENV{UNITY_THISISABUILDMACHINE}) {
	print "rmtree-ing $root/builds because we're on a buildserver, and want to make sure we don't include old artifacts\n";
	rmtree("$root/builds");
} else {
	print "not rmtree-ing $root/builds, as we're not on a buildmachine\n";
}

my $skipbuild=0;
my $cleanbuild=1;
my $jobs=8;

GetOptions(
   'skipbuild=i'=>\$skipbuild,
   'cleanbuild=i'=>\$cleanbuild,
   'jobs=i'=>\$jobs,
) or die ("illegal cmdline options");



if (-d $libmono)
{
	rmtree($libmono);
} 

if (not $skipbuild)
{
	my $target = "";

	if($^O eq "linux")
	{
		$ENV{CFLAGS} = $ENV{CXXFLAGS} = $ENV{LDFLAGS} = "-m32";
		$target = "--target=i686-pc-linux-gnu";
		$host = "--host=i686-pc-linux-gnu";
		$build = "--build=i686-pc-linux-gnu";
	}

	if ($cleanbuild)
	{
		rmtree($monoprefix);
	}
	chdir("$monoroot") eq 1 or die ("failed to chdir 2");
	if ($cleanbuild)
	{
		chdir("$monoroot") eq 1 or die("failed to chdir4");
		# print(">>>Calling autoreconf in mono\n");
		# system("autoreconf -i") eq 0 or die("failed to autoreconf mono");

		# Avoid "source directory already configured" ...
		system('rm', '-f', 'config.status', 'eglib/config.status', 'libgc/config.status');

		print(">>>Calling autogen in mono\n");
		system('./autogen.sh',"--prefix=$monoprefix",$host,'--with-monotouch=no', '--with-profile2=no','--with-glib=embedded','--with-mcs-docs=no', '--disable-nls') eq 0 or die ('failing autogenning mono');
		print("calling make clean in mono\n");
		system("make","clean") eq 0 or die ("failed to make clean");
	}
	system('make', "-j$jobs") eq 0 or die ('Failed running make');
	system("make install") eq 0 or die ("Failed running make install");
}
chdir ($root);

$File::Copy::Recursive::CopyLink = 0;  #make sure we copy files as files and not as symlinks, as TC unfortunately doesn't pick up symlinks.

#my @profiles = ("2.0","3.5","4.0","4.5");
my @profiles = ('4.0', '4.5');
for my $profile (@profiles)
{
	mkpath("$libmono/$profile");
	dircopy("$monoprefix/lib/mono/$profile","$libmono/$profile");
	system("rm $libmono/$profile/*.mdb");
}
system("cp -r $monoprefix/bin $monodistro/") eq 0 or die ("failed copying bin folder");
system("cp -r $monoprefix/etc $monodistro/") eq 0 or die("failed copy 4");
system("cp -r $monoprefix/lib/mono/gac $monodistro/lib/mono") eq 0 or die("failed copy gac");

sub CopyIgnoringHiddenFiles
{
	my $sourceDir = shift;
	my $targetDir = shift;

	#really need to find a better way to copy a dir, ignoring .svn's than rsync.	
	system("rsync -a -v --exclude='.*' $sourceDir $targetDir") eq 0 or die("failed to rsync $sourceDir to $targetDir");
}

CopyIgnoringHiddenFiles("$buildscriptsdir/add_to_build_results/monodistribution/", "$monoprefix/");

sub cp
{
	my $cmdLine = shift;
	# we can't die if copy fails, as some profiles may not have *.exe files
	#system("cp $cmdLine") eq 0 or die("failed to copy '$cmdLine'");
	system("cp $cmdLine");
}

sub CopyAssemblies
{
	my $sourceFolder = shift; 
	my $targetFolder = shift;
	
	print "Copying assemblies from '$sourceFolder' to '$targetFolder'...\n";
	
	mkpath($targetFolder);
	cp("$sourceFolder/*.dll $targetFolder/");
	cp("$sourceFolder/*.exe $targetFolder/");
	cp("$sourceFolder/*.mdb $targetFolder/");
}

sub CopyProfileAssemblies
{
	my $sourceName = shift;
	my $targetName = shift;
	CopyProfileAssembliesToPrefix($sourceName, $targetName, $monodistro)
}

sub CopyProfileAssembliesToPrefix
{
	my $sourceName = shift;
	my $targetName = shift;
	my $prefix = shift;
	
	my $targetDir = "$prefix/lib/mono/$targetName";
	CopyAssemblies("$monoroot/mcs/class/lib/$sourceName", $targetDir);
}

sub XBuild
{
   system("$monoprefix/bin/xbuild", @_) eq 0 or die("Failed to xbuild @_");
}

sub RunXBuildTargetOnProfile
{
	my $target = shift;	
	my $profile = shift;
	
	XBuild("$securityAttributesPath/SecurityAttributes.proj", "/p:Profile=$profile", "/p:ProfilePrefix=$monodistro", "/t:$target") eq 0 or die("failed to run target '$target' on $profile");
}

my $monoprefixUnity = "$monoprefix/lib/mono/unity";
my $monoprefix45 = "$monoprefix/lib/mono/4.0";
my $monodistroLibMono = "$monodistro/lib/mono";
my $monodistro45 = "$monodistroLibMono/4.0";

sub UnityBooc
{
	my $commandLine = shift;
	
	system("$monoprefixUnity/booc -debug- $commandLine") eq 0 or die("booc failed to execute: $commandLine");
}

sub Booc
{
	my $commandLine = shift;
	
	system("$monoprefix45/booc -debug- $commandLine") eq 0 or die("booc failed to execute: $commandLine");
}

sub BuildUnityScriptForUnity
{
	my $booCheckout = "external/boo";
	
	# TeamCity is handling this
	if (!$ENV{UNITY_THISISABUILDMACHINE}) {
		GitClone("git://github.com/Unity-Technologies/boo.git", $booCheckout, "unity-trunk");
	}
	UnityXBuild("$booCheckout/src/booc/booc.csproj");
	
	cp("$booCheckout/ide-build/Boo.Lang*.dll $monoprefixUnity/");
	cp("$booCheckout/ide-build/booc.exe $monoprefixUnity/");
	UnityBooc("-out:$monoprefixUnity/Boo.Lang.Extensions.dll -noconfig -nostdlib -srcdir:$booCheckout/src/Boo.Lang.Extensions -r:System.dll -r:System.Core.dll -r:mscorlib.dll -r:Boo.Lang.dll -r:Boo.Lang.Compiler.dll");
	UnityBooc("-out:$monoprefixUnity/Boo.Lang.Useful.dll -srcdir:$booCheckout/src/Boo.Lang.Useful -r:Boo.Lang.Parser");
	UnityBooc("-out:$monoprefixUnity/Boo.Lang.PatternMatching.dll -srcdir:$booCheckout/src/Boo.Lang.PatternMatching");
	
	# micro profile version
	#UnityXBuild("$booCheckout/src/Boo.Lang/Boo.Lang.csproj", "Micro-Release");
	#cp("$booCheckout/src/Boo.Lang/bin/Micro-Release/Boo.Lang.dll $monodistroLibMono/micro/");
	
	my $usCheckout = "external/unityscript";
	if (!$ENV{UNITY_THISISABUILDMACHINE}) {
		GitClone("git://github.com/Unity-Technologies/unityscript.git", $usCheckout, "unity-trunk");
	}
	
	my $UnityScriptLangDLL = "$monoprefixUnity/UnityScript.Lang.dll";
	UnityBooc("-out:$UnityScriptLangDLL -srcdir:$usCheckout/src/UnityScript.Lang");
	
	my $UnityScriptDLL = "$monoprefixUnity/UnityScript.dll";
	UnityBooc("-out:$UnityScriptDLL -srcdir:$usCheckout/src/UnityScript -r:$UnityScriptLangDLL -r:Boo.Lang.Parser.dll -r:Boo.Lang.PatternMatching.dll");
	UnityBooc("-out:$monoprefixUnity/us.exe -srcdir:$usCheckout/src/us -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:Boo.Lang.Useful.dll");
	
	# unityscript test suite
	my $UnityScriptTestsCSharpDLL = "$usCheckout/src/UnityScript.Tests.CSharp/bin/Debug/UnityScript.Tests.CSharp.dll";
	UnityXBuild("$usCheckout/src/UnityScript.Tests.CSharp/UnityScript.Tests.CSharp.csproj", "Debug");
	
	my $usBuildDir = "$usCheckout/build";
	mkdir($usBuildDir);
	
	my $UnityScriptTestsDLL = <$usBuildDir/UnityScript.Tests.dll>;
	UnityBooc("-out:$UnityScriptTestsDLL -srcdir:$usCheckout/src/UnityScript.Tests -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:$UnityScriptTestsCSharpDLL -r:Boo.Lang.Compiler.dll -r:Boo.Lang.Useful.dll");
	
	cp("$UnityScriptTestsCSharpDLL $usBuildDir/");
	cp("$monoprefixUnity/Boo.* $usBuildDir/");
	cp("$monoprefixUnity/UnityScript.* $usBuildDir/");
	cp("$monoprefixUnity/us.exe $usBuildDir/");
	
	#system(<$monoprefix/bin/nunit-console2>, "-noshadow", "-exclude=FailsOnMono", $UnityScriptTestsDLL) eq 0 or die("UnityScript test suite failed");
}
	
# TODO: If you don't refactor, then neither am I...
sub BuildUnityScriptFor45
{
	my $booCheckout = "external/boo";
	
	# TeamCity is handling this
	if (!$ENV{UNITY_THISISABUILDMACHINE}) {
		GitClone("git://github.com/Unity-Technologies/boo.git", $booCheckout, "unity-trunk");
	}
	XBuild("$booCheckout/src/booc/booc.csproj", "/t:Rebuild");
	
	cp("$booCheckout/ide-build/Boo.Lang*.dll $monoprefix45/");
	cp("$booCheckout/ide-build/booc.exe $monoprefix45/");
	cp("$monoprefixUnity/booc $monoprefix45/");
	cp("$monoprefixUnity/mono-env $monoprefix45/");
	Booc("-out:$monoprefix45/Boo.Lang.Extensions.dll -noconfig -nostdlib -srcdir:$booCheckout/src/Boo.Lang.Extensions -r:System.dll -r:System.Core.dll -r:mscorlib.dll -r:Boo.Lang.dll -r:Boo.Lang.Compiler.dll");
	Booc("-out:$monoprefix45/Boo.Lang.Useful.dll -srcdir:$booCheckout/src/Boo.Lang.Useful -r:Boo.Lang.Parser");
	Booc("-out:$monoprefix45/Boo.Lang.PatternMatching.dll -srcdir:$booCheckout/src/Boo.Lang.PatternMatching");
	
	my $usCheckout = "external/unityscript";
	if (!$ENV{UNITY_THISISABUILDMACHINE}) {
		GitClone("git://github.com/Unity-Technologies/unityscript.git", $usCheckout, "unity-trunk");
	}
	
	my $UnityScriptLangDLL = "$monoprefix45/UnityScript.Lang.dll";
	Booc("-out:$UnityScriptLangDLL -srcdir:$usCheckout/src/UnityScript.Lang");
	
	my $UnityScriptDLL = "$monoprefix45/UnityScript.dll";
	Booc("-out:$UnityScriptDLL -srcdir:$usCheckout/src/UnityScript -r:$UnityScriptLangDLL -r:Boo.Lang.Parser.dll -r:Boo.Lang.PatternMatching.dll");
	Booc("-out:$monoprefix45/us.exe -srcdir:$usCheckout/src/us -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:Boo.Lang.Useful.dll");
	
	# unityscript test suite
	my $UnityScriptTestsCSharpDLL = "$usCheckout/src/UnityScript.Tests.CSharp/bin/Debug/UnityScript.Tests.CSharp.dll";
	XBuild("$usCheckout/src/UnityScript.Tests.CSharp/UnityScript.Tests.CSharp.csproj", "/t:Rebuild");
	
	my $usBuildDir = "$usCheckout/build";
	mkdir($usBuildDir);
	
	my $UnityScriptTestsDLL = <$usBuildDir/UnityScript.Tests.dll>;
	Booc("-out:$UnityScriptTestsDLL -srcdir:$usCheckout/src/UnityScript.Tests -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:$UnityScriptTestsCSharpDLL -r:Boo.Lang.Compiler.dll -r:Boo.Lang.Useful.dll");
	
	cp("$UnityScriptTestsCSharpDLL $usBuildDir/");
	cp("$monoprefix45/Boo.* $usBuildDir/");
	cp("$monoprefix45/UnityScript.* $usBuildDir/");
	cp("$monoprefix45/us.exe $usBuildDir/");
}
	
sub UnityXBuild
{
	my $projectFile = shift;
	
	my $optionalConfiguration = shift; 
	my $configuration = defined($optionalConfiguration) ? $optionalConfiguration : "Release";
	
	my $target = "Rebuild";
	my $commandLine = "$monoprefix/bin/xbuild $projectFile /p:CscToolExe=smcs /p:CscToolPath=$monoprefixUnity /p:MonoTouch=True /t:$target /p:Configuration=$configuration /p:AssemblySearchPaths=$monoprefixUnity";
	
	system($commandLine) eq 0 or die("Failed to xbuild '$projectFile' for unity");
}

sub AddRequiredExecutePermissionsToUnity
{
	for my $profile (@_) {
		my @scripts = ("smcs", "booc", "us");
		for my $script (@scripts) { 
			chmod(0777, $profile. "/$script");
		}
	}
}

sub RunCSProj
{
	my $csprojnoext = shift;

    XBuild("$csprojnoext.csproj");
        
	my $dir = dirname($csprojnoext);
	my $basename = basename($csprojnoext);
	my $exe = "$dir/bin/Debug/$basename.exe";

	my @args = ();
	push(@args,"$monoprefix/bin/cli");
	push(@args,$exe);

	print("Starting $exer\n");
	my $ret = system(@args);
	print("$exe finished. exitcode: $ret\n");
	$ret eq 0 or die("Failed running $exe");
}

#Overlaying files
CopyIgnoringHiddenFiles("$buildscriptsdir/add_to_build_results/", "$root/builds/");

if($ENV{UNITY_THISISABUILDMACHINE})
{
	my %checkouts = (
		'mono-classlibs' => 'BUILD_VCS_NUMBER_mono_unity_2_10_2',
		'boo' => 'BUILD_VCS_NUMBER_Boo',
		'unityscript' => 'BUILD_VCS_NUMBER_UnityScript',
		'cecil' => 'BUILD_VCS_NUMBER_Cecil'
	);

	system("echo '' > $root/builds/versions.txt");
	for my $key (keys %checkouts) {
		system("echo \"$key = $ENV{$checkouts{$key}}\" >> $root/builds/versions.txt");
	}
}

# now remove nunit
system("rm -rf $monodistro/lib/mono/2.0/nunit*");
system("rm -rf $monodistro/lib/mono/gac/nunit*");

#zip up the results for teamcity
chdir("$root/builds");
system("tar -hpczf ../ZippedClasslibs.tar.gz *") && die("Failed to zip up classlibs for teamcity");	
