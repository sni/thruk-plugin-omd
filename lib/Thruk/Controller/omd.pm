package Thruk::Controller::omd;
use parent 'Catalyst::Controller';

use strict;
use warnings;

use Carp;
use JSON::XS;
use File::Slurp qw/read_file/;

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

my $top_dir = defined $ENV{'OMD_ROOT'} ? $ENV{'OMD_ROOT'}.'/var/top' : 'var/top';

######################################

=head2 omd_cgi

page: /thruk/cgi-bin/omd.cgi

=cut
sub omd_cgi : Path('/thruk/cgi-bin/omd.cgi') {
    my ( $self, $c ) = @_;
    return if defined $c->{'canceled'};
    return $c->detach('/omd/index');
}

##########################################################

=head2 index

=cut
sub index :Path :Args(0) :MyAction('AddCachedDefaults') {
    my ( $self, $c ) = @_;

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
    my @files = sort glob($top_dir.'/*');
    my $num = 0;
    my $max = scalar @files;
    for my $file (@files) {
        $num++;
        next if($num != 1 and $num != $max and $num%15 != 0);
        my $out = `zgrep -m 1 'load average:' $file 2>/dev/null`;
        $file =~ m|/(\d+)\.log|mxo;
        my $time = $1;
        if($out =~ m/top\s+\-\s+(\d+):(\d+):(\d+)\s+up.*?average:\s*([\.\d]+),\s*([\.\d]+),\s*([\.\d]+)/mxo) {
            my($hour,$min,$sec) = ($1,$2,$3);
            $time = ($time - $time%60) + $sec;
            push @{$load_series->[0]->{'data'}}, [$time*1000, $4];
            push @{$load_series->[1]->{'data'}}, [$time*1000, $5];
            push @{$load_series->[2]->{'data'}}, [$time*1000, $6];
        }
    }
    $c->stash->{load_series} = $load_series;
}

##########################################################

=head2 top_graph_details

=cut
sub top_graph_details {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'omd_top_details.tt';
    $c->stash->{'no_auto_reload'}      = 1;
    my @files = sort glob($top_dir.'/*');

    my $t1 = $c->{'request'}->{'parameters'}->{'t1'};
    my $t2 = $c->{'request'}->{'parameters'}->{'t2'};

    # get last 10 files for now
    my $data       = {};
    my $proc_found = {};
    my $files_read = 0;
    for my $file (@files) {
        $file =~ m/\/(\d+)\./mxo;
        my $time = $1;
        if($time < $t1 || $time > $t2) {
            next;
        }
        my($d, $p)  = _extract_top_data($c, $file);
        $data       = {%{$data}, %{$d}};
        $proc_found = {%{$proc_found}, %{$p}};
        last if $files_read > 300;
        $files_read++;
    }

    # create series to draw
    my $mem_series = [
        { label => "memory total",  data =>  [], color => "#000000"  },
        { label => "memory used",   data =>  [] },
        { label => "buffers",       data =>  [] },
        { label => "cached",        data =>  [] },
    ];
    my $cpu_series = [
        { label => "user",      data =>  [], stack => undef },
        { label => "system",    data =>  [], stack => undef },
        { label => "nice",      data =>  [], stack => undef },
        { label => "wait",      data =>  [], stack => undef },
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
        { label => "swap used",   color => "#edc240", data =>  [] },
    ];
    my $proc_cpu_series = [];
    my $proc_mem_series = [];
    for my $key (sort keys %{$proc_found}) {
        push @{$proc_cpu_series}, { label => $key, data => [], stack => undef };
        push @{$proc_mem_series}, { label => $key, data => [], stack => undef };
    }
    for my $time (sort keys %{$data}) {
        push @{$mem_series->[0]->{'data'}}, [$time*1000, $data->{$time}->{mem}];
        push @{$mem_series->[1]->{'data'}}, [$time*1000, $data->{$time}->{mem_used}];
        push @{$mem_series->[2]->{'data'}}, [$time*1000, $data->{$time}->{buffers}];
        push @{$mem_series->[3]->{'data'}}, [$time*1000, $data->{$time}->{cached}];

        push @{$swap_series->[0]->{'data'}}, [$time*1000, $data->{$time}->{swap}];
        push @{$swap_series->[1]->{'data'}}, [$time*1000, $data->{$time}->{swap_used}];

        push @{$cpu_series->[0]->{'data'}}, [$time*1000, $data->{$time}->{cpu_us}];
        push @{$cpu_series->[1]->{'data'}}, [$time*1000, $data->{$time}->{cpu_sy}];
        push @{$cpu_series->[2]->{'data'}}, [$time*1000, $data->{$time}->{cpu_ni}];
        push @{$cpu_series->[3]->{'data'}}, [$time*1000, $data->{$time}->{cpu_wa}];
        #push @{$cpu_series->[4]->{'data'}}, [$time*1000, $data->{$time}->{cpu_hi}];
        #push @{$cpu_series->[5]->{'data'}}, [$time*1000, $data->{$time}->{cpu_si}];
        #push @{$cpu_series->[6]->{'data'}}, [$time*1000, $data->{$time}->{cpu_st}];

        push @{$load_series->[0]->{'data'}}, [$time*1000, $data->{$time}->{load1}];
        push @{$load_series->[1]->{'data'}}, [$time*1000, $data->{$time}->{load5}];
        push @{$load_series->[2]->{'data'}}, [$time*1000, $data->{$time}->{load15}];

        #for my $key (keys %{$data->{$time}->{procs}}) {
        my $x = 0;
        for my $key (sort keys %{$proc_found}) {
            push @{$proc_cpu_series->[$x]->{'data'}}, [$time*1000, $data->{$time}->{procs}->{$key}->{'cpu'} || 0];
            push @{$proc_mem_series->[$x]->{'data'}}, [$time*1000, $data->{$time}->{procs}->{$key}->{'mem'} || 0];
            $x++;
        }
    }
    $c->stash->{mem_series}      = $mem_series;
    $c->stash->{swap_series}     = $swap_series;
    $c->stash->{cpu_series}      = $cpu_series;
    $c->stash->{load_series}     = $load_series;
    $c->stash->{proc_cpu_series} = $proc_cpu_series;
    $c->stash->{proc_mem_series} = $proc_mem_series;
    return;
}

##########################################################

=head2 top_graph_data

=cut
sub top_graph_data {
    my ( $self, $c ) = @_;
    my @files = sort glob($top_dir.'/*');
    my $time = $c->{'request'}->{'parameters'}->{'time'};
    my $lastfile;
    for my $file (@files) {
        $file =~ m/\/(\d+)\./mxo;
        my $timestamp = $1;
        last if $timestamp > $time;
        $lastfile = $file;
    }
    my($d, $p) = _extract_top_data($c, $lastfile, 1);
    my $data = $d->{$time};
    $c->stash->{'json'} = $data;
    return $c->forward('Thruk::View::JSON');
}

##########################################################
sub _extract_top_data {
    my($c, $file, $with_raw) = @_;
    my $content;
    if($file =~ m/\.gz$/mx) {
        $content = `zcat $file`;
    } else {
        $content = read_file($file);
    }

    my $pattern = [];
    if($c->config->{'omd_top'}) {
        for my $regex (@{$c->config->{'omd_top'}}) {
            my($k,$p) = split(/\s*=\s*/mx, $regex, 2);
            $p =~ s/^\s*//mx;
            $p =~ s/\s*$//mx;
            $k =~ s/^\s*//mx;
            $k =~ s/\s*$//mx;
            push @{$pattern}, [$k,$p];
        }
    }

    my $proc_found   = {};
    my $proc_started = 0;
    my $result = {};
    my $cur;
    for my $line (split/\n/mx, $content) {
        $line =~ s/^\s+//mxo;
        $line =~ s/\s+$//mxo;
        if($line =~ m/^top\s+\-\s+(\d+):(\d+):(\d+)\s+up.*?average:\s*([\.\d]+),\s*([\.\d]+),\s*([\.\d]+)/mxo) {
            if($cur) { $result->{$cur->{time}} = $cur; }
            $cur = { procs => {} };
            $cur->{'raw'} = [] if $with_raw;
            $cur->{'load1'}  = $4;
            $cur->{'load5'}  = $5;
            $cur->{'load15'} = $6;
            my($hour,$min,$sec) = ($1,$2,$3);
            $file =~ m/\/(\d+)\./mxo;
            my $time = $1;
            $cur->{'time'}   = ($time - $time%60) + $sec;
            $proc_started = 0;
        }
        elsif($line =~ m/^Tasks:\s*(\d+)\s*total,/mxo) {
            $cur->{'num'} = $1;
        }
        elsif($line =~ m/^%?Cpu\(s\):\s*([\.\d]+)[%\s]*us,\s*([\.\d]+)[%\s]*sy,\s*([\.\d]+)[%\s]*ni,\s*([\.\d]+)[%\s]*id,\s*([\.\d]+)[%\s]*wa,\s*([\.\d]+)[%\s]*hi,\s*([\.\d]+)[%\s]*si,\s*([\.\d]+)[%\s]*st/mxo) {
            $cur->{'cpu_us'} = $1;
            $cur->{'cpu_sy'} = $2;
            $cur->{'cpu_ni'} = $3;
            $cur->{'cpu_id'} = $4;
            $cur->{'cpu_wa'} = $5;
            $cur->{'cpu_hi'} = $6;
            $cur->{'cpu_si'} = $6;
            $cur->{'cpu_st'} = $7;
        }
        elsif($line =~ m/^(KiB|)\s*Mem:\s*([\.\w]+)\s*total,\s*([\.\w]+)\s*used,\s*([\.\w]+)\s*free,\s*([\.\w]+)\s*buffers/mxo) {
            my $factor = $1 eq 'KiB' ? 1024 : 1;
            $cur->{'mem'}      = _normalize_mem($factor * $2, $line);
            $cur->{'mem_used'} = _normalize_mem($factor * $3, $line);
            $cur->{'buffers'}  = _normalize_mem($factor * $5, $line);
        }
        elsif($line =~ m/(KiB|)\s*Swap:\s*([\.\w]+)\s*total,\s*([\.\w]+)\s*used,\s*([\.\w]+)\s*free,\s*([\.\w]+)\s*cached/mxo) {
            my $factor = $1 eq 'KiB' ? 1024 : 1;
            $cur->{'swap'}      = _normalize_mem($factor * $2, $line);
            $cur->{'swap_used'} = _normalize_mem($factor * $3, $line);
            $cur->{'cached'}    = _normalize_mem($factor * $5, $line);
        }
        elsif($proc_started) {
            my($pid, $user, $prio, $nice, $virt, $res, $shr, $status, $cpu, $mem, $time, $cmd) = split(/\s+/mx, $line, 12);
            next unless $cmd;
            push @{$cur->{'raw'}}, [$pid, $user, $prio, $nice, $virt, $res, $shr, $status, $cpu, $mem, $time, $cmd];
            my $key = 'other';
            for my $p (@{$pattern}) {
                if($cmd =~ m|$p->[0]|mx) {
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
        elsif($line =~ m/^PID/mxo) {
            $proc_started = 1;
        }
    }
    if($cur) { $result->{$cur->{time}} = $cur; }
    return($result, $proc_found);
}

##########################################################
# returns memory in megabyte
sub _normalize_mem {
    my($value, $line) = @_;

    if($value =~ m/^([\d\.]+)([a-z])$/) {
        $value = $1;
        if(   $2 eq 'k') { $value = $value * 1024; }
        elsif($2 eq 'm') { $value = $value * 1024 * 1024; }
        elsif($2 eq 'g') { $value = $value * 1024 * 1024 * 1024; }
        else {
            die("could not parse top data ($value) in line: $line\n");
        }
    }
    if($value !~ m/^[\d\.]*$/mx) {
        die("could not parse top data ($value) in line: $line\n");
    }
    return(int($value/1024/1024));
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
