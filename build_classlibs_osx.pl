use lib ('.', 'perl_lib', 'external/buildscripts/perl_lib');
use Cwd ;
use Cwd 'abs_path';
use File::Path;
use File::Copy::Recursive qw(dircopy);
use Getopt::Long;
use File::Basename;
use Tools qw(GitClone);
use strict;

system("source","~/.profile");
print "My Path: $ENV{PATH}\n";

my $root = getcwd();

my $monoroot = $root;
my $monodistro = "$root/builds/monodistribution";
my $lib = "$monodistro/lib";
my $libmono = "$lib/mono";
my $monoprefix = "$root/tmp/monoprefix";
my $buildscriptsdir = "$root/external/buildscripts";
my $unityPath = "$root/../../unity/build";
my $xcodePath = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform';

my $monoprefix45 = "$monoprefix/lib/mono/4.5";
my $monodistroLibMono = "$monodistro/lib/mono";
my $monodistro45 = "$monodistroLibMono/4.5";
my $dependencyBranchToUse = "unity3.0";
my $buildMachine = $ENV{UNITY_THISISABUILDMACHINE};

if ($buildMachine) {
	print "rmtree-ing $root/builds because we're on a buildserver, and want to make sure we don't include old artifacts\n";
	rmtree("$root/builds");
} else {
	print "not rmtree-ing $root/builds, as we're not on a buildmachine\n";
}

my $skipbuild=0;
my $cleanbuild=1;
my $jobs=8;
my $sdk='10.6';

GetOptions(
   'skipbuild=i'=>\$skipbuild,
   'cleanbuild=i'=>\$cleanbuild,
   'jobs=i'=>\$jobs,
   'sdk=s'=>\$sdk,
) or die ("illegal cmdline options");



if (-d $libmono)
{
	rmtree($libmono);
} 

if (not $skipbuild)
{
	my $osxflags = '';
	my $target = '';
	my $host = '';
	my $build = '';
	my $mcs = '';

	if($^O eq "linux")
	{
		$ENV{CFLAGS} = $ENV{CXXFLAGS} = $ENV{LDFLAGS} = "-m32";
		$target = "--target=i686-pc-linux-gnu";
		$host = "--host=i686-pc-linux-gnu";
		$build = "--build=i686-pc-linux-gnu";
	}
	elsif($^O eq 'darwin')
	{
		my $sdkversion = $sdk;
		my $sdkPath = "$xcodePath/Developer/SDKs/MacOSX$sdkversion.sdk";
		my $libtoolize = $ENV{'LIBTOOLIZE'};
		my $libtool = $ENV{'LIBTOOL'};

		if ($buildMachine)
		{
			# Set up mono for bootstrapping
			$mcs = 'EXTERNAL_MCS=/Library/Frameworks/Mono.framework/Versions/2.10.2/bin/mcs';
			# Set up clang toolchain
			$sdkPath = "$unityPath/External/MacBuildEnvironment/builds/MacOSX$sdkversion.sdk";
			if (! -d $sdkPath)
			{
				print("Unzipping mac build toolchain\n");
				system("cd $unityPath; ./jam EditorZips; cd $root");
			}
			$ENV{'CC'} = "$sdkPath/../usr/bin/clang";
			$ENV{'CXX'} = "$sdkPath/../usr/bin/clang++";
			$ENV{'CFLAGS'} = $ENV{MACSDKOPTIONS} = "-D_XOPEN_SOURCE -I$unityPath/External/MacBuildEnvironment/builds/usr/include -mmacosx-version-min=$sdkversion -isysroot $sdkPath";
			$libtoolize = `which glibtoolize`;
			chomp($libtoolize);
			if(!-e $libtoolize)
			{
				$libtoolize = `which libtoolize`;
				chomp($libtoolize);
			}
		}
		else
		{
			$ENV{MACSDKOPTIONS} = "-D_XOPEN_SOURCE -mmacosx-version-min=$sdkversion -isysroot $sdkPath";
		}

		if(!-e $libtoolize)
		{
			$libtoolize = 'libtoolize';
		}
		if(!-e $libtool)
		{
			$libtool = $libtoolize;
			$libtool =~ s/ize$//;
		}
		print("Libtool: using $libtoolize and $libtool\n");
		$ENV{'LIBTOOLIZE'} = $libtoolize;
		$ENV{'LIBTOOL'} = $libtool;
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
		system('./autogen.sh',"--prefix=$monoprefix",$host,'--with-monotouch=no', '--with-glib=embedded','--with-mcs-docs=no', '--disable-nls', $osxflags) eq 0 or die ('failing autogenning mono');
		print("calling make clean in mono\n");
		system("make","clean") eq 0 or die ("failed to make clean");
	}
	system("make $mcs -j$jobs") eq 0 or die ('Failed running make');
	system("make install") eq 0 or die ("Failed running make install");

	CopyIgnoringHiddenFiles("$buildscriptsdir/add_to_build_results/monodistribution/", "$monoprefix/");
	BuildUnityScriptFor45();
}
chdir ($root);

$File::Copy::Recursive::CopyLink = 0;  #make sure we copy files as files and not as symlinks, as TC unfortunately doesn't pick up symlinks.

my @profiles = ("2.0","3.5","4.0","4.5");
system("mkdir -p $libmono");
for my $profile (@profiles)
{
	system("cp -r $monoprefix/lib/mono/$profile $libmono");
	if ($buildMachine)
	{
		system("rm -f $libmono/$profile/*.mdb");
	}
}
system("cp -r $monoprefix/bin $monodistro/") eq 0 or die ("failed copying bin folder");
system("cp -r $monoprefix/etc $monodistro/") eq 0 or die("failed copying etc folder");
system("cp -r $monoprefix/lib/mono/gac $monodistro/lib/mono") eq 0 or die("failed copying gac");
system("cp -r $monoprefix/lib/mono/xbuild-frameworks $monodistro/lib/mono") eq 0 or die("failed copying xbuild-frameworks");

sub CopyIgnoringHiddenFiles
{
	my $sourceDir = shift;
	my $targetDir = shift;
	system("cp -R $sourceDir $targetDir");
}

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

sub Booc
{
	my $commandLine = shift;
	
	system("$monoprefix45/booc -debug- $commandLine") eq 0 or die("booc failed to execute: $monoprefix45/booc -debug- $commandLine");
}

sub BuildUnityScriptFor45
{
	my $booCheckout = "external/boo";
	print("Using mono prefix $monoprefix45\n");
	
	# Build host is handling this
	if (!$buildMachine) {
		GitClone("git://github.com/Unity-Technologies/boo.git", $booCheckout, "unity-trunk");
	}
	XBuild("$booCheckout/src/booc/booc.csproj", "/t:Rebuild");
	
	cp("$booCheckout/ide-build/Boo.Lang*.dll $monoprefix45/");
	cp("$booCheckout/ide-build/booc.exe $monoprefix45/");
	Booc("-out:$monoprefix45/Boo.Lang.Extensions.dll -noconfig -nostdlib -srcdir:$booCheckout/src/Boo.Lang.Extensions -r:System.dll -r:System.Core.dll -r:mscorlib.dll -r:Boo.Lang.dll -r:Boo.Lang.Compiler.dll");
	Booc("-out:$monoprefix45/Boo.Lang.Useful.dll -srcdir:$booCheckout/src/Boo.Lang.Useful -r:Boo.Lang.Parser");
	Booc("-out:$monoprefix45/Boo.Lang.PatternMatching.dll -srcdir:$booCheckout/src/Boo.Lang.PatternMatching");
	
	my $usCheckout = "external/unityscript";
	if (!$buildMachine) {
		GitClone("git://github.com/Unity-Technologies/unityscript.git", $usCheckout, "unity-trunk");
	}
	
	my $UnityScriptLangDLL = "$monoprefix45/UnityScript.Lang.dll";
	Booc("-out:$UnityScriptLangDLL -srcdir:$usCheckout/src/UnityScript.Lang");
	
	my $UnityScriptDLL = "$monoprefix45/UnityScript.dll";
	Booc("-out:$UnityScriptDLL -srcdir:$usCheckout/src/UnityScript -r:$UnityScriptLangDLL -r:Boo.Lang.Parser.dll -r:Boo.Lang.PatternMatching.dll");
	Booc("-out:$monoprefix45/us.exe -srcdir:$usCheckout/src/us -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:Boo.Lang.Useful.dll");
	
	# # unityscript test suite
	# my $UnityScriptTestsCSharpDLL = "$usCheckout/src/UnityScript.Tests.CSharp/bin/Debug/UnityScript.Tests.CSharp.dll";
	# XBuild("$usCheckout/src/UnityScript.Tests.CSharp/UnityScript.Tests.CSharp.csproj", "/t:Rebuild");
	
	my $usBuildDir = "$usCheckout/build";
	mkdir($usBuildDir);
	
	# my $UnityScriptTestsDLL = <$usBuildDir/UnityScript.Tests.dll>;
	# Booc("-out:$UnityScriptTestsDLL -srcdir:$usCheckout/src/UnityScript.Tests -r:$UnityScriptLangDLL -r:$UnityScriptDLL -r:$UnityScriptTestsCSharpDLL -r:Boo.Lang.Compiler.dll -r:Boo.Lang.Useful.dll");
	
	# cp("$UnityScriptTestsCSharpDLL $usBuildDir/");
	cp("$monoprefix45/Boo.* $usBuildDir/");
	cp("$monoprefix45/UnityScript.* $usBuildDir/");
	cp("$monoprefix45/us.exe $usBuildDir/");
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

	print("Starting $exe\n");
	my $ret = system(@args);
	print("$exe finished. exitcode: $ret\n");
	$ret eq 0 or die("Failed running $exe");
}

#Overlaying files
CopyIgnoringHiddenFiles("$buildscriptsdir/add_to_build_results/", "$root/builds/");

if($buildMachine)
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
