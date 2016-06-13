# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2012-2016 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::PageOptimizerPlugin::Stats;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
our $pluginName = 'PageOptimizerPlugin';

###############################
sub new {
  my $class = shift;


  my $this = bless({
      @_
    },
    $class
  );

  return $this;
}

###############################
sub finish {
}


###############################
sub logJavaScript {
  my ($this, $urls) = @_;

  my $workArea = Foswiki::Func::getWorkArea($pluginName);
  my $fileName = $workArea.'/javascript.log';
  my $file;

  my $baseWeb = $Foswiki::Plugins::SESSION->{webName};
  my $baseTopic = $Foswiki::Plugins::SESSION->{topicName};

  open($file, ">>", $fileName) or die "can't open logfile $fileName";
  print $file "$baseWeb.$baseTopic:" . join(', ', @$urls) . "\n";
  close($file);
}

###############################
sub logStylesheet {
  my ($this, $urls) = @_;

  my $workArea = Foswiki::Func::getWorkArea($pluginName);
  my $fileName = $workArea.'/stylesheet.log';
  my $file;

  my $baseWeb = $Foswiki::Plugins::SESSION->{webName};
  my $baseTopic = $Foswiki::Plugins::SESSION->{topicName};

  open($file, ">>", $fileName) or die "can't open logfile $fileName";
  print $file "$baseWeb.$baseTopic:" . join(', ', @$urls) . "\n";
  close($file);
}

###############################
sub restStatistics {
  my ($this, $session, $subject, $verb, $response) = @_;

  #print STDERR "called restStatistics\n";

  my $query = Foswiki::Func::getCgiQuery();
  my $type = $query->param("type");

  my $workArea = Foswiki::Func::getWorkArea($pluginName);

  if (!defined $type || $type eq 'js') {
    my $fileName = $workArea.'/javascript.log';
    my $stats = $this->gatherStatistics($fileName);
    if ($stats) {
      print "javascripts: ".scalar(keys %$stats)."\n";
      foreach my $key (sort {$stats->{$b} <=> $stats->{$a}} keys %$stats) {
        my $val = int($stats->{$key} * 100);
        print "   $key: $val%\n";
      }
    }
  }

  if (!defined $type || $type eq 'css') {
    my $fileName = $workArea.'/stylesheet.log';
    my $stats = $this->gatherStatistics($fileName);
    if ($stats) {
      print "stylesheets: ".scalar(keys %$stats)."\n";
      foreach my $key (sort {$stats->{$b} <=> $stats->{$a}} keys %$stats) {
        my $val = int($stats->{$key} * 100);
        print "   $key: $val%\n";
      }
    }
  }

  return "";
}

###############################
sub gatherStatistics {
  my ($this, $fileName) = @_;

  #print STDERR "called gatherStatistics\n";

  unless (-e $fileName) {
    print STDERR "no statistics found in $fileName\n";
    return;
  }

  my $file;
  my $data = Foswiki::Func::readFile($fileName);
  my %stats = ();

  my $index = 0;
  while($data =~ /^(.*?)$/mg) {
    my $line = $1;
    if ($line =~ /^(.*):\s*(.*)$/) {
      my $topic = $1;
      $index++;
      #print STDERR "topic=$topic\n";
      foreach my $url (split(/\s*,\s*/, $2)) {
        my $key = $url;
        $key =~ s/\?.*?$//;
        push @{$stats{$key}}, $topic;
      }
    }
  }

  foreach my $key (keys %stats) {
    $stats{$key} = (scalar(@{$stats{$key}} + 0.0) / $index);
  }

  return \%stats;
}

1;
