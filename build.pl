#! /usr/bin/perl -w

package main;

use Template;
use strict;
use Cwd;
use FindBin qw($Bin);
use lib "$Bin/perl";

use vars qw( @LANG %COMPRESS  $RUN_YUIC_JS $RUN_YUIC_CSS @PROCESS @PROCESS_APACHE $VARS $INSTALL  %mtime_cache);
use Getopt::Long;
use IO::File;
use Digest::MD5 qw(md5 md5_hex);
use POSIX qw(strftime);
use Template::Provider;
use Template::Provider::Locale;
use Template::Constants qw(:debug);
use Template::Plugin::GT;
use Parallel::ForkManager;
use FSi18n::PO;
use FSi18n;
use FSi18n::MultipleRead;

use strict;

@LANG = qw( en-us fr zh-cn cs de hu-hu  nb-no sv pt-br ja-jp ru nl hr );


chdir $Bin or die "Could not chdir $Bin : $!";

$| = 1;

my ( $usage, %argv, %input ) = "";

%input = (
           "debug"     => "Produce debug output (no compression)",
           "install"   => "put files in install directory instead of compile directory",
           "config=s"  => "config file (default: config.inc + config.local)",
           "lang=s"    => "build just one langauge (default: all known)",
           "type=s"    => "build just one type of file (default: all types; options: php html js)",
           "verbose"   => "be chatty about what's going on",
           "maxjobs=i" => "max jobs to run in parallel",
           "h|help"    => "show option help"
         );

my $result = GetOptions( \%argv, keys %input );
$argv{"v"} ||= $argv{"n"};
$argv{"maxjobs"} ||= 0;
$argv{"maxjobs"} = 0 if (defined &DB::DB) ;
if ( ( !$result ) || ( $argv{h} ) ) {
    &showOptionsHelp;
    exit 0;
}

$argv{"config"} ||= "./config.inc";

@LANG = split( /[\s,]+/, $argv{"lang"} ) if ( $argv{"lang"} );

require( $argv{config} );
require( $argv{config} . ".local" ) if ( -f ( $argv{config} . ".local" ) );

$VARS->{"subdomain"} ||= $VARS->{"domain"};    # When generating hostnames, use this specific domain instead.  Defaults to just the domain name.

get_svn();

$VARS->{"version"} = $VARS->{"svn_Revision"} . "-" . time;

$VARS->{"AddLanguage"} = get_addlanguage(@LANG);

# Text portion is seperate.

@PROCESS = (
    [ "js",   "index.js" ],
    [ "css",  "index.css" ],
    [ "html", "index.html" ],
    [ "html", "neg.html" ],

    [ "html", "faq_helpdesk.html" ],
    [ "html", "broken.html" ],
    [ "html", "faq_disable.html" ],
    [ "html", "version.html" ],
    [ "html", "faq.html" ],
    [ "html", "stats.html" ],
    [ "html", "mission.html" ],
    [ "html", "mirrors.html" ],
    [ "html", "mirrorstats.html" ],
    [ "html", "source.html" ],
    [ "html", "6to4.html" ],
    [ "html", "faq_6to4.html" ],
    [ "html", "faq_ipv4_only.html" ],
    [ "html", "faq_no_ipv6.html" ],
    [ "html", "faq_teredo_minimum.html" ],
    [ "html", "faq_teredo.html" ],
    [ "html", "faq_v6ns_bad.html" ],
    [ "html", "faq_broken_aaaa.html" ],
    [ "html", "faq_firefox_plugins.html" ],
    [ "html", "faq_browser_plugins.html" ],
    [ "html", "simple_test.html" ],
    [ "html", "faq_whyipv6.html" ],
    [ "html", "faq_pmtud.html" ],
    [ "html", "attributions.html" ],
    [ "html", "faq_buggydns1.html" ],
    [ "html", "faq_avoids_ipv6.html" ],
    [ "html", "faq_tunnel.html" ],
    [ "html", "faq_tunnel_6rd.html" ],
    [ "html", "nat.html" ],
    [ "php",  "common.php" ],
    [ "php",  "comment.php" ],
    [ "php",  "survey.php" ],
    [ "php",  "errors.php" ],

           );

@PROCESS_APACHE = (
                    [ "dot.htaccess",             ".htaccess" ],
                    [ "ip.htaccess",              "ip/.htaccess" ],
                    [ "images.htaccess",          "images/.htaccess" ],
                    [ "images-nc.htaccess",       "images-nc/.htaccess" ],
                    [ "vhost-short.conf.example", "vhost-short.conf.example" ],
                    [ "vhost-long.conf.example",  "vhost-long.conf.example" ],
                    [ "config.js.example",        "config.js.example" ],
                    [ "private.js.example",       "private.js.example" ],
                  );

# create Template object

my @errors;

my $pm = new Parallel::ForkManager( $argv{"maxjobs"} );

$pm->run_on_finish(
    sub {
        my ( $pid, $exit_code, $ident ) = @_;

#                print "** $ident just got out of the pool " . "with PID $pid and exit code: $exit_code\n";
        push( @errors, $ident ) if ($exit_code);
    }
);


sub run_lang  {
  my $lang = shift;
    my $pid = $pm->start($lang) and return;

#    if ( system( "./build-text.pl", $lang ) != 0 ) {
#        die "failed to run .built-text.pl $lang";
#    }

    # TODO either start new POT files
    # or read PO files (in order of least specific to most specific)

    my $i18n;
    print "Preparing POT for $lang\n";
        
    if ( $lang eq "pot" ) {
        # Create a new pot.
        $i18n = new FSi18n( lang => $lang );
        $i18n->filename("falling-sky.pot");

        # $i18n->read_file();  # Do we have an existing file?  # You know, I don't care.
        my $poheader = $i18n->poheader();
        $i18n->add( "", undef,$poheader );
    } else {
        $i18n = new FSi18n::MultipleRead("falling-sky.pot",$lang );
        die "unable to find any files for $lang" unless ($i18n);
    }

    foreach my $p (@PROCESS) {
        process( $p, $lang, $i18n );
    }


        $i18n->write_file();
       

    $pm->finish();
}

# Always run "pot". With force.
{ 
 local $argv{"force"} = 1;
 run_lang("pot");
}
foreach my $lang (@LANG) {
  run_lang($lang) unless ($lang eq "pot");
} ## end foreach my $lang (@LANG)



$pm->wait_all_children;
die "Errors with --lang value(s) @errors" if (@errors);

foreach my $p (@PROCESS_APACHE) {
    process_apache( $p, "en-us" );
}

fixup_apache( "$INSTALL/.htaccess", "$INSTALL/vhost-long.conf.example" );
system( "rsync", "-av", "transparent", "$INSTALL" );


sub prepdir_for_file {
    my ($filename) = @_;
    if ( $filename =~ m#^(.*)/[^/]+$# ) {
        system( "mkdir", "-p", $1 ) unless ( -d $1 );
    }
}

sub process {
    my ( $aref, $lang, $i18n ) = @_;
    my ( $type, $name ) = @{$aref};
    return if ( ( $argv{"type"} ) && ( $argv{"type"} ne $type ) );
    my $cwd = cwd;

    my $lname = $name;
    if ( $name =~ /html|js/ ) {
        $lname .= "." . $lang;    # For localized content.
    } else {
        return unless ( $lang =~ /en-us/ );
    }

    print "Processing: $lang\: $type/$name\n";

    my $new_mtime = ( stat("$INSTALL/$lname") )[9];

    prepdir_for_file("$INSTALL/$lname");
    chdir $type or die "Failed to chdir $type : $!";
    my $output;

    my %provider_config = ( INCLUDE_PATH => "." );

    my $locale_handler = Template::Provider::Locale->new( { VARS => $VARS, LOCALE => $lang, VERBOSE => $argv{"verbose"} } );

    my $template_config = {
        LOAD_PERL      => 1,                          # Locally defined plugins
        INTERPOLATE    => 0,                          # expand "$var" in plain text
        EVAL_PERL      => 1,                          # evaluate Perl code blocks
        OUTPUT         => sub { $output = shift; },
        LOAD_TEMPLATES => [$locale_handler],
        POST_CHOMP     => 1,
        PRE_CHOMP      => 1,
        TRIM           => 1,
        RELATIVE       => 1,
        ENCODING       => 'UTF-8',
        FILTERS        => {
                     i18n => [ \&filter_i18n_factory, 1 ]
                   },

#                            DEBUG => DEBUG_ALL,
    };

    my $newest = newest_mtime( $name, $lang );
    if ( $name =~ /(index|version).html/ ) {

#        $DB::single=1;
    }

    if ( ( $name =~ /(index|version).html/ ) ) {

#        $DB::single=1;
        $newest = time();    # Force index.html updates whenever we see prior items have built
    }

#    if ( !$argv{"force"} ) {
#        if ( ($newest) && ($new_mtime) ) {
#            if ( $newest <= $new_mtime ) {
#                chdir $cwd or die "Failed to return to $cwd: $!";
#                return;
#            }
#        }
#    }

    print "Compiling: $type/$lname\n" if ( $argv{"debug"} );

    $VARS->{i18n} = $i18n;
    $VARS->{"date_utc"} = strftime( '%d-%b-%Y', gmtime time );
    $VARS->{"compiled"} = scalar localtime time;
    $VARS->{"lang"}     = $lang;

    # In HTML, the lang code should be xx-YY
    $VARS->{"langUC"} = $lang;
    $VARS->{"langUC"} =~ s/(-[a-z]+)/uc $1/ge;

    my $template = Template->new($template_config) or die "Could not create template object";
    my $success = $template->process( $name, $VARS ) || die( "crap!" . $template->error() );

#    if ($output =~ /\[%/) {
#      $template_process(\$output,$VARS);
#    }

    # We now have $output - we need to return back to the $cwd
    # so any relative path names are still correct
    chdir $cwd or die "Could not return to $cwd  : $!";

    # Now save $output
    mkdir $INSTALL unless ( -d $INSTALL );
    die "Missing directory: $INSTALL" unless ( -d $INSTALL );

    if ( $lang ne "pot" ) {
    $DB::single=1;
        our_save( "$INSTALL/$lname", $output );
        our_yui( "$INSTALL/$lname", $type );
        our_gzip("$INSTALL/$lname");
    }
} ## end sub process

sub process_apache {
    my ( $aref, $lang )  = @_;
    my ( $name, $lname ) = @{$aref};
    my $type = "apache";

    my $cwd = cwd;
    print "Processing: $name -> $lname\n";

    my $new_mtime = ( stat("$INSTALL/$lname") )[9];

    prepdir_for_file("$INSTALL/$lname");
    chdir $type or die "Failed to chdir $type : $!";
    my $output;

    my %provider_config = ( INCLUDE_PATH => "." );

    my $locale_handler = Template::Provider::Locale->new( { VARS => $VARS, LOCALE => $lang, VERBOSE => $argv{"verbose"} } );

    my $template_config = {
        LOAD_PERL      => 1,                          # Locally defined plugins
        INTERPOLATE    => 0,                          # expand "$var" in plain text
        EVAL_PERL      => 1,                          # evaluate Perl code blocks
        OUTPUT         => sub { $output = shift; },
        LOAD_TEMPLATES => [$locale_handler],
        POST_CHOMP     => 0,
        PRE_CHOMP      => 0,
        TRIM           => 0,

#                            DEBUG => DEBUG_ALL,
                          };

    print "Compiling: $type/$lname\n" if ( $argv{"debug"} );

    $VARS->{"date_utc"} = strftime( '%d-%b-%Y', gmtime time );
    $VARS->{"compiled"} = scalar localtime time;

    my $template = Template->new($template_config) or die "Could not create template object";
    my $success = $template->process( $name, $VARS ) || die( "crap!" . $template->error() );

    # We now have $output - we need to return back to the $cwd
    # so any relative path names are still correct
    chdir $cwd or die "Could not return to $cwd  : $!";

    # Now save $output
    mkdir $INSTALL unless ( -d $INSTALL );
    die "Missing directory: $INSTALL" unless ( -d $INSTALL );

    # Debug mode: Don't do YUI
    our_save( "$INSTALL/$lname", $output );
} ## end sub process_apache

sub fixup_apache {
    my (@files) = @_;
    my ($first) = @files;
    my $ctx     = Digest::MD5->new;
    my $digest;

    $digest = $ctx->hexdigest;
    print "digest 1 $digest\n";
    my $file = IO::File->new("<$first") or die "could not open $first : $!";
    while (<$file>) {

        # Clean up some stuff, so we don't make changes for things like comments and whitespace
        s/#.*$//;
        s/^\s+//;
        s/\s+$//;
        s/\s+/ /g;
        next unless (/./);
        $ctx->add($_) unless (/BUILDMD5HASH/);    # Ignore the lines that might be volatile
    }
    $digest = join( "-", $VARS->{"svn_Revision"}, $ctx->hexdigest );
    print "digest 2 $digest\n";
    system( "perl", "-pi", "-e", "s/BUILDMD5HASH/$digest/g", @files );
} ## end sub fixup_apache

sub our_yui {
    my ( $file, $type ) = @_;

    my $run = $COMPRESS{$type} if ( exists $COMPRESS{$type} );
    return unless ($run);
    return if ( $argv{"debug"} );

    my $cwd = cwd;
    $file =~ s#$INSTALL/*##;
    chdir $INSTALL or die;

    our_rename( "$file", "$file.orig" );

    $run =~ s#\[INPUT]#$file.orig#g;
    $run =~ s#\[OUTPUT]#$file#g;
    print "% $run\n" if ( $argv{"debug"} );
    my $rc = system($run);
    if ( ($rc) || ( !-f $file ) || ( !-s $file ) ) {

        if ( ( $rc == 256 ) && ( $run =~ /tidy/ ) ) {

            # ignore
        } else {

            # failed!
            die "Failed to run: $run  (RC=$rc)\n";
        }
    }
    chdir $cwd;    # Restore directory

} ## end sub our_yui

sub our_save {
    my ( $filename, $buffer ) = @_;
    open( SAVEFILE, ">$filename.new" ) or die "Failed to create $filename.new: $!";
#    binmode SAVEFILE, ":utf8";
    print SAVEFILE $buffer;
    close SAVEFILE;
    our_rename( "$filename.new", "$filename" );
}

sub our_rename {
    my ( $old, $new ) = @_;
    print "% mv $old $new\n" if ( $argv{"debug"} );
    rename( $old, $new ) or die "Failed to rename $old $new : $!";
}

sub our_gzip {
    my ($file) = @_;
    my $newname = $file;
    $newname =~ s#(\.(html|js|css))#${1}.gz#;
    return if ( $file eq $newname );

    my $cmd = "cat $file | gzip -f -9 -Sgz > $newname";

    if ( $file =~ /html/ ) {
        $cmd = "cat $file | perl -pi -e 's#/index.js#/index.js.gz#' |  gzip -f -9 -Sgz > $newname";
    }

    print "% $cmd\n" if ( $argv{"debug"} );
    my $rc = system($cmd);
    if ($rc) {

        # failed!
        die "Failed to run: $cmd\n";
    }
} ## end sub our_gzip

sub showOptionsHelp {
    my ( $left, $right, $a, $b, $key );
    my (@array);
    print "Usage: $0 [options] $usage\n";
    print "where options can be:\n";
    foreach $key ( sort keys(%input) ) {
        ( $left, $right ) = split( /[=:]/, $key );
        ( $a,    $b )     = split( /\|/,   $left );
        if ($b) {
            $left = "-$a --$b";
        } else {
            $left = "   --$a";
        }
        $left = substr( "$left" . ( ' ' x 20 ), 0, 20 );
        push( @array, "$left $input{$key}\n" );
    }
    print sort @array;
}

sub newest_mtime {
    my ( $file, $lang ) = @_;
    return unless ($file);

    # If this is a localizable file... localize it.
    if ( $file =~ /\.(html|js|css)/ ) {
        if ( -f "$file\.$lang" ) {
            $file = "$file\.$lang";
        } elsif ( -f "$file.en-us" ) {
            $file = "$file\.en-us";
        }
    }

    my $key = cwd . "/" . $file;

    if ( !exists $mtime_cache{$key} ) {

        my $mtime ||= ( stat($file) )[9];

        # Are there any dependencies?
        my $fh = IO::File->new("<$file");
        if ($fh) {
            while (<$fh>) {
                my (@includes) = ( $_ =~ m#\[\%\s+PROCESS\s+"(.*?)"#g );
                foreach my $inc (@includes) {
                    print "  (scanning $inc)\n" if ( $argv{"debug"} );
                    my $m = newest_mtime( $inc, $lang );
                    if ( ($m) && ( $m > $mtime ) ) {
                        $mtime = $m;
                    }
                }
            }
            close $fh;
        }
        $mtime_cache{$key} = $mtime;
    } ## end if ( !exists $mtime_cache{$key} )
    return $mtime_cache{$key};
} ## end sub newest_mtime

sub my_process {
    my ( $context, $file ) = @_;

}

sub get_svn {
    my @svn = `TZ=UTC svn info`;
    foreach my $svn ( grep( /./, @svn ) ) {
        chomp $svn;
        my ( $a, $b ) = split( /: /, $svn );
        $a =~ s/ /_/g;
        $VARS->{ "svn_" . $a } = $b;
    }
}

sub get_addlanguage {
    my (@list) = @_;
    my ($string);
    foreach my $lang (@list) {
        next if ( $lang eq "pot" );
        $string .= "AddLanguage $lang .$lang\n";
    }
    return $string;
}

sub filter_i18n_factory {
    my ( $context, $arg1 ) = @_;

    # What file did we find this in? We'll possibly want to make a note of it.

    my $component_name = $context->stash->get("component")->name;
    my $modtime        = $context->stash->get("component")->modtime;
    my $lang           = $context->stash->get("lang");
    my $langUC         = $context->stash->get("langUC");
    my $i18n           = $context->stash->get("i18n");

    if ( $lang eq "pot" ) {
        return sub {
            my $text = shift;
            my $lo   = FSi18n::PO->new();    # new() does not (today) actually take the msgid, reference args
            
            $text =~ s/^\s+//;
            $text =~ s/\s+/ /g;  # Canonicalize any size whitespace to single space
            $text =~ s/\s+$//;
            $lo->msgid($text);
            $lo->msgstr("");
            $lo->reference($component_name);
            $lo->msgctxt($arg1) if ($arg1);
            $i18n->add( $text, $arg1,$lo );
            return $text;
        };
    } else {

        #TODO  Actually do .po lookups
        return sub {
            my $text = shift;
            $text =~ s/^\s+//;
            $text =~ s/\s+/ /g;  # Canonicalize any size whitespace to single space
            $text =~ s/\s+$//;
            my $found = $i18n->find_text($text,$arg1);
            return $found;
        };
    }

} ## end sub filter_i18n_factory