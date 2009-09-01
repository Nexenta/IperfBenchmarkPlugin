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

package nmc_iperf_benchmark;

use Socket;
use NZA::Common;
use NMC::Const;
use NMC::Util;
use NMC::Term::Clui;
use strict;
use warnings;

##############################  variables  ####################################

my $benchmark_name = 'iperf-benchmark';

my %benchmark_words =
(
	_enter => \&iperf_benchmark,
	_usage => \&iperf_benchmark_usage,
);

my $_benchmark_interrupted;


############################## Plugin Hooks ####################################

sub construct {
	my $all_builtin_word_trees = shift;

	my $setup_words = $all_builtin_word_trees->{setup};

	$setup_words->{$NMC::BENCHMARK}{$NMC::run_now}{$benchmark_name} = \%benchmark_words;
}

############################## Setup Command ####################################

sub iperf_benchmark_usage
{
	my ($cmdline, $prompt, @path) = @_;
	print_out <<EOF;
$cmdline
Usage: [-s] 
       [-P numthreads] [-i interval] [-l length] [-w window] [-t time] [hostname]

   -s             run in server mode
   -P numthreads  number of parallel client threads to run   (default 3)
   -i interval    seconds between periodic bandwidth reports (default 3)
   -l length      length of buffer to read or write          (default 128KB)
   -w window      TCP window size (socket buffer size)       (default 256KB)
   -t time        total time in seconds to run the bencmark  (default 30)
   hostname       for the iperf client, you can optionally specify
                  hostname or IP address of the iperf server

Usage: [-s] [server-options] 
       [-c] [client-options]
       
   server-options    any number of valid iperf server command line option, 
	             as per iperf documentation
   client-options    any number of valid iperf client command line option, 
	             as per iperf documentation

			     
This plugin is based on a popular Iperf tool used to measure
network performance. The benchmark is easy to set up. It requires two
hosts, one - to run iperf in server mode, another - to connect to the 
iperf server and run as a client.

Use -s option to specify server mode. 

The easiest way to run this benchmark is to select a host for the server
and type 'run benchmark iperf-benchmark -s'. Next, go to the host that
will run iperf client and type 'run benchmark iperf-benchmark'.
You will be prompted to specify the server's hostname or IP address.

See more examples below.

To run this benchmark, you can either:

   a) use built-in defaults for the most basic parameters, or
   b) specify the most basic benchmark parameters, or
   c) specify any/all iperf command line option, as per iperf manual page.

To display iperf manual page, run:

${prompt}!iperf -h

Quoting Wikipedia Iperf article (http://en.wikipedia.org/wiki/Iperf):

   "Iperf is a commonly used network testing tool that can create
   TCP and UDP data streams and measure the throughput of a network
   that is carrying them. Iperf is a modern tool for network performance
   measurement written in C++.
   
   Iperf allows the user to set various parameters that can be used for
   testing a network, or alternately for optimizing or tuning a network.
   Iperf has a client and server functionality, and can measure 
   the throughput between the two ends, either unidirectonally or 
   bi-directionally. 

   It is open source software and runs on various platforms including
   linux, unix and windows. It is supported by the
   National Laboratory for Applied Network Research."


Examples:

  1) Let's say, there are two appliances: hostA and hostB. 
     On appliance hostA run:

     nmc\@hostA:/\$ run benchmark iperf-benchmark -s

     This will execute iperf in a server mode. On appliance hostB
     the iperf client connects to hostA and drives the traffic
     using default parameter settings:

     nmc\@hostB:/\$ run benchmark iperf-benchmark hostA

  2) Same as above, except that now we assign parameters such as:
     * number of parallel client threads = 5
     * seconds between periodic bandwidth reports = 10
     * length of buffer to read or write = 8KB
     * TCP window size = 64KB

     nmc\@hostA:/\$ run benchmark iperf-benchmark -s
     nmc\@hostB:/\$ run benchmark iperf-benchmark hostA -P 5 -i 10 -l 8k -w 64k

     Notice that all these parameters are specified on the client side
     only. There is no need to restart iperf server in order to change 
     window size, interval between bandwidth reports, etc.
     
  3) Same as #1, except that iperf server is not specified in the
     command line. Instead, NMC will prompt you to select the server
     interactively from a list of all ssh-bound appliances:

     nmc\@hostA:/\$ run benchmark iperf-benchmark -s
     nmc\@hostB:/\$ run benchmark iperf-benchmark 

  4) ********* Note: advanced usage only *********
     You can specify any number of valid iperf server and/or client 
     command line option, as per iperf documentation.
     Unlike the most basic command line options listed above,
     the rest command line options are not validated and do not have
     NMC provided defaults.
     Unlike the most basic command line options listed above,
     the rest command line options are passed to iperf AS IS. 

     Examples:
        
     4.1) Display iperf version:
          nmc\@hostA:/\$ run benchmark iperf-benchmark -v

     4.2) Run iperf server in single threaded UDP mode:
          nmc\@hostB:/\$ run benchmark iperf-benchmark -U
 
    To view iperf manual page, run '!iperf -h'


See also: 'dtrace'
See also: 'show performance'

See also: 'show auto-sync <name> stats'
See also: 'show auto-tier <name> stats'

See also: 'help dtrace'

See also: 'show network ssh-bindings'
See also: 'show network appliance'

See also: 'run benchmark bonnie-benchmark'

See also: 'setup usage'
See also: 'help'

EOF
}

sub iperf_benchmark
{
	my ($h, @path) = @_;
	# 
	# command line args, validated and defaulted
	# 
	my ($server, $numprocs, $interval, $blocksize, $windowsize, $totaltime,
	   # optional, not validated. client and server
	    $format1, $print_mss1, $output_file1, $server_port1, $use_udp1,
	    $bind_host1, $compat1, $set_mss1, $no_delay1, $use_ipv6,
	   # optional, not validated. server only
	    $server_singlethreaded_udp, $server_run_as_daemon,
	   # optional, not validated. client only
	    $client_bandwidth, $client_is_client_server_host, $client_dualtest, $client_number_tx_bytes, 
	    $client_tradeoff, $client_from_file, $client_from_stdin, $client_listening_port,
	    $client_ttl, $client_linuxonly,
	   # miscellaneous
	    $misc_reportexclude, $misc_reportstyle, $misc_version) =
		NMC::Util::get_optional('sP:i:l:w:t:f:mo:p:uB:CM:NVUDb:c:dn:rF:IL:T:Z:x:yv', \@path);

	my $client_cmd = '';
	my $server_cmd = '';
	
	# 
	# validate the most important command line args and provide defaults
	# 
	if ($numprocs && $numprocs !~ /^\d+$/) {
		print_error("Error: expected numeric value for number of threads (numthreads), got '$numprocs'\n");
		goto _see_use;
	}
	if ($interval && $interval !~ /^\d+$/) {
		print_error("Error: expected numeric value for interval between periodic bandwidth reports, got '$interval'\n");
		goto _see_use;
	}
	if ($totaltime && $totaltime !~ /^\d+$/) {
		print_error("Error: expected numeric value for total time to run the benchmark, got '$totaltime'\n");
		goto _see_use;
	}
	if ($blocksize) {
		if ($blocksize !~ /^\d+[kK][bB]?$/ && $blocksize !~ /^\d+[mM][bB]?$/) {
			print_error("Error: length of buffer to read or write ('$blocksize'): invalid format\n");
			goto _see_use;
		}
		$blocksize =~ s/[bB]$//;
	}
	if ($windowsize) { 
		if ($windowsize !~ /^\d+[kK][bB]?$/ && $windowsize !~ /^\d+[mM][bB]?$/) {
			print_error("Error: TCP window size ('$windowsize'): invalid format\n");
			goto _see_use;
		}
		$windowsize =~ s/[bB]$//;
	}

	# 
	# set defaults
	# 
	if ($numprocs) {
		$client_cmd .= " -P$numprocs";
	}
	else {
		$client_cmd .= " -P3";
	}

	if ($interval) {
		$client_cmd .= " -i$interval";
		$server_cmd .= " -i$interval";
	}
	else {
		$client_cmd .= ' -i3';
	}

	if ($blocksize) {
		$client_cmd .= " -l$blocksize";
		$server_cmd .= " -l$blocksize";
	}
	else {
		$client_cmd .= ' -l128k';
	}

	if ($windowsize) {
		$client_cmd .= " -w$windowsize";
		$server_cmd .= " -w$windowsize";
	}
	else {
		$client_cmd .= ' -w256k';
	}

	if ($totaltime) {
		$client_cmd .= " -t$totaltime";
		$server_cmd .= " -t$totaltime";
	}
	else {
		$client_cmd .= ' -t30';
	}

	# 
	# the rest command line args (not validated) - as per 'iperf --help'
	# 
	if ($format1) {
		$client_cmd .= " -f$format1";
		$server_cmd .= " -f$format1";
	}
	if ($print_mss1) {
		$client_cmd .= " -m";
		$server_cmd .= " -m";
	}
	if ($output_file1) {
		$client_cmd .= " -o$output_file1";
		$server_cmd .= " -o$output_file1";
	}
	if ($server_port1) {
		$client_cmd .= " -p$server_port1";
		$server_cmd .= " -p$server_port1";
	}
	if ($use_udp1) {
		$client_cmd .= " -u";
		$server_cmd .= " -u";
	}
	if ($bind_host1) {
		$client_cmd .= " -B$bind_host1";
		$server_cmd .= " -B$bind_host1";
	}
	if ($compat1) {
		$client_cmd .= " -C";
		$server_cmd .= " -C";
	}
	if ($set_mss1) {
		$client_cmd .= " -M$set_mss1";
		$server_cmd .= " -M$set_mss1";
	}
	if ($no_delay1) {
		$client_cmd .= " -N";
		$server_cmd .= " -N";
	}
	if ($use_ipv6) {
		$client_cmd .= " -V";
		$server_cmd .= " -V";
	}
	
	# server only
	if ($server_singlethreaded_udp) {
		$server_cmd .= " -U";
	}
	if ($server_run_as_daemon) {
		$server_cmd .= " -D";
	}
	
	# client only
	if ($client_bandwidth) {
		$client_cmd .= " -b$client_bandwidth";
	}
	if ($client_dualtest) {
		$client_cmd .= " -d";
	}
	if ($client_number_tx_bytes) {
		$client_cmd .= " -n$client_number_tx_bytes";
	}
	if ($client_tradeoff) {
		$client_cmd .= " -r";
	}
	if ($client_from_file) {
		$client_cmd .= " -F$client_from_file";
	}
	if ($client_from_stdin) {
		$client_cmd .= " -I";
	}
	if ($client_listening_port) {
		$client_cmd .= " -L$client_listening_port";
	}
	if ($client_ttl) {
		$client_cmd .= " -T$client_ttl";
	}

	# misc 
	if ($misc_reportexclude) {
		$client_cmd .= " -x$misc_reportexclude";
		$server_cmd .= " -x$misc_reportexclude";
	}
	if ($misc_reportstyle) {
		$client_cmd .= " -y";
		$server_cmd .= " -y";
	}
	if ($misc_version) {
		$client_cmd .= " -v";
		$server_cmd .= " -v";
	}
	
	# 
	# do it
	# 
	if ($server) {
		if (system("iperf -s $server_cmd") != 0) {
			goto _see_use;
		}
	}
	else {
		# -c option
		my $rem_appliance = $client_is_client_server_host;
		# end of commandline 
		unless ($rem_appliance) {
			($rem_appliance) = NMC::Util::names_to_values_from_path(\@path, $benchmark_name);
		}
		# interactive.. 
		unless ($rem_appliance) {
			my @all_appls = ();
			my $all_appls_hash = &NZA::appliance->list_appliances();
			for my $a (keys %$all_appls_hash) {
				next if (hostname_is_local($a));
				push @all_appls, $a;
			}
			if (scalar @all_appls == 0) {
				print_out("No bound remote $NZA::PRODUCT appliances (iperf server) found - unable to start iperf client.\n");
				return 0;
			}

			#
			# remote appliance dialog
			#
			my $prompt = "Select remote appliance as an iperf server. Use 'show network appliance' to make sure that remote apliance is online";
			return 0 if (!NMC::Util::input_field('remote appliance',
							     0,
							     $prompt,
							     \$rem_appliance,
							     'choose-from' => \@all_appls));
			return 0 if (&choose_ret_ctrl_c());
		}
		elsif ($rem_appliance =~ /^-/) {
			print_error("Error: unknown command line option '$rem_appliance'\n");
			goto _see_use;
		}

		$client_cmd = "iperf -c $rem_appliance $client_cmd";
#print "client_cmd=$client_cmd\n";
		if (system($client_cmd) != 0) {
			goto _see_use;
		}
	}

	return 1;

_see_use:
	print_error("See usage (-h) for information on command line options, and examples\n");
	return 0;
}

1;
