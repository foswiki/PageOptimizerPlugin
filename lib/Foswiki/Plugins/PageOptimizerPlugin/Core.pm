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

package Foswiki::Plugins::PageOptimizerPlugin::Core;

use strict;
use warnings;
use Foswiki::Plugins();
use Foswiki::Func();
use Foswiki::Plugins::PageOptimizerPlugin ();

use constant TRACE => 0;    # toggle me

###############################################################################
sub new {
  my $class = shift;


  my $this = bless({
      cacheDir => $Foswiki::cfg{PageOptimizerPlugin}{CacheDir}
        || $Foswiki::cfg{PubDir} . '/' . $Foswiki::cfg{SystemWebName} . '/PageOptimizerPlugin/cache/',
      cachePath => $Foswiki::cfg{PageOptimizerPlugin}{CachePath} 
        || $Foswiki::cfg{PubUrlPath} . '/' . $Foswiki::cfg{SystemWebName} . '/PageOptimizerPlugin/cache/',
      @_
    },
    $class
  );

  # make sure it has got a tailing slash
  $this->{cacheDir} =~ s/\/?$/\//;
  $this->{cachePath} =~ s/\/?$/\//;

  mkdir $this->{cacheDir} unless -d $this->{cacheDir};

  return $this;
}

###############################################################################
sub finish {

  # nop for now
}

###############################################################################
sub optimizeJavaScript {
  my ($this, $text) = @_;

  # take out ie stuff
  my @ieConditionals = ();
  my $index = 0;
  while ($text =~ s/(<!\-\- +\[if.*?<!\[endif\]\-\->)/\0ie$index/s) {

    #_writeDebug("found ie conditional: $1");
    push @ieConditionals, $1;
    $index++;
  }

  # collect all javascript
  my @jsUrls = ();
  my $excludePattern = '';

  # if we defined JQueryVersionForOldIEs then the jQuery core lib has to be excluded from the process
  if (defined $Foswiki::cfg{PageOptimizerPlugin}{ExcludeJavaScript} || $Foswiki::cfg{JQueryPlugin}{JQueryVersionForOldIEs}) {
    $excludePattern = '(?!.*(?:' . $Foswiki::cfg{PageOptimizerPlugin}{ExcludeJavaScript} . ($Foswiki::cfg{JQueryPlugin}{JQueryVersionForOldIEs} ? '|jquery\-\d\.\d' : '') . '))';
  }

  #_writeDebug("excludePattern=$excludePattern");

  my %classes = ();
  $classes{"script"} = 1;
  while ($text =~ s/<script (?:class=["']([^"']+)["'])?.*?type=["']text\/javascript["'] .*?src=["'](\/$excludePattern(?:[^"']+))["'].*><\/script>/\0js\0/) {
    #_writeDebug("found src $2 in script tag");
    if ($1) {
      $classes{$_} = 1 foreach split(/ /, $1);
    }
    push @jsUrls, $2;
  }

  # put back ie stuff
  $index = 0;
  foreach my $cond (@ieConditionals) {
    $text =~ s/\0ie$index/$cond/;
  }

  return $text unless @jsUrls;

  # check if there's a cache file already
  my ($cacheFileName, $cacheUrl) = $this->getCacheEntry("js", \@jsUrls);

  my $query = Foswiki::Func::getCgiQuery();
  my $refresh = $query->param("refresh") || '';

  my $cacheFileTime = _getModificationTime($cacheFileName);
  my $needsUpdate = 0;
  foreach my $url (@jsUrls) {
    my $fileName = _url2FileName($url);
    my $fileTime = _getModificationTime($fileName);
    if ($cacheFileTime < $fileTime) {
      $needsUpdate = 1;
      _writeDebug("$fileName has been updated ... refreshing cache file");
      last;
    }
  }

  if ($needsUpdate || $refresh =~ /\b(on|all|cache|js)\b/ || !-f $cacheFileName) {
    # TODO: compare timestamps of files
    _writeDebug("creating cache at $cacheFileName");

    my $cachedData = '';

    foreach my $url (@jsUrls) {
      #_writeDebug("url=$url");
      my $fileName = _url2FileName($url);
      if (-f $fileName) {
        my $data = Foswiki::Func::readFile($fileName);
        if ($data) {
#          $cachedData .= "\n\n/* DEBUG: fileName=$fileName */\n"
#            if TRACE;
          $cachedData .= ";\n$data;\n";
        }
      } else {
        print STDERR "woops, file $fileName does not exist for url=$url\n";
      }
    }

    $cachedData =~ s/\/\/#\s+sourceMappingURL=.*?\.js\.map;//g;

    # save the cached javascript
    Foswiki::Func::saveFile($cacheFileName, $cachedData);

    # create a gzip'ed version as well
    $cachedData = Compress::Zlib::memGzip($cachedData);
    Foswiki::Func::saveFile($cacheFileName . '.gz', $cachedData);

    Foswiki::Plugins::PageOptimizerPlugin::getStats()->logJavaScript(\@jsUrls) 
      if $Foswiki::cfg{PageOptimizerPlugin}{GatherStatistics};

  } else {
    _writeDebug("found compressed javascript in cache at $cacheFileName");
  }

  my $classes = join(" ", sort keys %classes);

  # insert the cached javascript at the first position we've found a js url
  $text =~ s/\0js\0/<script class='$classes' type='text\/javascript' src='$cacheUrl'><\/script>/;

  # remove the rest
  $text =~ s/\0js\0//g;

  # add http/2 server push to http header
  my $session = $Foswiki::Plugins::SESSION;
  my $response = $session->{response};
  $response->pushHeader('Link', '<'.$cacheUrl.'>; rel=preload; as=script' );

  return $text;
}

###############################################################################
sub optimizeStylesheets {
  my ($this, $text) = @_;

  # collect all css
  $this->{_cssUrls} = [];
  my %classes = ();

  while ($text =~ s/((?:<(link) (?:class=["']([^"']+)["'])?.*?rel=["']stylesheet["']\s+href=["'](\/[^"']+)["'].*media=["']all["'](?:\s+type=["']text\/css["'])?[^\/>]*?\/?>)|(?:<(style)\s+.*?media=["']all["'][^>]*?>(.*?)<\/style>))/$this->_gatherCssUrls($2||$5, $4||$6)||$1/e) {
    if ($3) {
      $classes{$_} = 1 foreach split(/ /, $3);
    }
  }

  return $text unless @{$this->{_cssUrls}};

  my ($cacheFileName, $cacheUrl) = $this->getCacheEntry("css", $this->{_cssUrls});

  my $query = Foswiki::Func::getCgiQuery();
  my $refresh = $query->param("refresh") || '';

  my $cacheFileTime = _getModificationTime($cacheFileName);
  my $needsUpdate = 0;
  foreach my $url (@{$this->{_cssUrls}}) {
    my $fileName = _url2FileName($url);
    my $fileTime = _getModificationTime($fileName);
    if ($cacheFileTime < $fileTime) {
      $needsUpdate = 1;
      _writeDebug("$fileName has been updated ... refreshing cache file");
      last;
    }
  }

  if ($needsUpdate || $refresh =~ /\b(on|all|cache|css)\b/ || !-f $cacheFileName) {    
    _writeDebug("creating cache at $cacheFileName");

    my $cachedData = '';

    foreach my $url (@{$this->{_cssUrls}}) {
      my $data = $this->parseStylesheet($url);
      $cachedData .= $data if $data;
    }

    Foswiki::Func::saveFile($cacheFileName, $cachedData);
    $cachedData = Compress::Zlib::memGzip($cachedData);
    Foswiki::Func::saveFile($cacheFileName . '.gz', $cachedData);

    Foswiki::Plugins::PageOptimizerPlugin::getStats()->logStylesheet($this->{_cssUrls})
      if $Foswiki::cfg{PageOptimizerPlugin}{GatherStatistics};
  } else {
    _writeDebug("found compressed css in cache at $cacheFileName");
  }

  my $classes = join(" ", sort keys %classes);

  $text =~ s/\0css\0/<link rel='stylesheet' href='$cacheUrl' class='$classes' media='all' \/>/;
  $text =~ s/\0css\0//g;

  # add http/2 server push to http header
  my $session = $Foswiki::Plugins::SESSION;
  my $response = $session->{response};
  $response->pushHeader('Link', '<'.$cacheUrl.'>; rel=preload; as=style' );

  return $text;
}

###############################
sub _getModificationTime {
  my ($file) = @_;

  return 0 unless $file;

  my @stat = stat($file);
  return $stat[9] || $stat[10] || 0;
}

###############################
sub _gatherCssUrls {
  my ($this, $type, $data) = @_;

  # link tag
  if ($type eq 'link') {
    my $excludePattern = $Foswiki::cfg{PageOptimizerPlugin}{ExcludeCss};
    return if defined($excludePattern) && $data =~ /$excludePattern/;

    #_writeDebug("found url $data in link tag");
    push @{$this->{_cssUrls}}, $data;
    return "\0css\0";
  }

  # style block
  while ($data =~ s/\@import +url\(["']?(.*?)["']?\);//) {
    push @{$this->{_cssUrls}}, $1;
    #_writeDebug("found url $1 in style block");
  }

  # test for an empty style block
  if ($data =~ /^\s*$/s) {
    return "\0css\0";
  }

  # return the rest of the style block
  return "\0css\0<style>$data</style>";
}

###############################
sub parseStylesheet {
  my ($this, $url, $baseUrl) = @_;

  $baseUrl ||= $url;
  $baseUrl =~ s/\?.*?$//;

  my $fileName = _url2FileName($url);

  #_writeDebug("baseUrl=$baseUrl");
  #_writeDebug("fileName=$fileName");

  my $data = '';

  if (-f $fileName) {
    $data = Foswiki::Func::readFile($fileName);

    $data =~ s/url\(["']?(.*?)["']?\)/"url("._rewriteUrl($1, $baseUrl).")"/ge;
    $data =~ s/\@import +url\(["']?(.*?)["']?\);/$this->parseStylesheet($1)/ge;

  } else {
    print STDERR "woops file $fileName does not exist for url $url\n";
  }

  return $data;
}

###############################
sub purgeCache {
  my $this = shift;

  opendir(my $dh, $this->{cacheDir});

  my @files = map { Foswiki::Sandbox::normalizeFileName($this->{cacheDir} . $_) } grep { !/^(\.|README)/ } readdir $dh;
  closedir $dh;

  _writeDebug("cleaning up ".scalar(@files)." files");
  unlink @files;

  return;
}

###############################
sub getCacheEntry {
  my ($this, $type, $urls) = @_;

  my $fileName = Digest::MD5::md5_hex(@$urls) . '.' . $type;

  return ($this->{cacheDir} . $fileName, $this->{cachePath} . $fileName);
}

###############################################################################
# static
sub _writeDebug {
  return unless TRACE;
  print STDERR "- PageOptimizerPlugin - " . $_[0] . "\n";
}


###############################
# static
sub _url2FileName {
  my $url = shift;

  my $fileName = $url;
  $fileName =~ s/$Foswiki::cfg{PubUrlPath}/$Foswiki::cfg{PubDir}/;
  $fileName =~ s/^$Foswiki::cfg{DefaultUrlHost}//;
  $fileName =~ s/\?.*$//;

  return $fileName;
}

###############################
# static
sub _rewriteUrl {
  my ($url, $baseUrl) = @_;

  return $url if $url =~ /^(data|https?):/;

  #_writeDebug("rewriteUrl($url, $baseUrl)");

  my $uri = URI->new($url);
  $url = $uri->abs($baseUrl);

  #_writeDebug("... url=$url");

  return $url;
}


1;
