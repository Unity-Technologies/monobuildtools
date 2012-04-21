use lib ('.', "perl_lib");
use Cwd ;
use Cwd 'abs_path';
use File::Path;
use File::Copy::Recursive qw(dircopy);
use Getopt::Long;
use File::Basename;

system("source","~/.profile");
print "My Path: $ENV{PATH}\n";

my $root = getcwd();

my $monoroot = abs_path($root."/../Mono");
my $monodistro = "$root/builds/monodistribution";
my $lib = "$monodistro/lib";
my $libmono = "$lib/mono";
my $monoprefix = "$root/tmp/monoprefix";

my $dependencyBranchToUse = "unity3.0";

if ($ENV{UNITY_THISISABUILDMACHINE}) {
	print "rmtree-ing $root/builds because we're on a buildserver, and want to make sure we don't include old artifacts\n";
	rmtree("$root/builds");
} else {
	print "not rmtree-ing $root/builds, as we're not on a buildmachine\n";
}

my $unity=1;
my $monotouch=0;
my $injectSecurityAttributes=0;

my $skipbuild=0;
my $cleanbuild=1;
GetOptions(
   "skipbuild=i"=>\$skipbuild,
   "cleanbuild=i"=>\$cleanbuild,
   "unity=i"=>\$unity,
   "injectsecurityattributes=i"=>\$injectSecurityAttributes,
   "monotouch=i"=>\$monotouch,
) or die ("illegal cmdline options");



if (-d $libmono)
{
	rmtree($libmono);
} 

if (not $skipbuild)
{
	my $target = "";

	if($^O eq "darwin")
	{
		#we need to manually set the compiler to gcc4, because the 10.4 sdk only shipped with the gcc4 headers
		#their setup is a bit broken as they dont autodetect this, but basically the gist is if you want to copmile
		#against the 10.4 sdk, you better use gcc4, otherwise things go boink.
		$ENV{CC} = "gcc-4.0";
		$ENV{CXX} = "gcc-4.0";
	}
	elsif($^O eq "linux")
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
		my $withMonotouch = $monotouch ? "yes" : "no";
		my $withUnity = $unity ? "yes" : "no";
		
		chdir("$monoroot") eq 1 or die("failed to chdir4");
		print(">>>Calling autoreconf in mono\n");
		system("autoreconf -i") eq 0 or die("failed to autoreconf mono");
		print(">>>Calling configure in mono\n");
		system("./configure","--prefix=$monoprefix",$host,"--with-monotouch=no", "--with-profile4=yes","--with-glib=embedded","--with-mcs-docs=no", "--disable-nls") eq 0 or die ("failing autogenning mono");
		print("calling make clean in mono\n");
		system("make","clean") eq 0 or die ("failed to make clean");
	}
	system("make") eq 0 or die ("Failed running make");
	system("make install") eq 0 or die ("Failed running make install");
}
chdir ($root);

$File::Copy::Recursive::CopyLink = 0;  #make sure we copy files as files and not as symlinks, as TC unfortunately doesn't pick up symlinks.

my @profiles = ("2.0","3.5","4.0","4.5");
for my $profile (@profiles)
{
	mkpath("$libmono/$profile");
	dircopy("$monoprefix/lib/mono/$profile","$libmono/$profile");
	system("rm $libmono/$profile/*.mdb");
	system("cp $monoprefix/lib/mono/gac/Mono.Cecil/*/Mono.Cecil.dll $libmono/$profile") eq 0 or die("failed to copy Mono.Cecil.dll");
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

CopyIgnoringHiddenFiles("add_to_build_results/monodistribution/", "$monoprefix/");

sub cp
{
	my $cmdLine = shift;
	system("cp $cmdLine") eq 0 or die("failed to copy '$cmdLine'");
}

sub CopyAssemblies
{
	my $sourceFolder = shift; 
	my $targetFolder = shift;
	
	print "Copying assemblies from '$sourceFolder' to '$targetFolder'...\n";
	
	mkpath($targetFolder);
	cp("$sourceFolder/*.dll $targetFolder/");
	#cp("$sourceFolder/*.exe $targetFolder/");
	#cp("$sourceFolder/*.mdb $targetFolder/");
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

my $securityAttributesPath = "tuning/SecurityAttributes";

sub InjectSecurityAttributesOnProfile
{
	if ($injectSecurityAttributes)
	{
		my $profile = shift;
		RunXBuildTargetOnProfile("Install", $profile);
	}
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

sub PackageSecurityAttributeInjectionTools
{
	if ($injectSecurityAttributes)
	{
		my $libSecAttrs = "$lib/SecurityAttributes";
		CopyAssemblies("$securityAttributesPath/bin", $libSecAttrs);
		cp("$root/mcs/tools/security/sn.exe $libSecAttrs/");
	}
}

my $monoprefixUnity = "$monoprefix/lib/mono/unity";
my $monoprefix20 = "$monoprefix/lib/mono/2.0";
my $monodistroLibMono = "$monodistro/lib/mono";
my $monodistro20 = "$monodistroLibMono/2.0";
my $monodistroUnity = "$monodistroLibMono/unity";
my $monoprefixUnityWeb = "$monoprefix/lib/mono/unity_web";
my $monodistroUnityWeb = "$monodistro/lib/mono/unity_web";

sub UnityBooc
{
	my $commandLine = shift;
	
	system("$monoprefixUnity/booc -debug- $commandLine") eq 0 or die("booc failed to execute: $commandLine");
}

sub Booc
{
	my $commandLine = shift;
	
	system("$monoprefix20/booc -debug- $commandLine") eq 0 or die("booc failed to execute: $commandLine");
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
	UnityBooc("-out:$monoprefixUnity/Boo.Lang.Extensions.dll -noconfig -nostdlib -srcdir:$booCheckout/src/Boo.Lang.Extensions -r:System.dll -r:System.Core.dll -r:mscorlib.dll -r:Boo.Lang.dll");
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
	
# TODO: Refactor with BuildUnityScriptForUnity
sub BuildUnityScriptFor20
{
	my $booCheckout = "external/boo";
	
	# TeamCity is handling this
	if (!$ENV{UNITY_THISISABUILDMACHINE}) {
		GitClone("git://github.com/Unity-Technologies/boo.git", $booCheckout, "unity-trunk");
	}
	XBuild("$booCheckout/src/booc/booc.csproj", "/t:Rebuild");
	
	cp("$booCheckout/ide-build/Boo.Lang*.dll $monoprefix20/");
	cp("$booCheckout/ide-build/booc.exe $monoprefix20/");
	cp("$monoprefixUnity/booc $monoprefix20/");
	cp("$monoprefixUnity/mono-env $monoprefix20/");
	Booc("-out:$monoprefix20/Boo.Lang.Extensions.dll -noconfig -nostdlib -srcdir:$booCheckout/src/Boo.Lang.Extensions -r:System.dll -r:System.Core.dll -r:mscorlib.dll -r:Boo.Lang.dll");
	Booc("-out:$monoprefix20/Boo.Lang.Useful.dll -srcdir:$booCheckout/src/Boo.Lang.Useful -r:Boo.Lang.Parser");
	Booc("-out:$monoprefix20/Boo.Lang.PatternMatching.dll -srcdir:$booCheckout/src/Boo.Lang.PatternMatching");
	
	my $usCheckout = "external/unityscript";
	if (!$ENV{UNITY_THISISABUILDMACHINE}) {
		GitClone("git://github.com/Unity-Technologies/unityscript.git", $usCheckout, "unity-trunk");
	}
	
	my $UnityScriptLangDLL = "$monoprefix20/UnityScript.Lang.dll";
	Booc("-out:$UnityScriptLangDLL -srcdir:$usCheckout/src/UnityScript.Lang");
	
	my $UnityScriptDLL = "$monoprefix20/UnityScript.dll";
	Booc("-out:$UnityScriptDLL -srcdir:$usCheckout/src/UnityScript -r:$UnityScriptLangDLL -r:Boo.Lang.Parser.dll -r:Boo.Lang.PatternMatching.dll");
	Booc("-out:$monoprefix20/us.exe -srcdir:$usCheckout/src/us -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:Boo.Lang.Useful.dll");
	
	# unityscript test suite
	my $UnityScriptTestsCSharpDLL = "$usCheckout/src/UnityScript.Tests.CSharp/bin/Debug/UnityScript.Tests.CSharp.dll";
	XBuild("$usCheckout/src/UnityScript.Tests.CSharp/UnityScript.Tests.CSharp.csproj", "/t:Rebuild");
	
	my $usBuildDir = "$usCheckout/build";
	mkdir($usBuildDir);
	
	my $UnityScriptTestsDLL = <$usBuildDir/UnityScript.Tests.dll>;
	Booc("-out:$UnityScriptTestsDLL -srcdir:$usCheckout/src/UnityScript.Tests -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:$UnityScriptTestsCSharpDLL -r:Boo.Lang.Compiler.dll -r:Boo.Lang.Useful.dll");
	
	cp("$UnityScriptTestsCSharpDLL $usBuildDir/");
	cp("$monoprefix20/Boo.* $usBuildDir/");
	cp("$monoprefix20/UnityScript.* $usBuildDir/");
	cp("$monoprefix20/us.exe $usBuildDir/");
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

sub GitClone
{
	my $repo = shift;
	my $localFolder = shift;
	my $branch = shift;
	$branch = defined($branch)?$branch:master;

	if (-d $localFolder) {
		return;
	}
	system("git clone --branch $branch $repo $localFolder") eq 0 or die("git clone $repo $localFolder failed!");
}

sub BuildCecilForUnity
{
	my $useCecilLight = 0;
	
	my $cecilCheckout = "mcs/class/Mono.Cecil";
	
	if ($useCecilLight) {
		
		$cecilCheckout = "external/cecil";
		if (!$ENV{UNITY_THISISABUILDMACHINE}) {
			GitClone("http://github.com/Unity-Technologies/cecil", $cecilCheckout, $dependencyBranchToUse);
		}
		
	}
	
	UnityXBuild("$cecilCheckout/Mono.Cecil.csproj");
	cp("$cecilCheckout/bin/Release/Mono.Cecil.dll $monoprefixUnity/");
		
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

sub RunLinker()
{
	RunCSProj("tuning/UnityProfileShaper/UnityProfileShaper");
}

sub RunSecurityInjection
{
	RunCSProj("tuning/SecurityAttributes/DetectMethodPrivileges/DetectMethodPrivileges");
}

sub CopyUnityScriptAndBooFromUnityProfileTo20
{
	my $twozeroprofile = "$monodistro/lib/mono/2.0";
	system("cp $monodistroUnity/Boo* $twozeroprofile/") && die("failed copying");
	system("cp $monodistroUnity/boo* $twozeroprofile/") && die("failed copying");
	system("cp $monodistroUnity/us* $twozeroprofile/") && die("failed copying");
	system("cp $monodistroUnity/UnityScript* $twozeroprofile/") && die("failed copying");

}


if ($unity)
{
	CopyProfileAssembliesToPrefix("unity", "unity", $monoprefix);
	
	AddRequiredExecutePermissionsToUnity($monoprefixUnity, $monoprefix20);
	BuildUnityScriptForUnity();
	BuildUnityScriptFor20();
	#BuildCecilForUnity();

	CopyAssemblies($monoprefix20,$monodistro20);
	CopyAssemblies($monoprefixUnity,$monodistroUnity);
	CopyAssemblies($monoprefixUnity,$monodistroUnityWeb); # Just copy unity profile to unity_web for now
	#now, we have a functioning, raw, unity profile in builds/monodistribution/lib/mono/unity
	#we're now going to transform that into the unity_web profile by running it trough the linker, and decorating it with security attributes.	

	# CopyUnityScriptAndBooFromUnityProfileTo20();

	#RunLinker();
	#RunSecurityInjection();
}

#Overlaying files
CopyIgnoringHiddenFiles("add_to_build_results/", "$root/builds/");
# now remove nunit
system("rm -rf $monoprefix/lib/mono/2.0/nunit*") eq 0 or die("failed to delete nunit from 2.0");
system("rm -rf $monoprefix/lib/mono/gac/nunit*") eq 0 or die("failed to delete nunit from gac");

#zip up the results for teamcity
chdir("$root/builds");
system("tar -hpczf ../ZippedClasslibs.tar.gz *") && die("Failed to zip up classlibs for teamcity");	
