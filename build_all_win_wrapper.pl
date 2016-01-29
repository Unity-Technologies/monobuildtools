use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;
use Config;

print ">>> My Path: $ENV{PATH}\n\n";

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);
my $buildScriptsRoot = "$monoroot/external/buildscripts";
print ">>> Mono checkout found in $monoroot\n\n";

my $cygwinRootWindows = "";
my $monoInstallLinux = "";

my @thisScriptArgs = ();
my @passAlongArgs = ();
foreach my $arg (@ARGV)
{
	print("$arg\n");
	push @backupArgs, $arg;
	
	if ($arg =~ /^--cygwin=/)
	{
		push @thisScriptArgs, $arg;
	}
	elsif ($arg =~ /^--existingmono=/)
	{
		push @thisScriptArgs, $arg;
	}
	else
	{
		push @passAlongArgs, $arg;
	}
}

print(">>> This Script Args = @thisScriptArgs\n");
print(">>> Pass Along Args = @passAlongArgs\n");

@ARGV = @thisScriptArgs;
GetOptions(
	'cygwin=s'=>\$cygwinRootWindows,
	'existingmono=s'=>\$monoInstallLinux,
);

# Attempt to find common default cygwin install locations
if ($cygwinRootWindows eq "")
{
	print(">>> No cygwin install specified.  Looking for defaults...\n");
	
	if (-d "C:\\Cygwin64")
	{
		$cygwinRootWindows = "C:\\Cygwin64";
		print(">>> Found Cygwin at : $cygwinRootWindows\n");
	}
	elsif (-d "C:\\Cygwin")
	{
		$cygwinRootWindows = "C:\\Cygwin";
		print(">>> Found Cygwin at : $cygwinRootWindows\n");
	}
	else
	{
		die("\nCould not fined Cygwin.  Define path using --cygwin=<path>\n")
	}
}
else
{
	print(">>> Cygwin Path = $cygwinRootWindows\n");
}

if ($monoInstallLinux eq "")
{
	if (-d "C:\\Program Files (x86)\\Mono")
	{
		# Pass over the cygwin format since I already have it escaped correctly to survive
		# crossing over the shell
		$monoInstallLinux = "/cygdrive/c/Program\\ Files\\ \\(x86\\)/Mono";
		print(">>> Found Mono at : $monoInstallLinux\n");
	}
	else
	{
		die("\n--existingmono=<path> is required and should be in the cygwin path format\n");
	}
}
else
{
	$monoInstallLinux =~ s/\\/\//g;
	print(">>> Linux Mono Path = $monoInstallLinux\n");
}

push @passAlongArgs, "--existingmono=$monoInstallLinux";

my $windowsPerl = $Config{perlpath};
print ">>> Perl Exe = $windowsPerl\n";
push @passAlongArgs, "--winperl=$windowsPerl";
push @passAlongArgs, "--winmonoroot=$monoroot";

print ">>> Calling $cygwinRootWindows\\bin\\sh.exe with @passAlongArgs";
system("$cygwinRootWindows\\bin\\sh.exe", "$monoroot/external/buildscripts/build_all_win.sh", @passAlongArgs) eq 0 or die("failed building mono");