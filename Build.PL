#!/usr/bin/env perl
use strict; use warnings;
use Module::Build;

my $build = Module::Build->new(
  module_name   => "Bot::Cobalt::Plugin::Weather",
  dist_abstract => "Weather plugin set for Bot::Cobalt",
  
  dist_author  => 'Jon Portnoy <avenj@cobaltirc.org>',
  
  license => 'perl',
  create_readme => 1,
  
  create_makefile_pl => 'small',
  
  requires => {
    'perl' => '5.12.1',

    'strictures'  => 1,

    'Bot::Cobalt' => '0.003',

    'HTML::TokeParser' => '3.69',
    'HTTP::Request' => 0,
    'URI::Escape'   => 0,
  }
);

$build->create_build_script;
