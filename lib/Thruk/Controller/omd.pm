package Thruk::Controller::omd;
use parent 'Catalyst::Controller';

use strict;
use warnings;

use Carp;
use JSON::XS;
use File::Slurp qw/read_file/;
use IPC::Open3 qw/open3/;
#use Thruk::Timer qw/timing_breakpoint/;

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
    $c->stash->{no_auto_reload}        = 1;

    our $hosts_list = undef;

    # check permissions
    unless( $c->check_user_roles( "authorized_for_configuration_information")
        and $c->check_user_roles( "authorized_for_system_commands")) {
        return $c->detach('/error/index/8');
    }

    # get input folders
    my $default_parser = 'LinuxTop';
    my $folder_hash    = {};
    my $folders        = [];
    if(-d $top_dir.'/.') {
        $folder_hash->{$top_dir} = $default_parser;
    }
    if($c->config->{'omd_top_extra_dir'}) {
        for my $dir (@{Thruk::Utils::list($c->config->{'omd_top_extra_dir'})}) {
            my($parser, $folder) = split/\s*=\s*/mx, $dir;
            if(!$folder) { $folder = $parser; $parser = $default_parser; }
            next unless -d $folder.'/.';
            my @subdirs = glob($folder.'/*');
            for my $sub (sort @subdirs) {
                my $display = $sub;
                $display =~ s|.*/||mx;
                push @{$folders}, { parser => $parser, 'dir' => $sub, display => $display };
                $folder_hash->{$sub} = $parser;
            }
        }
    }
    $folders = Thruk::Backend::Manager->_sort($folders, 'display');
    if(-d $top_dir.'/.') {
        unshift @{$folders}, { parser => $default_parser, 'dir' => $top_dir, 'display' => 'Monitoring Server' };
    }
    $c->stash->{folders} = $folders;
    $c->stash->{folder}  = $c->{'request'}->{'parameters'}->{'folder'} || $top_dir;
    if(!$folder_hash->{$c->stash->{folder}}) { $c->stash->{folder} = $top_dir; }
    $c->stash->{parser}  = $folder_hash->{$c->stash->{folder}};
    my $class   = 'Thruk::OMD::Top::Parser::'.$c->stash->{parser};
    my $require = $class;
    $require =~ s/::/\//gmx;
    require $require . ".pm";
    $class->import;
    my $parser = $class->new($c->stash->{folder});

    my $action = $c->{'request'}->{'parameters'}->{'action'} || '';
    if($action eq 'top_details') {
        return $parser->top_graph_details($c);
    }
    elsif($action eq 'top_data') {
        return $parser->top_graph_data($c);
    }

    return $parser->top_graph($c);
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
