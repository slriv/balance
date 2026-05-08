use v5.38;
use Test::More;
use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);

my $script = "$Bin/../../../script/balance";
my $prefix = '/__balance_missing_mount_prefix__';

sub _shell_quote ($value) {
	$value =~ s/'/'\\''/g;
	return qq{'$value'};
}

my $output = qx{$^X -I$Bin/../../../lib $script 2>&1};
my $exit_code = $? >> 8;

isnt($exit_code, 0, 'script exits non-zero when no mounts are provided');
like($output, qr/balance starting: perl /, 'startup banner still shown');
like($output, qr/FATAL: At least two mounts must be provided via --mount=\/path\n/, 'clean fatal message is shown');
like($output, qr/--mount=\/path/, 'fatal message includes explicit mount guidance');
unlike($output, qr/main::__ANON__/, 'fatal output does not include Perl stack trace frames');
unlike($output, qr/called at /, 'fatal output does not include confess stack trace');

subtest 'script emits scan progress to stderr and stamped plan log' => sub {
	my $dir = tempdir(CLEANUP => 1);
	my $m1 = File::Spec->catdir($dir, 'media1');
	my $m2 = File::Spec->catdir($dir, 'media2');
	my $plan_file = File::Spec->catfile($dir, 'balance-plan.sh');
	my $log_file = File::Spec->catfile($dir, 'balance-plan.log');

	mkdir $m1 or die "mkdir $m1: $!";
	mkdir $m2 or die "mkdir $m2: $!";
	mkdir File::Spec->catdir($m1, 'Show A') or die "mkdir Show A: $!";
	mkdir File::Spec->catdir($m2, 'Show B') or die "mkdir Show B: $!";

	open my $fh1, '>', File::Spec->catfile($m1, 'Show A', 'Episode1.mkv') or die "write Episode1: $!";
	print {$fh1} 'example';
	close $fh1;

	open my $fh2, '>', File::Spec->catfile($m2, 'Show B', 'Episode1.mkv') or die "write Episode2: $!";
	print {$fh2} 'example';
	close $fh2;

	my $cmd = join ' ',
		map { _shell_quote($_) }
		($^X, "-I$Bin/../../../lib", $script,
		 "--mount=$m1", "--mount=$m2",
		 "--plan-file=$plan_file", "--log-file=$log_file");
	my $run_output = qx{$cmd 2>&1};
	my $run_exit_code = $? >> 8;

	is($run_exit_code, 0, 'script exits successfully for disposable mounts');
	like($run_output, qr/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Scanning 2 mount\(s\) for current usage\.\.\./, 'stderr includes overall scan progress');
	like($run_output, qr/\[scan 1\/2\].*measuring 1 show directory/, 'stderr includes per-mount scan progress');

	my @logs = glob(File::Spec->catfile($dir, 'balance-plan-*.log'));
	is(scalar @logs, 1, 'exactly one stamped plan log created');
	open my $log_fh, '<', $logs[0] or die "read $logs[0]: $!";
	local $/;
	my $log_content = <$log_fh>;
	close $log_fh;

	like($log_content, qr/=== PLAN started /, 'stamped plan log includes start marker');
	like($log_content, qr/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Scanning 2 mount\(s\) for current usage\.\.\./, 'stamped plan log includes overall scan progress');
	like($log_content, qr/\[scan 2\/2\].*complete \(1 shows, tv=/, 'stamped plan log includes per-mount completion progress');
};

subtest 'script can apply a previously saved plan file without replanning' => sub {
	my $dir = tempdir(CLEANUP => 1);
	my $bin_dir = File::Spec->catdir($dir, 'bin');
	my $src_mount = File::Spec->catdir($dir, 'media1');
	my $dst_mount = File::Spec->catdir($dir, 'media2');
	my $show_dir = File::Spec->catdir($src_mount, 'Show A');
	my $dest_dir = File::Spec->catdir($dst_mount, 'Show A');
	my $plan_file = File::Spec->catfile($dir, 'balance-plan.sh');
	my $manifest_file = File::Spec->catfile($dir, 'balance-apply-manifest.jsonl');
	my $log_file = File::Spec->catfile($dir, 'balance-apply.log');
	my $fake_rsync = File::Spec->catfile($bin_dir, 'rsync');

	mkdir $bin_dir or die "mkdir $bin_dir: $!";
	mkdir $src_mount or die "mkdir $src_mount: $!";
	mkdir $dst_mount or die "mkdir $dst_mount: $!";
	mkdir $show_dir or die "mkdir $show_dir: $!";

	open my $media_fh, '>', File::Spec->catfile($show_dir, 'Episode1.mkv') or die "write media: $!";
	print {$media_fh} 'example';
	close $media_fh;

	open my $rsync_fh, '>', $fake_rsync or die "write fake rsync: $!";
	print {$rsync_fh} "#!/usr/bin/env perl\nprint join(q{ }, \@ARGV), qq{\\n};\nexit 0;\n";
	close $rsync_fh;
	chmod 0755, $fake_rsync;

	open my $plan_fh, '>', $plan_file or die "write plan file: $!";
	print {$plan_fh} "#!/usr/bin/env bash\n";
	print {$plan_fh} "set -euo pipefail\n\n";
	print {$plan_fh} "# Show A (1M)\n";
	print {$plan_fh} "rsync -avP --remove-source-files ", _shell_quote("$show_dir/"), q{ }, _shell_quote($dest_dir), "\n";
	close $plan_fh;

	my $cmd = join ' ',
		"PATH=" . _shell_quote("$bin_dir:$ENV{PATH}"),
		map { _shell_quote($_) }
		($^X, "-I$Bin/../../../lib", $script,
		 "--input-plan-file=$plan_file",
		 '--apply',
		 "--manifest-file=$manifest_file",
		 "--log-file=$log_file");
	my $run_output = qx{$cmd 2>&1};
	my $run_exit_code = $? >> 8;

	is($run_exit_code, 0, 'saved plan apply exits successfully');
	like($run_output, qr/Loaded 1 move\(s\) from saved plan file:/, 'saved plan run reports the loaded plan file');
	unlike($run_output, qr/At least two mounts must be provided/, 'saved plan apply does not require mount flags');

	my @manifests = glob(File::Spec->catfile($dir, 'balance-apply-manifest-*.jsonl'));
	is(scalar @manifests, 1, 'saved plan apply writes one stamped manifest file');
	open my $manifest_fh, '<', $manifests[0] or die "read manifest: $!";
	my $record = decode_json(scalar <$manifest_fh>);
	close $manifest_fh;

	is($record->{mode}, 'apply', 'manifest records apply mode');
	is($record->{status}, 'applied', 'manifest records apply status');
	is($record->{from_path}, "$show_dir/", 'manifest records source path from saved plan');
	is($record->{to_path}, $dest_dir, 'manifest records destination path from saved plan');
};

done_testing();