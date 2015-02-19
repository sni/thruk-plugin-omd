package Thruk::Controller::omd;
use parent 'Catalyst::Controller';

use strict;
use warnings;

use Carp;
use JSON::XS;
use File::Slurp qw/read_file/;
use IPC::Open3 qw/open3/;

=head1 NAME

Thruk::Controller::omd - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

######################################
# add new menu item
Thruk::Utils::Menu::insert_item('Reports', {
                                    'href'  => '/thruk/cgi-bin/omd.cgi',
                                    'name'  => 'OMD Top',
                         });

my $top_dir    = defined $ENV{'OMD_ROOT'} ? $ENV{'OMD_ROOT'}.'/var/top' : 'var/top';
my $pluginname = 'omd';
eval { # not available in older thruk releases
    $pluginname = Thruk::Utils::get_plugin_name(__FILE__, __PACKAGE__);
};

######################################

=head2 omd_cgi

page: /thruk/cgi-bin/omd.cgi

=cut
sub omd_cgi : Path('/thruk/cgi-bin/omd.cgi') {
    my ( $self, $c ) = @_;
    return if defined $c->{'canceled'};
    $c->stash->{plugin} = $pluginname;
    return $c->detach('/omd/index');
}

##########################################################

=head2 index

=cut
sub index :Path :Args(0) :MyAction('AddSafeDefaults') {
    my ( $self, $c ) = @_;

    $c->stash->{title} = 'Top Statistics';
    $c->stash->{page}  = 'status';
    $c->stash->{hide_backends_chooser} = 1;

    our $hosts_list = undef;

    # check permissions
    unless( $c->check_user_roles( "authorized_for_configuration_information")
        and $c->check_user_roles( "authorized_for_system_commands")) {
        return $c->detach('/error/index/8');
    }

    my $action = $c->{'request'}->{'parameters'}->{'action'} || '';
    if($action eq 'top_details') {
        return $self->top_graph_details($c);
    }
    elsif($action eq 'top_data') {
        return $self->top_graph_data($c);
    }

    return $self->top_graph($c);
}

##########################################################

=head2 top_graph

    entry page with overview graph

=cut
sub top_graph {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'omd_top.tt';
    $c->stash->{'no_auto_reload'}      = 1;
    my $load_series = [
        { label => "load 1",  data =>  [] },
        { label => "load 5",  data =>  [] },
        { label => "load 15", data =>  [] },
    ];
    my @files = sort glob("$top_dir/*.log $top_dir/*.gz");
    my $num = 0;
    my $max = scalar @files;
    my @files_striped;
    if($max < 300) {
        @files_striped = @files;
    } else {
        for my $file (@files) {
            $num++;
            # use only the first, the last and every 30th file to speed up initial graph
            next if($num != 1 and $num != $max and $num%30 != 0);
            push @files_striped, $file;
        }
    }
    # zgrep to 30 files each to reduce the number of forks
    while( my @chunk = splice( @files_striped, 0, 30 ) ) {
        my $joined = join(' ', @chunk);
        my $out = `LC_ALL=C zgrep -H -F -m 1 'load average:' $joined 2>/dev/null`;
        if(my @matches = $out =~ m/(\d+)\.log.*?:\s*top\s+\-\s+(\d+):(\d+):(\d+)\s+up.*?average:\s*([\.\d]+),\s*([\.\d]+),\s*([\.\d]+)/gmxo) {
            while( my @m = splice( @matches, 0, 7 ) ) {
                my($time,$hour,$min,$sec,$l1,$l5,$l15) = (@m);
                $time = (($time - $time%60) + $sec)*1000;
                push @{$load_series->[0]->{'data'}}, [$time, $l1];
                push @{$load_series->[1]->{'data'}}, [$time, $l5];
                push @{$load_series->[2]->{'data'}}, [$time, $l15];
            }
        }
    }
    $c->stash->{load_series} = $load_series;
}

##########################################################

=head2 top_graph_details

    details graph for given timeperiod

=cut
sub top_graph_details {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'omd_top_details.tt';
    $c->stash->{'no_auto_reload'}      = 1;
    my @files = sort glob("$top_dir/*.log $top_dir/*.gz");

    my $t1 = $c->{'request'}->{'parameters'}->{'t1'};
    my $t2 = $c->{'request'}->{'parameters'}->{'t2'};

    # get all files which are matching the timeframe
    my $truncated  = 0;
    my $files_read = 0;
    my @file_list;
    for my $file (@files) {
        $file =~ m/\/(\d+)\./mxo;
        my $time = $1;
        if($time < $t1 || $time > $t2) {
            next;
        }
        push @file_list, $file;
        $files_read++;
    }

    my $num = scalar @file_list;
    if($num > 500) {
        $truncated = 1;
        my $keep = int($num / 500);
        my @newfiles;
        my $x = 0;
        for my $file (@file_list) {
            $x++;
            if($x == 1 || $x == $num || $x % $keep == 0) {
                push @newfiles, $file;
            }
        }
        @file_list = @newfiles;
    }

    # now read all zip files at once
    my $proc_found = {};
    my $pattern    = _get_pattern($c);
    my $data       = _extract_top_data(\@file_list, undef, $pattern, $proc_found, $truncated);

    # create series to draw
    my $mem_series = [
        { label => "memory total",  data =>  [], color => "#000000"  },
        { label => "memory used",   data =>  [], stack => undef, lines => { fill => 1 } },
        { label => "buffers",       data =>  [], stack => 1, lines => { fill => 1 } },
        { label => "cached",        data =>  [], stack => 1, lines => { fill => 1 } },
    ];
    my $cpu_series = [
        { label => "user",      data =>  [], stack => 1, lines => { fill => 1 } },
        { label => "system",    data =>  [], stack => 1, lines => { fill => 1 } },
        { label => "nice",      data =>  [], stack => 1, lines => { fill => 1 } },
        { label => "wait",      data =>  [], stack => 1, lines => { fill => 1 } },
        #{ label => "high",      data =>  [], stack => undef },
        #{ label => "si",        data =>  [], stack => undef },
        #{ label => "st",        data =>  [], stack => undef },
    ];
    my $load_series = [
        { label => "load 1",  data =>  [] },
        { label => "load 5",  data =>  [] },
        { label => "load 15", data =>  [] },
    ];
    my $swap_series = [
        { label => "swap total",  color => "#000000", data =>  [] },
        { label => "swap used",   color => "#edc240", data =>  [], lines => { fill => 1 } },
    ];
    my $gearman_series = [
        { label => "checks running", color => "#0354E4", data =>  [] },
        { label => "checks waiting", color => "#F46312", data =>  [] },
        { label => "worker",         color => "#00C600", data =>  [] },
    ];
    my $proc_cpu_series = [];
    my $proc_mem_series = [];
    for my $key (sort keys %{$proc_found}) {
        push @{$proc_cpu_series}, { label => $key, data => [], stack => undef };
        push @{$proc_mem_series}, { label => $key, data => [], stack => undef };
    }
    for my $time (sort keys %{$data}) {
        my $js_time = $time*1000;
        my $d       = $data->{$time};
        push @{$mem_series->[0]->{'data'}}, [$js_time, $d->{mem}];
        push @{$mem_series->[1]->{'data'}}, [$js_time, $d->{mem_used}];
        push @{$mem_series->[2]->{'data'}}, [$js_time, $d->{buffers}];
        push @{$mem_series->[3]->{'data'}}, [$js_time, $d->{cached}];

        push @{$swap_series->[0]->{'data'}}, [$js_time, $d->{swap}];
        push @{$swap_series->[1]->{'data'}}, [$js_time, $d->{swap_used}];

        push @{$cpu_series->[0]->{'data'}}, [$js_time, $d->{cpu_us}];
        push @{$cpu_series->[1]->{'data'}}, [$js_time, $d->{cpu_sy}];
        push @{$cpu_series->[2]->{'data'}}, [$js_time, $d->{cpu_ni}];
        push @{$cpu_series->[3]->{'data'}}, [$time*1000, $data->{$time}->{cpu_wa}];
        #push @{$cpu_series->[4]->{'data'}}, [$js_time, $d->{cpu_hi}];
        #push @{$cpu_series->[5]->{'data'}}, [$js_time, $d->{cpu_si}];
        #push @{$cpu_series->[6]->{'data'}}, [$js_time, $d->{cpu_st}];

        push @{$load_series->[0]->{'data'}}, [$js_time, $d->{load1}];
        push @{$load_series->[1]->{'data'}}, [$js_time, $d->{load5}];
        push @{$load_series->[2]->{'data'}}, [$js_time, $d->{load15}];

        if($d->{gearman}) {
            push @{$gearman_series->[0]->{'data'}}, [$js_time, $d->{gearman}->{service}->{running}];
            push @{$gearman_series->[1]->{'data'}}, [$js_time, $d->{gearman}->{service}->{waiting}];
            push @{$gearman_series->[2]->{'data'}}, [$js_time, $d->{gearman}->{service}->{worker}];
        }

        my $x = 0;
        for my $key (sort keys %{$proc_found}) {
            push @{$proc_cpu_series->[$x]->{'data'}}, [$js_time, $d->{procs}->{$key}->{'cpu'} || 0];
            push @{$proc_mem_series->[$x]->{'data'}}, [$js_time, $d->{procs}->{$key}->{'mem'} || 0];
            $x++;
        }
    }
    $c->stash->{truncated}       = $truncated;
    $c->stash->{mem_series}      = $mem_series;
    $c->stash->{swap_series}     = $swap_series;
    $c->stash->{cpu_series}      = $cpu_series;
    $c->stash->{load_series}     = $load_series;
    $c->stash->{proc_cpu_series} = $proc_cpu_series;
    $c->stash->{proc_mem_series} = $proc_mem_series;
    $c->stash->{gearman_series}  = $gearman_series;
    return;
}

##########################################################

=head2 top_graph_data

=cut
sub top_graph_data {
    my ( $self, $c ) = @_;
    my @files = sort glob("$top_dir/*.log $top_dir/*.gz");
    my $time = $c->{'request'}->{'parameters'}->{'time'};
    my $lastfile;
    for my $file (@files) {
        $file =~ m/\/(\d+)\./mxo;
        my $timestamp = $1;
        last if $timestamp > $time;
        $lastfile = $file;
    }
    my $d    = _extract_top_data([$lastfile], 1);
    my $data = $d->{$time};
    $data->{'file'}     = $lastfile;
    if(defined $ENV{'OMD_ROOT'}) { my $root = $ENV{'OMD_ROOT'}; $data->{'file'} = s|$root||gmx; }
    $c->stash->{'json'} = $data;
    return $c->forward('Thruk::View::JSON');
}

##########################################################
sub _extract_top_data {
    my($files, $with_raw, $pattern, $proc_found, $first_one_only) = @_;

    my($pid, $wtr, $rdr, @lines);
    $pid = open3($wtr, $rdr, $rdr, 'zcat', @{$files});
    close($wtr);

    $files->[0] =~ m/\/(\d+)\./mxo;
    my(@startdate) = localtime($1);

    my $proc_started    = 0;
    my $gearman_started = 0;
    my $skip_this_one   = 0;
    my $result          = {};
    my($cur, $gearman);
    my $last_hour = $startdate[2];
    my $last_min  = -1;
    while(my $line = <$rdr>) {
        &_trim($line);

        if($line =~ m/^top\s+\-\s+(\d+):(\d+):(\d+)\s+up.*?average:\s*([\.\d]+),\s*([\.\d]+),\s*([\.\d]+)/mxo) {
            if($cur) { $result->{$cur->{time}} = $cur; }
            $cur = { procs => {} };
            $cur->{'raw'} = [] if $with_raw;
            $cur->{'load1'}  = $4;
            $cur->{'load5'}  = $5;
            $cur->{'load15'} = $6;
            $skip_this_one   = 0;
            my($hour,$min,$sec) = ($1,$2,$3);
            if($last_hour == 23 and $hour != 23) {
                @startdate = localtime(POSIX::mktime(59, 59, 23, $startdate[3], $startdate[4], $startdate[5], $startdate[6], $startdate[7])+7500);
            }
            $cur->{'time'}   = POSIX::mktime($sec, $min, $hour, $startdate[3], $startdate[4], $startdate[5], $startdate[6], $startdate[7]);
            if($first_one_only) {
                if($last_min == $min) {
                    $skip_this_one = 1;
                    $cur           = undef;
                    next;
                }
            }
            $last_hour       = $hour;
            $last_min        = $min;
            $proc_started    = 0;
            $gearman_started = 0;
            if($gearman) {
                $cur->{gearman} = $gearman;
                $gearman        = undef;
            }
            next;
        }

        if($line =~ m/^Queue\ Name/mxo) {
            $gearman_started = 1;
            $gearman         = {};
            next;
        }

        if($gearman_started) {
            if($line =~ m/^(\w+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)/mxo) {
                $gearman->{$1} = { worker => 0+$2, waiting => 0+$3, running => 0+$4 };
            }
        }

        next if $skip_this_one;

        if(!$proc_started) {
            if($line =~ m/^PID/mxo) {
                $proc_started    = 1;
                $gearman_started = 0;
            }
            elsif($line =~ m/^Tasks:\s*(\d+)\s*total,/mxo) {
                $cur->{'num'} = $1;
            }
            # CPU %
            elsif($line =~ m/^%?Cpu\(s\):\s*([\.\d]+)[%\s]*us,\s*([\.\d]+)[%\s]*sy,\s*([\.\d]+)[%\s]*ni,\s*([\.\d]+)[%\s]*id,\s*([\.\d]+)[%\s]*wa,\s*([\.\d]+)[%\s]*hi,\s*([\.\d]+)[%\s]*si,\s*([\.\d]+)[%\s]*st/mxo) {
                $cur->{'cpu_us'} = $1;
                $cur->{'cpu_sy'} = $2;
                $cur->{'cpu_ni'} = $3;
                $cur->{'cpu_id'} = $4;
                $cur->{'cpu_wa'} = $5;
                $cur->{'cpu_hi'} = $6;
                $cur->{'cpu_si'} = $7;
                $cur->{'cpu_st'} = $8;
            }
            # Memory
            elsif($line =~ m/^(KiB|)\s*Mem:\s*([\.\w]+)\s*total,\s*([\.\w]+)\s*used,\s*([\.\w]+)\s*free,\s*([\.\w]+)\s*buffers/mxo) {
                my $factor = $1 eq 'KiB' ? 1024 : 1;
                $cur->{'mem'}      = _normalize_mem($2, $line, $factor);
                $cur->{'mem_used'} = _normalize_mem($3, $line, $factor);
                $cur->{'buffers'}  = _normalize_mem($5, $line, $factor);
            }
            # Swap / Cached
            elsif($line =~ m/^(KiB|)\s*Swap:\s*([\.\w]+)\s*total,\s*([\.\w]+)\s*used,\s*([\.\w]+)\s*free(,|\.)\s*([\.\w]+)\s*cached/mxo) {
                my $factor = $1 eq 'KiB' ? 1024 : 1;
                $cur->{'swap'}      = _normalize_mem($2, $line, $factor);
                $cur->{'swap_used'} = _normalize_mem($3, $line, $factor);
                $cur->{'cached'}    = _normalize_mem($6, $line, $factor);
            }
        } else {
            my($pid, $user, $prio, $nice, $virt, $res, $shr, $status, $cpu, $mem, $time, $cmd) = split(/\s+/mxo, $line, 12);
            next unless $cmd;
            push @{$cur->{'raw'}}, [$pid, $user, $prio, $nice, $virt, $res, $shr, $status, $cpu, $mem, $time, $cmd] if $with_raw;
            my $key = 'other';
            for my $p (@{$pattern}) {
                if($line =~ m|$p->[0]|mx) {
                    $key = $p->[1];
                }
            }
            $cur->{procs}->{$key}->{num}  += 1;
            $cur->{procs}->{$key}->{cpu}  += $cpu;
            $cur->{procs}->{$key}->{virt} += _normalize_mem($virt, $line);
            $cur->{procs}->{$key}->{res}  += _normalize_mem($res, $line);
            $cur->{procs}->{$key}->{mem}  += $mem;
            $proc_found->{$key} = 1;
        }
    }
    if($gearman && $cur) {
        $cur->{gearman} = $gearman;
    }
    if($cur) { $result->{$cur->{time}} = $cur; }
    return($result);
}

##########################################################
# returns memory in megabyte
sub _normalize_mem {
    my($value, $line, $factor) = @_;
    $factor = 1 unless $factor;

    if($value =~ m/^([\d\.]+)([a-zA-Z])$/mx) {
        $value = $1;
        my $unit = lc($2);
        if(   $unit eq 'k') { $value = $value * 1024; }
        elsif($unit eq 'm') { $value = $value * 1024 * 1024; }
        elsif($unit eq 'g') { $value = $value * 1024 * 1024 * 1024; }
        else {
            die("could not parse top data ($value) in line: $line\n");
        }
    }
    if($value !~ m/^[\d\.]*$/mx) {
        die("could not parse top data ($value) in line: $line\n");
    }
    $value = $value * $factor;
    return(int($value/1024/1024));
}

##########################################################
sub _get_pattern {
    my($c) = @_;
    my $pattern = [];
    if($c && $c->config->{'omd_top'}) {
        for my $regex (@{$c->config->{'omd_top'}}) {
            my($k,$p) = split(/\s*=\s*/mx, $regex, 2);
            &_trim($p);
            &_trim($k);
            push @{$pattern}, [$k,$p];
        }
    }
    return($pattern);
}

##########################################################
sub _trim {
    $_[0] =~ s/^\s+//mx;
    $_[0] =~ s/\s+$//mx;
    return;
}

##########################################################

=head1 AUTHOR

Sven Nierlein, 2009-2014, <sven@nierlein.org>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
