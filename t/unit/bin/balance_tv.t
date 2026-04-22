use v5.38;
use Test::More;
use FindBin qw($Bin);

my $script = "$Bin/../../../bin/balance_tv.pl";
my $prefix = '/__balance_missing_mount_prefix__';

my $output = qx{$^X -I$Bin/../../../lib $script --mount-prefix=$prefix 2>&1};
my $exit_code = $? >> 8;

isnt($exit_code, 0, 'script exits non-zero when no mounts are discovered');
like($output, qr/balance_tv starting: perl /, 'startup banner still shown');
like($output, qr/FATAL: No mounts discovered for prefix '\Q$prefix\E'\./, 'clean fatal message is shown');
like($output, qr/--mount=\/path/, 'fatal message includes explicit mount guidance');
unlike($output, qr/main::__ANON__/, 'fatal output does not include Perl stack trace frames');
unlike($output, qr/called at /, 'fatal output does not include confess stack trace');

done_testing();