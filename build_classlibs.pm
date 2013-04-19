use strict;
use warnings;

use File::Path;
use File::Copy::Recursive qw(dircopy);
use Getopt::Long;
use File::Basename;

my $dependencyBranchToUse = "unity3.0";

my $booCheckout = "external/boo";
my $cecilCheckout = "mcs/class/Mono.Cecil";
my $usCheckout = "external/unityscript";


sub CopyIgnoringHiddenFiles
{
	my $sourceDir = shift;
	my $targetDir = shift;

	#really need to find a better way to copy a dir, ignoring .svn's than rsync.
	system("rsync -a -v --exclude='.*' $sourceDir $targetDir") eq 0 or die("failed to rsync $sourceDir to $targetDir");
}

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
	cp("$sourceFolder/*.exe $targetFolder/");
	cp("$sourceFolder/*.mdb $targetFolder/");
}

sub CopyProfileAssemblies
{
	my $monoroot = shift;
	my $buildtarget = shift;
	my $sourceName = shift;
	my $targetName = shift;
	CopyProfileAssembliesToPrefix ($monoroot, $buildtarget, $sourceName, $targetName)
}

sub CopyProfileAssembliesToPrefix
{
	my $monoroot = shift;
	my $buildtarget = shift;
	my $sourceName = shift;
	my $targetName = shift;

	my $targetDir = "$buildtarget/lib/mono/$targetName";
	CopyAssemblies ("$monoroot/mcs/class/lib/$sourceName", $targetDir);
}

my $securityAttributesPath = "tuning/SecurityAttributes";

sub InjectSecurityAttributesOnProfile
{
	my $prefix = shift;
	my $injectSecurityAttributes = shift;

	if ($injectSecurityAttributes)
	{
		my $profile = shift;
		RunXBuildTargetOnProfile ($prefix, "Install", $profile);
	}
}

sub XBuild
{
	my $prefix = shift;
	system("$prefix/bin/xbuild", @_) eq 0 or die("Failed to xbuild @_");
}

sub RunXBuildTargetOnProfile
{
	my $prefix = shift;
	my $target = shift;
	my $profile = shift;

	XBuild ($prefix, "$securityAttributesPath/SecurityAttributes.proj", "/p:Profile=$profile", "/p:ProfilePrefix=$prefix", "/t:$target") eq 0 or die("failed to run target '$target' on $profile");
}


sub UnityBooc
{
	my $prefixUnity = shift;
	my $commandLine = shift;

	system("$prefixUnity/booc -debug- $commandLine") eq 0 or die("booc failed to execute: $commandLine");
}

sub BuildUnityScriptForUnity
{
	my $prefix = shift;
	my $prefixUnity = shift;
	my $libmono = shift;
	my $libmonoUnity = shift;
	my $prefixUnityWeb = shift;
	my $libmonoUnityWeb = shift;


	# TeamCity is handling this
	if (!$ENV{UNITY_THISISABUILDMACHINE}) {
		GitClone("git://github.com/Unity-Technologies/boo.git", $booCheckout);
	}
	UnityXBuild ($prefix, $prefixUnity, "$booCheckout/src/booc/booc.csproj");

	cp ("$booCheckout/ide-build/Boo.Lang*.dll $prefixUnity/");
	cp ("$booCheckout/ide-build/booc.exe $prefixUnity/");
	UnityBooc ($prefixUnity, "-out:$prefixUnity/Boo.Lang.Extensions.dll -noconfig -nostdlib -srcdir:$booCheckout/src/Boo.Lang.Extensions -r:System.dll -r:System.Core.dll -r:mscorlib.dll -r:Boo.Lang.dll -r:Boo.Lang.Compiler.dll");
	UnityBooc ($prefixUnity, "-out:$prefixUnity/Boo.Lang.Useful.dll -srcdir:$booCheckout/src/Boo.Lang.Useful -r:Boo.Lang.Parser");
	UnityBooc ($prefixUnity, "-out:$prefixUnity/Boo.Lang.PatternMatching.dll -srcdir:$booCheckout/src/Boo.Lang.PatternMatching");

	# micro profile version
	UnityXBuild ($prefix, $prefixUnity, "$booCheckout/src/Boo.Lang/Boo.Lang.csproj", "Micro-Release");
	cp ("$booCheckout/src/Boo.Lang/bin/Micro-Release/Boo.Lang.dll $libmono/micro/");

	if (!$ENV{UNITY_THISISABUILDMACHINE}) {
		GitClone ("git://github.com/Unity-Technologies/unityscript.git", $usCheckout);
	}

	my $UnityScriptLangDLL = "$prefixUnity/UnityScript.Lang.dll";
	UnityBooc ($prefixUnity, "-out:$UnityScriptLangDLL -srcdir:$usCheckout/src/UnityScript.Lang");

	my $UnityScriptDLL = "$prefixUnity/UnityScript.dll";
	UnityBooc ($prefixUnity, "-out:$UnityScriptDLL -srcdir:$usCheckout/src/UnityScript -r:$UnityScriptLangDLL -r:Boo.Lang.Parser.dll -r:Boo.Lang.PatternMatching.dll");
	UnityBooc ($prefixUnity, "-out:$prefixUnity/us.exe -srcdir:$usCheckout/src/us -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:Boo.Lang.Useful.dll");

	# unityscript test suite
	my $UnityScriptTestsCSharpDLL = "$usCheckout/src/UnityScript.Tests.CSharp/bin/Debug/UnityScript.Tests.CSharp.dll";
	UnityXBuild($prefix, $prefixUnity, "$usCheckout/src/UnityScript.Tests.CSharp/UnityScript.Tests.CSharp.csproj", "Debug");

	my $usBuildDir = "$usCheckout/build";
	mkdir($usBuildDir);

	my $UnityScriptTestsDLL = <$usBuildDir/UnityScript.Tests.dll>;
	UnityBooc ($prefixUnity, "-out:$UnityScriptTestsDLL -srcdir:$usCheckout/src/UnityScript.Tests -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:$UnityScriptTestsCSharpDLL -r:Boo.Lang.Compiler.dll -r:Boo.Lang.Useful.dll");

	cp ("$UnityScriptTestsCSharpDLL $usBuildDir/");
	cp ("$prefixUnity/Boo.* $usBuildDir/");
	cp ("$prefixUnity/UnityScript.* $usBuildDir/");
	cp ("$prefixUnity/us.exe $usBuildDir/");

#	$ENV{MONO_EXECUTABLE} = <$prefix/bin/cli>;
#	system(<$prefix/bin/nunit-console2>, "-noshadow", "-exclude=FailsOnMono", $UnityScriptTestsDLL) eq 0 or die("UnityScript test suite failed");
}

sub UnityXBuild
{
	my $prefix = shift;
	my $prefixUnity = shift;
	my $projectFile = shift;

	my $optionalConfiguration = shift;
	my $configuration = defined($optionalConfiguration) ? $optionalConfiguration : "Release";

	my $target = "Rebuild";
	my $commandLine = "$prefix/bin/xbuild $projectFile /p:CscToolExe=smcs /p:CscToolPath=$prefixUnity /p:MonoTouch=True /t:$target /p:Configuration=$configuration /p:AssemblySearchPaths=$prefixUnity";

	print ($commandLine."\n");
	system($commandLine) eq 0 or die("Failed to xbuild '$projectFile' for unity");
}

sub GitClone
{
	my $repo = shift;
	my $localFolder = shift;
	my $branch = shift;
	$branch = defined($branch)?$branch:"master";

	if (-d $localFolder) {
		return;
	}
	system("git clone --branch $branch $repo $localFolder") eq 0 or die("git clone $repo $localFolder failed!");
}

sub BuildCecilForUnity
{
	my $prefix = shift;
	my $prefixUnity = shift;
	my $useCecilLight = 0;


	if ($useCecilLight) {

		$cecilCheckout = "external/cecil";
		if (!$ENV{UNITY_THISISABUILDMACHINE}) {
			GitClone("http://github.com/Unity-Technologies/cecil", $cecilCheckout, $dependencyBranchToUse);
		}

	}

	UnityXBuild ($prefix, $prefixUnity, "$cecilCheckout/Mono.Cecil.csproj");
	cp ("$cecilCheckout/bin/Release/Mono.Cecil.dll $prefixUnity/");

}

sub AddRequiredExecutePermissionsToUnity
{
	my $prefixUnity = shift;

	my @scripts = ("smcs", "booc", "us");
	for my $script (@scripts) {
		chmod(0777, $prefixUnity . "/$script");
	}
}

sub RunCSProj
{
	my $prefix = shift;
	my $csprojnoext = shift;
	my $args = shift;

    XBuild ($prefix, "$csprojnoext.csproj");

	my $dir = dirname($csprojnoext);
	my $basename = basename($csprojnoext);
	my $exe = "$dir/bin/Debug/$basename.exe";

	my @args = ();
	push(@args,"$prefix/bin/cli");
	push(@args,$exe);
	push(@args,$args);

	print("Starting $exe @args\n");
	my $ret = system(@args);
	print("$exe finished. exitcode: $ret\n");
	$ret eq 0 or die("Failed running $exe");
}

sub RunLinker()
{
	my $prefix = shift;
	my $prefixUnity = shift;
	my $buildtarget = shift;
	RunCSProj ($prefix, "tuning/UnityProfileShaper/UnityProfileShaper", "--inputdir $prefixUnity --outputdir $buildtarget/tmp/unity_linkered");
}

sub RunSecurityInjection
{
	my $prefix = shift;
	my $prefixUnityWeb = shift;
	my $buildtarget = shift;
	RunCSProj ($prefix, "tuning/SecurityAttributes/DetectMethodPrivileges/DetectMethodPrivileges", "--inputdir $buildtarget/tmp/unity_linkered --outputdir $prefixUnityWeb");
}

sub CopyUnityScriptAndBooFromUnityProfileTo20
{
	my $distdir = shift;
	my $libmonoUnity = shift;

	my $twozeroprofile = "$distdir/lib/mono/2.0";
	system("cp $libmonoUnity/Boo* $twozeroprofile/") && die("failed copying");
	system("cp $libmonoUnity/boo* $twozeroprofile/") && die("failed copying");
	system("cp $libmonoUnity/us* $twozeroprofile/") && die("failed copying");
	system("cp $libmonoUnity/UnityScript* $twozeroprofile/") && die("failed copying");

}
