#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
#
# Copyright (C) 2006-2009 Nexenta Systems, Inc.
# All rights reserved.
#

package nmc_iozone_benchmark;

use Cwd;
use NZA::Common;
use NMC::Const;
use NMC::Util;
use NMC::Term::Clui;
use strict;
use warnings;

##############################  variables  ####################################

my $benchmark_name = 'iozone-benchmark';

my %benchmark_words =
(
	_enter => \&volume_benchmark,
	_usage => \&volume_benchmark_usage,
);

my $_benchmark_interrupted;


############################## Plugin Hooks ####################################

sub construct {
	my $all_builtin_word_trees = shift;

	my $setup_words = $all_builtin_word_trees->{setup};

	$setup_words->{$NMC::BENCHMARK}{$NMC::run_now}{$benchmark_name} = \%benchmark_words;
	$setup_words->{$NMC::VOLUME}{_unknown}{$NMC::BENCHMARK}{$NMC::run_now}{$benchmark_name} = \%benchmark_words;
}

############################## Setup Command ####################################

sub volume_benchmark_usage
{
	my ($cmdline, $prompt, @path) = @_;
	print_out <<EOF;
$cmdline
Usage: [-p numprocs] [-b blocksize] [-s filesize] [-q]

   -p <numprocs>     Number of process to run. Default is 2.
   -b <blocksize>    Block size to use. Default is 32k
   -s <filesize>     Max file size to use in MB. Default is automatic
   -q	             Quick mode. Warning: filesystem cache might
                     affect (and distort) results.

See also: 'dtrace'
See also: 'show performance'

See also: 'show volume iostat'
See also: 'show volume <name> iostat'
See also: 'show lun iostat'

See also: 'show auto-sync <name> stats'
See also: 'show auto-tier <name> stats'

See also: 'run benchmark iperf-benchmark'
See also: 'run benchmark bonnie-benchmark'

See also: 'help iostat'
See also: 'help dtrace'

EOF
}

sub _benchmark_begin
{
	my $scratch_dir = shift;
	my @lines = ();
	# NMS_CALLER as far as libzfs is concerned
	$ENV{$NZA::LIBZFS_ENV_NMS_CALLER} = 1;
	sysexec("zfs destroy $scratch_dir");
	if (sysexec("zfs create  $scratch_dir", \@lines) != 0) {
		print_error(@lines, "\n");
		return 0;
	}
	@lines = ();
	if (sysexec("chown admin $scratch_dir", \@lines) != 0) {
		print_error(@lines, "\n");
		return 0;
	}
	return 1;
}

sub _benchmark_end
{
	my $scratch_dir = shift;
	sysexec("zfs destroy $scratch_dir");
	delete $ENV{$NZA::LIBZFS_ENV_NMS_CALLER} if (exists $ENV{$NZA::LIBZFS_ENV_NMS_CALLER});
}

sub volume_benchmark
{
	my ($h, @path) = @_;
	my ($vol) = NMC::Util::names_to_values_from_path(\@path, $NMC::VOLUME);

	my ($numprocs, $quick, $block, $filesize) = NMC::Util::get_optional('p:qb:s:', \@path);
	$numprocs = 2 if (!defined $numprocs);

	$block = 32 if (!defined $block);
	$block = 32 if (!$block || $block !~ /^\d+$/);

	if (defined $vol && $vol eq $NZA::SYSPOOL) {
		print_error("Cannot use volume '$vol' for benchmarking: not supported yet\n");
		return 0;
	}
	
	my $volumes = &NZA::volume->get_names('');
	if (scalar @$volumes == 0) {
		print_error("No volumes in the system - cannot nothing to benchmark\n");
		return 0;
	}

	if (!defined $vol && scalar @$volumes == 1) {
		$vol = $volumes->[0];
		print_out("Volume '$vol' is the only available volume, starting benchmark...\n");
		sleep 1;
	}
	
	my $prompt = "Please select a volume to benchmark for performance";
	return 0 if (!NMC::Util::input_field("Select volume to run Iozone file I/O benchmark",
					   0,
					   $prompt,
					   \$vol,
					   "on-empty" => $NMC::warn_no_changes,
					   cmdopt => 'v:',
					   'choose-from' => $volumes));

	return 0 if (NMC::Util::scrub_in_progress_bail_out($vol, 'cannot run I/O benchmark: '));

	if (defined $filesize && $filesize !~ /^\d+$/) {
		print_error("File size needs to be an integer in MB. Exiting\n");
		return 0;
	}

	my $size;
	if (defined $filesize) {
		$size = $filesize;
	} else {
		eval {
			my $vmstat = &NZA::appliance->get_memstat();
			my $ram_total_mb = $vmstat->{ram_total};
			my $needed_mb = $ram_total_mb * 2;

			my $vol_avail = &NZA::volume->get_child_prop($vol, 'available');
			my $vol_avail_mb = NZA::Common::to_bytes($vol_avail);
			$vol_avail_mb = int($vol_avail_mb / 1024 / 1024);

			if ($quick) {
				if ($needed_mb > $vol_avail_mb && 0) {
					die "Volume '$vol' does not have enough free space to run '$benchmark_name'. Needed: approximately ${needed_mb}MB. Available: ${vol_avail_mb}MB.";
				}
				
				$size = int($ram_total_mb / 2);
			}
			else {
				my $needed_mb_extra = $needed_mb * 4;
				if ($needed_mb_extra > $vol_avail_mb) {
					die "Volume '$vol' does not have enough free space to run '$benchmark_name'. Needed: approximately ${needed_mb_extra}MB. Available: ${vol_avail_mb}MB.";
				}

				$size = $needed_mb;
			}

		}; if (nms_catch($@)) {
			nms_print_error($@);
			return 0;
		}
	}

	my $mode = $quick ? "quick" : "optimal";
	print_out("$vol: running $mode mode benchmark\n");
	print_out("$vol: generating ${size}MB files, using $block blocks\n");

	# 
	# Set output autoflush on
	# 
	my $oldfh = select(STDOUT); my $fl = $|; $| = 1; select($oldfh);

	my $scratch_dir = "$vol/.nmc-iozone-benchmark";
	goto _exit_bmed if (! _benchmark_begin($scratch_dir));

	my $curdir = getcwd();
	chdir "$NZA::VOLROOT/$vol/.nmc-iozone-benchmark";
	# ignore error - try to count what we have...
	system("iozone -ec -r $block -s ${size}m -l $numprocs -i 0 -i 1 -i 8");

	if (! $fl) {
		$oldfh = select(STDOUT); $| = $fl; select($oldfh);
	}

_exit_bmed:
	chdir $curdir;
	_benchmark_end($scratch_dir);
}

1;
