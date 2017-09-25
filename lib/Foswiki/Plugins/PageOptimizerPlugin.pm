# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2012-2017 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.
# For more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the Foswiki root.

package Foswiki::Plugins::PageOptimizerPlugin;

use strict;
use warnings;

use Foswiki::Func ();    # The plugins API
use Foswiki::Plugins (); # For the API version
use Digest::MD5 ();
use URI ();
use Compress::Zlib ();

our $VERSION = '3.00';
our $RELEASE = '25 Sep 2017';
our $SHORTDESCRIPTION = 'Optimize html markup, as well as js and css';
our $NO_PREFS_IN_TOPIC = 1;
our $core;
our $stats;

###############################################################################
sub initPlugin {

  Foswiki::Func::registerRESTHandler('statistics', sub {
      return getStats()->restStatistics(@_);
    }, 
    authenticate => 1,
    validate => 0,
    http_allow => 'GET',
  );

  Foswiki::Func::registerRESTHandler('purgeCache', sub { return getCore()->purgeCache(@_); },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  return 1;
}

###############################################################################
sub getCore {
  unless (defined $core) {
    require Foswiki::Plugins::PageOptimizerPlugin::Core;
    $core = Foswiki::Plugins::PageOptimizerPlugin::Core->new();
  }

  return $core;
}

###############################################################################
sub getStats {
  unless (defined $core) {
    require Foswiki::Plugins::PageOptimizerPlugin::Stats;
    $core = Foswiki::Plugins::PageOptimizerPlugin::Stats->new();
  }

  return $core;
}

###############################################################################
sub finishPlugin {
  $core->finish if defined $core;
  $stats->finish if defined $stats;

  undef $core;
  undef $stats;
}

###############################################################################
sub completePageHandler {
  my $text = $_[0];
  my $header = $_[1];

  return unless $header =~ /Content-type: text\/html/;

  # clean up
  use bytes;
  $text =~ s/<!--\s+-->//g; # remove this in any case
  $text =~ s/(<\/html>).*?$/$1/gs;

  # remove non-macros and leftovers
  $text =~ s/%(?:REVISIONS|REVTITLE|REVARG|QUERYPARAMSTRING)%//g;
  $text =~ s/^%META:\w+{.*}%$//gm;

  if ($Foswiki::cfg{PageOptimizerPlugin}{CleanUpHTML}) {
    $text =~ s/<!--[^\[<].*?-->//g;
    $text =~ s/^\s*$//gms;
    
    # EXPERIMENTAIL: make at least some <p>s real paragraphs
    if (1) {
      $text =~ s/<p><\/p>\s*([^<>]+?)\s*(?=<p><\/p>)/<p class='p'>$1<\/p>\n\n/gs;
      $text =~ s/\s*<\/p>(?:\s*<p><\/p>)*/<\/p>\n/gs; # remove useless <p>s
    }

    # clean up %{<verbatim>}% ...%{</verbatim>}%
    $text =~ s/\%\{(<pre[^>]*>)\}&#37;\s*/$1/g;
    $text =~ s/\s*&#37;\{(<\/pre>)\}\%/$1/g;

    # make empty table cells really empty
    $text =~ s/(<td[^>]*>)\s+(<\/td>)/$1$2/gs;

    # clean up non html tags
    $text =~ s/<\/?(?:nop|noautolink|sticky|literal)>//g;
  }
  no bytes;

  if ($Foswiki::cfg{PageOptimizerPlugin}{OptimizeJavaScript} || $Foswiki::cfg{PageOptimizerPlugin}{OptimizeStylesheets}) {
    my $query = Foswiki::Func::getCgiQuery();
    my $refresh = $query->param("refresh") || '';
    getCore()->purgeCache() if $refresh =~ /\ball\b/;
  }

  $text = getCore()->optimizeJavaScript($text) if $Foswiki::cfg{PageOptimizerPlugin}{OptimizeJavaScript};
  $text = getCore()->optimizeStylesheets($text) if $Foswiki::cfg{PageOptimizerPlugin}{OptimizeStylesheets};

  $text =~ s/^\s+$//gms;    # remove a few empty lines

  # return the changed text
  $_[0] = $text;
}

###############################################################################
sub preRenderingHandler {
  # better cite markup
  $_[0] =~ s/[\n\r](>.*?)([\n\r][^>])/_processCite($1).$2/ges;
}

###############################################################################
sub _processCite {
  my $block = shift;

  $block =~ s/^>/<span class='foswikiCiteChar'>&gt;<\/span>/gm;
  #$block =~ s/\n/<br \/>\n/g;

  my $class = ($block =~ /\n/)?'foswikiBlockQuote':'foswikiCite';

  return "<div class='$class'>".$block."</div>";
}

1;
