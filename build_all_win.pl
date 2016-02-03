use Cwd;
use Cwd 'abs_path';
use Getopt::Long;
use File::Basename;
use File::Path;

my $currentdir = getcwd();

my $monoroot = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
my $monoroot = abs_path($monoroot);
my $buildscriptsdir = "$monoroot/external/buildscripts";

my @passAlongArgs = ();
foreach my $arg (@ARGV)
{
	# Filter out --clean if someone uses it.  We have to clean since we are doing two builds
	if (not $arg =~ /^--clean=/)
	{
		push @passAlongArgs, $arg;
	}
}

print(">>> Building i686\n");
system("perl", "$buildscriptsdir/build_win_wrapper.pl", "--arch32=1", "--clean=1", "--classlibtests=0", @passAlongArgs) eq 0 or die ('failing building win32');

print(">>> Building x86_64\n");
system("perl", "$buildscriptsdir/build_win_wrapper.pl", "--clean=1", "--classlibtests=0", @passAlongArgs) eq 0 or die ('failing building x64');