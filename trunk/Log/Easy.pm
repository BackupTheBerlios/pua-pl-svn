package Log::Easy;
use strict;
use Data::Dumper;
use IO::File;
use Fcntl qw(:flock);
use Carp qw( cluck confess );
use Getopt::Long;

use Exporter;
our ( %EXPORT_TAGS, @ISA, @EXPORT_OK, @EXPORT, $VERSION );
@ISA = qw( Exporter );

$VERSION = '0.01_08';

our ($FILTER_REGEX, $NOT_FILTER_REGEX, $FILTER_ALL_REGEX, $MATCH_LOG_LEVEL_REGEX, $FILTER, $NOT_FILTER, $CNT );

our ( $DUMPER, $log_level, $log );
our ( $ll, $all, $lll, $cll, $ell, $wll, $nll, $ill, $dll, $tll, $sll, $mll );

# we don't normally want a stack trace on every log call
our $STACK_TRACE = $ENV{STACK_TRACE} || 0;
# enable on any particular call with: $log->write({st=>1},$lll, ':');
# enable on all calls with: $log->stack_trace( 1 );

# if we have big warngings set to true for any particular log level then we'll issue a perl 'warn'ing
our %BIG_WARN_DEFAULTS = qw( WARN 0 ERROR 1 CRIT 1 );
our %BIG_WARN_ON       = map { $_ => ( defined $ENV{"BIG_WARN_ON_$_"} ? $ENV{"BIG_WARN_ON_$_"} :( $BIG_WARN_DEFAULTS{$_} || 0 )); }  keys %BIG_WARN_DEFAULTS;

if ( $ENV{LOG_USE_CARP} and $ENV{LOG_USE_CARP} eq 'YES'  ) {
  # big ugly stack traces when we encounter a 'warn' or a 'die'
  $SIG{__WARN__} = \&cluck;
  $SIG{__DIE__}  = \&confess;
}
# DEFAULT MESSAGE QUIET
use constant LOG_LEVELS =>  qw( ALWAYS LOUD CLEAN
                                EMERG ALERT CRIT ERROR WARN NOTICE INFO DEBUG
                                TRACE SPEW );

# if any $log->write(...)'s are in the calling code, and the log level is specified with one of the followin prepended with a '$'
use constant DEFAULT_FILTER =>  qw( all mll lll qll cll ell wll nll ill dll tll sll );


%EXPORT_TAGS = (
                # available constants for log level text names, these will never be filtered nor will warnings about them ever be made
                # basically, these are for production level logging (as opposed to the 'shorthand' log levels below in "log_level_[not_]filtered"
                # as such they can still be used to put the program in DEBUG mode (etc), but for more formalized debugging
                log_level              => [ LOG_LEVELS() ],
                # global logging object
                log                    => [ qw( $log )   ],
                # convenient log level aliases that WILL BE FILTERED if appropriate (MUST begin with a $ [eg regular SCALAR variable]
                log_level_filtered     => [ map { "\$$_" }  DEFAULT_FILTER() ],
                # same as above, but without '$', these will not be filtered, but if $ENV{WARN_FILTER} is set, warnings about unfiltered log messages will show up
                # this is useful for debugging when you may want a particular message to be displayed (simply delete the '$')
                log_level_not_filtered => [                 DEFAULT_FILTER() ],
                # these are utility methods for output formatting
                misc      => [ qw(space pad dump _caller get_options usage) ],
               );

$EXPORT_TAGS{all} = [ map {@{$_}} values %EXPORT_TAGS ];
$EXPORT_TAGS{initialize} = [ @{$EXPORT_TAGS{log_level}} ];
@EXPORT_OK = @{$EXPORT_TAGS{'all'}};
@EXPORT = ();

# the following two sets of exported variables/subs are for development debugging purposes and are
# filtered out at compile time, unless $ENV{LOG_FILTER} is appropriately set. I'm thinking that since
# these are for development debugging that they should maybe have some different significance when
# it comes to descriptive output. Currently all log messages output the &{$log->{prefix}}(). Perhaps
# we should use a bitmask to determine whether or not a log should be output and additionally what
# kind of prefix it has. This would allow these to mimic the "production" log levels (in value)
# while also allowing us to have more descriptive prefix (caller, etc...) when they are used for
# development debugging

( $ll, $all, $lll, $cll, $ell, $wll, $nll, $ill, $dll, $tll, $sll, $mll)
  = qw(DEFAULT ALWAYS LOUD CLEAN ERROR WARN NOTICE INFO DEBUG TRACE SPEW MESSAGE );

# these were(are?) actually apache constants for logging levels I think anything that gets in that
# is preceded with a '_' gets [0] (numerical value) these return the uppercase(?) version of
# themselves

use constant LOG_CODE   => { ALWAYS  => 0x000E,
                             STDERR  => 0x000E,
                             STDOUT  => 0x000E,
                             MESSAGE => 0x000D,
                             LOUD    => 0x000C,
                             EMERG   => 0x000B,
                             ALERT   => 0x000A,
                             CRIT    => 0x0009,
                             ERROR   => 0x0008,
                             WARN    => 0x0007,
                             CLEAN   => 0x0006,
                             NOTICE  => 0x0005,
                             INFO    => 0x0004,
                             DEBUG   => 0x0003,
                             TRACE   => 0x0002,
                             SPEW    => 0x0001,
                             QUIET   => 0x0000,
                             DEFAULT => 0x0003,# set equal to DEBUG
                           };

use constant MESSAGE => 'MESSAGE'; # this will send an email to the appointed person
use constant ALWAYS  => 'ALWAYS';
use constant DEFAULT => 'DEFAULT';
use constant LOUD    => 'LOUD';
use constant CLEAN   => 'CLEAN';
use constant QUIET   => 'QUIET';
use constant EMERG   => 'EMERG';
use constant ALERT   => 'ALERT';
use constant CRIT    => 'CRIT';
use constant ERROR   => 'ERROR';
use constant WARN    => 'WARN';
use constant NOTICE  => 'NOTICE';
use constant INFO    => 'INFO';
use constant DEBUG   => 'DEBUG';
use constant TRACE   => 'TRACE';
use constant SPEW    => 'SPEW';
# translate between our more expanded selection of logging levels to what apache understands
our %APACHE_LEVELS = ( DEFAULT => INFO,
                       TRACE   => DEBUG,
                       SPEW    => DEBUG,
                       DEBUG   => DEBUG,
                       INFO    => INFO,
                       WARN    => WARN,
                       NOTICE  => NOTICE,
                       CRIT    => CRIT,
                       ERROR   => ERROR,
                       ALERT   => ALERT,
                       EMERG   => EMERG,
                       LOUD    => ERROR,
                       CLEAN   => ERROR,
                       QUIET   => DEBUG,
                       ALWAYS  => ERROR,
                     );


# the following, when used as log levels in code calling this package with qw(:all)
# these may not be worth the clutter
# I have also made identically named scalars which if used will  cause the log messages to be filtered out
# WARNING: without the `$' the log message WILL NOT be filtered out!
use constant  ll  => DEFAULT;
use constant  all => ALWAYS;
use constant  lll => LOUD;
use constant  cll => CLEAN;
use constant  qll => QUIET;
use constant  ell => ERROR;
use constant  wll => WARN;
use constant  nll => NOTICE;
use constant  ill => INFO;
use constant  dll => DEBUG;
use constant  tll => TRACE;
use constant  sll => SPEW;

BEGIN { 
  $ENV{DEBUG_FILTER} = exists $ENV{DEBUG_FILTER} ? $ENV{DEBUG_FILTER} : 0;
  $ENV{LOG_FILTER} ||= $ENV{FILTER} ||= 'ON';
  unless ( defined $FILTER_REGEX ) {
    my $FILTER;
    if( $ENV{LOG_FILTER} =~ /^off$/i ) {
      print STDERR "FILTER: IS OFF\n" if $ENV{DEBUG_FILTER};
      $FILTER = [];
      $NOT_FILTER = [ DEFAULT_FILTER ];
    } elsif( $ENV{LOG_FILTER} =~ /^(on|\d+)$/i ) {
      print STDERR "FILTER: IS ON\n" if $ENV{DEBUG_FILTER};
      $FILTER = [ DEFAULT_FILTER ];
      $NOT_FILTER = [];
    } else {
      print STDERR "FILTER: IS SPECIAL FILTER=$ENV{LOG_FILTER}\n" if $ENV{DEBUG_FILTER};
      my %not_filter = ();
      my %filter = ();
      foreach my $piece ( split( /:/, $ENV{LOG_FILTER} )) {
        if ( $piece =~ /^\!/ ) {
            $piece =~ s/^\!//;
              $not_filter{$piece} = $piece;
          } else {
              $filter{$piece}     = $piece;
              }
      }
      print STDERR "\%filter: ", join( ', ', keys %filter ), "\n"  if $ENV{DEBUG_FILTER};
      print STDERR "\%not_filter: ", join( ', ', keys %not_filter ), "\n" if $ENV{DEBUG_FILTER};
      if ( %filter ) {
        $FILTER = [ keys %filter ];
        $NOT_FILTER = [];
      } else {
        $FILTER = [ map { $not_filter{$_} ? () : $_; } ( DEFAULT_FILTER ) ];
        $NOT_FILTER = [ map { $not_filter{$_} ? $_ : (); } ( DEFAULT_FILTER ) ];
      }
    }
    print STDERR "FILTER: ", join('|', @$FILTER ), "\n" if $ENV{DEBUG_FILTER};
    $FILTER_REGEX = '\$log->write\(.*?\$(' . join('|', @$FILTER) . '),.*?\);';
    print STDERR "FILTER_REGEX     : $FILTER_REGEX\n"  if $ENV{DEBUG_FILTER};
    print STDERR "NOT_FILTER: ", join('|', @$NOT_FILTER ), "\n" if $ENV{DEBUG_FILTER};
    $NOT_FILTER_REGEX = '\$log->write\(.*?\$(' . join('|', @$NOT_FILTER) . ')(\,|\ \,|\,\ ).*?\);';
    print STDERR "NOT_FILTER_REGEX     : $NOT_FILTER_REGEX\n"  if $ENV{DEBUG_FILTER};
  }

  unless ( defined $FILTER_ALL_REGEX ) {
    my $FILTER = [ DEFAULT_FILTER ];
    $FILTER_ALL_REGEX = '(\$log->write\(.*?)(' . join('|', @$FILTER) . ')(\,|\ \,|\,\ )(.*?\);)';
    print STDERR "FILTER_ALL_REGEX: $FILTER_ALL_REGEX\n"  if $ENV{DEBUG_FILTER};
  }

  unless ( defined $MATCH_LOG_LEVEL_REGEX ) {
    my $FILTER = [ LOG_LEVELS() ];
    $MATCH_LOG_LEVEL_REGEX = '(\$log->write\(.*?)(' . join('|', @$FILTER) . ')(\,|\ \,|\,\ )(.*?\);)';
    print STDERR "MATCH_LOG_LEVEL_REGEX: $MATCH_LOG_LEVEL_REGEX\n"  if $ENV{DEBUG_FILTER};
  }
}

use Filter::Simple;
our $replace = '1;';
FILTER { # this filters out unwanted log messages from source code BEFORE COMPILATION
  # proves to be a great boon to performance
  $CNT++;
  ##print STDERR __LINE__, ": \$ENV{LOG_FILTER} = $ENV{LOG_FILTER}\n";
  return if ( $ENV{LOG_FILTER} and $ENV{LOG_FILTER} =~ /^(OFF|)$/i);
  #return if ( $before =~ /\s*/s );
  my @caller = caller(1);
#  print STDERR "CALLER: \n\t", join("\t\n", map { (defined $_ ? $_ : '')} @caller ), "\n";
  my $package = $caller[0];
  my $file    = $caller[1];
  my $calline = $caller[2];
  #  print STDERR "CALLING PACKAGE: $package\n";
  #print STDERR "." if $ENV{DEBUG_FILTER};
  $ENV{DEBUG_FILTER}||=0;
  my $not_filtered = $ENV{DEBUG_FILTER} ? "' ### LOG MESSAGE UN-FILTERABLE ### '" : '';
  my @match;
  my @before = split("\n", $_ );
  my @after = ();
  my $linenum = $calline;
  my $totallines = scalar @before;
  my $filtered = '';
  my $filtered_status = '';
  foreach my $line ( @before ) {
    $linenum++;
    $filtered = '';
    $filtered_status = '';
    if ( $line =~ /$MATCH_LOG_LEVEL_REGEX/ ) {
      $filtered_status = 'UNTOUCHED';
    } elsif ( $line =~ s/($FILTER_REGEX)/$replace/g ) {
      $filtered_status = 'FILTERED ';
      $filtered   = $1;
    } elsif ( $line =~ /$NOT_FILTER_REGEX/g ) {
      $filtered_status = 'NOT-FILTERED';
    } elsif ( $line =~ /$FILTER_ALL_REGEX/ ) { #and $line !~ /$not_filtered/ ) {
      print STDERR  "WARNING DEBUG LOG MESSAGE NOT REMOVED: $file : $linenum: $line \n" if ($ENV{WARN_FILTER} or $ENV{DEBUG_FILTER});
      $line =~ s/$FILTER_ALL_REGEX/${1}${2},${not_filtered}${3}${4}/;
      $filtered_status = 'CHANGED';
    }
    push @after, $line;
    print STDERR pad(++$ENV{GLOBAL_LINES_FILTER_EXAMINED},5), ' |', pad($linenum,5), '/', space($totallines,5),': ', space($filtered_status, undef, '.'), '| ', $line, "\n" if ($ENV{DEBUG_FILTER} > 3);
    print STDERR pad('',5, 'x'), 'xx', pad('',5,'x'), 'x', space('',5,'x'),'::::: ', "FORMER CONTENTS: $filtered", "\n" if ( $ENV{DEBUG_FILTER} > 3 and $filtered );
    
  }
  $_ = join( "\n", @after) . "\n";
};

my $default_log_level = 'NOTICE';
$log_level = $ENV{LOG_LEVEL} ||= ( [ map {$ENV{$_}?$_:()}(@{$EXPORT_TAGS{log_level}}) ]->[0] || $default_log_level );
# message terminator (sometimes we DON'T want newlines!)
our $n;
sub n              { exists $_[1] ? $_[0]->{ n              } = $_[1] : $_[0]->{ n             }; }
sub log            { exists $_[1] ? $_[0]->{ log            } = $_[1] : $_[0]->{ log           }; }
sub log_file       { exists $_[1] ? $_[0]->{ log_file       } = $_[1] : $_[0]->{ log_file      }; }
sub log_level      { exists $_[1] ? $_[0]->{ log_level      } = $_[1] : $_[0]->{ log_level     }; }
sub dump_refs      { exists $_[1] ? $_[0]->{ dump_refs      } = $_[1] : $_[0]->{ dump_refs     }; }
sub handle_fatals  { exists $_[1] ? $_[0]->{ handle_fatals  } = $_[1] : $_[0]->{ handle_fatals }; }
sub exclusive      { exists $_[1] ? $_[0]->{ exclusive      } = $_[1] : $_[0]->{ exclusive     }; }
sub stack_trace    { exists $_[1] ? $_[0]->{ stack_trace    } = $_[1] : $_[0]->{ stack_trace   }; }
sub email          { exists $_[1] ? $_[0]->{ email          } = $_[1] : $_[0]->{ email         }; }
sub prefix         { exists $_[1] ? $_[0]->{ prefix         } = $_[1] : $_[0]->{ prefix        }; }
sub terse          { exists $_[1] ? $_[0]->{ terse          } = $_[1] : $_[0]->{ terse         }; }

sub clone {
  my $self = shift;
  my $VAR1 = $self->dump( @_ );
  my $clone = eval $VAR1;
  $clone->{prefix} = $self->{prefix} if ( UNIVERSAL::isa( $clone, __PACKAGE__ ) and ref $self->{prefix} eq 'CODE' );
  return $clone;
}

our $default_handle_fatals = 1;
our $default_fh = 'STDOUT';
our %init = ( log_file       => $ENV{LOG_FILE} || $default_fh ,
              log_level      => $log_level,
              dump_refs      => defined $ENV{LOG_DUMP_REFS} ? $ENV{LOG_DUMP_REFS} : 1 ,
              handle_fatals  => defined $ENV{LOG_HANDLE_FATALS} ? $ENV{LOG_HANDLE_FATALS} : $default_handle_fatals,
              exclusive      => $ENV{LOG_EXCLUSIVE} || '',
              prefix         => \&_default_prefix,
            );

$log = __PACKAGE__->new();
sub new {
  my $self = shift;
  my $class = ref $self || $self;
  $self = bless {}, $class;
  $self->init( @_ );
  return $self;
}

sub init {
  my $self = shift;
  my $init = shift || \%init;
  if ( ref $init eq 'HASH' ) {
    while ( my ( $key, $value ) = each %$init ) {
      next unless $key;
      #$self->{$key} = $value;
      $self->$key( $value );
    }
  }
  return $self;
};

sub space {
  # this is a stupid little subroutine to nicely display stuff
  # could probably use a format specifier or sprintf better, but what the hell
  # I mostly use this for aligning output nicely
  my $piece     = shift;
  my $max       = shift || 27;
  my $separator = shift || ' ';
  my $lp = defined $piece ? length $piece : 0;
  my $ls = length $separator;
  my $multiplier = $lp < $max ? int (( $max - $lp )/$ls ) : 1;
  my $return = $piece . ( $separator x $multiplier );
  my $lr = length $return;
  $lr < $max ? ( $return = $return . ( ' ' x ( $max - $lr ))) : ();
  return $return;
}

sub pad {
  my $piece     = shift;
  my $max       = shift || 27;
  my $separator = shift;
  defined $separator or $separator = ' ';
  length $separator or $separator = ' ';
  my $lp = defined $piece ? length $piece : 0;
  my $ls = length $separator;
  my $multiplier = $lp < $max ? int (( $max - $lp )/$ls ) : 0;
  my $return = ( $separator x $multiplier ) . $piece;
  my $lr = length $return;
  #$log->write($lll, "$max:$lr:$piece:") if ( $max != $lr );
  $lr <= $max ? ( $return = ( ' ' x ( $max - $lr )) . $return) : ();
  return $return;
}

sub dump { # maybe change this to take a list of dumpees
  #print STDERR __PACKAGE__, " ", __LINE__, " ", caller(), "\n", join(' XXX ', @_ ), "\n";
  my $DUMP = '';
  my $self = shift;
  my $class = ref $self || $self;
  my ( $dumps, $names );
  my ( $pure, $deep,  $indent, $id, $terse );
  if ( $_[0] and $_[0] =~ /^-/ ) { 
    my $args = { @_ };
    $dumps    = $args->{-d} || $args->{-dump}    || $self;
    $names    = $args->{-n} || $args->{-names}   || undef;
    $dumps  = [ $dumps ] unless ( ref $names eq 'ARRAY' );
    $pure     =                $args->{-pure}    || 0    ;
    $deep     =                $args->{-deep}    || 0    ;
    $indent   = ((defined $args->{-i})? ($args->{-i}) : (defined $args->{-indent} ? $args->{-indent} : 2 ));
    $id       =                $args->{-id}      || 0;
    $terse    =                $args->{-terse}   || 0    ;
  } else {
    $dumps    = shift || $self;
    ref $dumps eq 'ARRAY' or $dumps = [ $dumps ];
    $names    = shift || undef;
    $pure     = shift || 0;
    $deep     = shift || 0;
    $indent   = shift || 2;
    $id       = shift || 0;
    $terse    = shift || 0;
  }
  ( defined $dumps ) && ( ref $dumps eq 'ARRAY' ) || ( $dumps = [ $dumps ] );
  ( defined $names ) && ( ref $names eq 'ARRAY' ) || ( $names = [ $names ] );
  if ( $id ) {
    for( my $i =0; $i <= $#$dumps; $i++ ) {
      my $d = $dumps->[$i];
      my $n = ref $d ? $d : \$d;
      $names->[$i] = $n;
    }
  }
  my $dumper = Data::Dumper->new( $dumps , $names );
  $dumper->Purity  ( $pure   );
  $dumper->Deepcopy( $deep   );
  $dumper->Terse   ( $terse  );
  $dumper->Indent  ( $indent );
  $DUMP = $dumper->Dump();
  return $DUMP
}

sub get_options {
  my $optargs = shift;
  my %GetOptions = map { ("$_$optargs->{$_}[0]" => \$optargs->{$_}[1]) } keys %$optargs;
  $log->write($dll, '%GetOptions: ', \%GetOptions);
  my $opt = GetOptions( %GetOptions );
  $log->write($dll, '$opt: ', $opt);
  
  $log->write($dll, '$optargs: ', $optargs);
  my %options = map { ($_ => $optargs->{$_}[1]) } keys %$optargs;
  $log->write($dll, '%options: ', \%options);
  
  # check that all required options have been provided
  my @missing;
  foreach (keys %$optargs ) {
    if ( $optargs->{$_}[0] =~ /\=/ and not $options{$_} ) {
      push @missing, $_;
    }
  }
  return usage ( $optargs, @missing ) if (scalar @missing);
  return %options;
}

sub usage {
  my $optargs = shift;
  $log->write('STDERR', "Missing required option(s): ( ", join(', ', map { "--$_" } @_ )," )::: \n", join("\\\n" . (' ' x length "usage: $0"),
						   space("usage: $0", ),
						   map { my @opt = ( '--', space($_, 20), space(uc "<$_>", 22));
							 @opt = ( $optargs->{$_}[0] =~ /\=/
								  ? ( ' '  , @opt , ' '    )
								  : ( ' [ ', @opt ,' ] ')
								);
							 join('', @opt);
						       } ( # sort here to make required options come first
							  sort { my ($an, $bn) = ( $optargs->{$a}[0], $optargs->{$b}[0] );
								 my ($av, $bv) = (1, 1);
								 $an =~ /\=/ and $av = 0;
								 $bn =~ /\=/ and $bv = 0;
								 $av <=> $bv
							       } keys %$optargs
							 )));
  exit -1;
}

sub _prepare_message {
  my $self  = shift;
  my $level = shift;
  my $args  = shift;
  my @inmsg = @_;
  my $dump_refs = exists $args->{dump_refs} ? $args->{dump_refs}
    :  exists $self->{dump_refs} ? $self->{dump_refs}
      : $level eq 'SPEW';
  my @outmsg = ();
  my $tmp;
  my ($msg, $d);
 INMSG: while ( @inmsg > 0 ) {
    $tmp = undef;
    $msg = shift @inmsg;
    defined $msg or $msg = 'undef';#'(UNDEFINED ELEMENT IN LOG MESSAGE ARGUMENTS)';
    if (( my $ref = ref $msg ) and $dump_refs ) {
      $d = $self->dump(-d=>[$msg],-n=>["$msg"], -i=>1, -deep => 0 );
      $msg = $d;
    }
    push @outmsg, "$msg";
  }
  # really we should have somethings that checks the %args for ALL of the possible settings
  my $st = $STACK_TRACE;
  $STACK_TRACE = exists $args->{stack_trace} ? $args->{stack_trace}
    : defined $self->{stack_trace}           ? $self->{stack_trace}
      : $STACK_TRACE;

  my $prefix = exists $args->{prefix} ? $args->{prefix}
    : $level =~ /^CLEAN|QUIET$/       ? ''
      : defined $self->{prefix}       ? $self->{prefix}
        : \&_default_prefix;

  ref $prefix eq 'CODE' and $prefix = &$prefix( $level );
  $STACK_TRACE = $st;# restore the previous setting
  unshift @outmsg, $prefix if defined $prefix;
  return @outmsg;
}

*_default_prefix = \&_prefix_dev_long;
sub _prefix_dev_long {
  my $level = shift;
  return '['.join('][',
                  "pid: $$",
                  scalar localtime(),
#		   time(),
                  _caller(3), # we need a 3 here to ignore (skip over) the subroutine calls within the logging module itself
                  uc $level,
                 )."] "
		   . "\n"
		   ;
}

sub _prefix_dev_short {
  my $level = shift;
  return '['.join('][',
                  _caller(3), # we need a 3 here to ignore (skip over) the subroutine calls within the logging module itself
                  uc $level,
                 )."] "
		   . "\n"
		   ;
}

my %level_cache = ();
sub _check_level {
  my $self  = shift;
  my $msg = shift;
  my $args = {};
  my $level = shift @$msg;
  ref $level eq 'HASH'
    and ($args=$level)
      and $level=shift @$msg;
  
  my $log_level = $args->{log_level} ||= $self->{log_level}   || DEFAULT;
  my ( $_level, $_log_level ) = (@{LOG_CODE()}{$level, $log_level});
  #  print STDERR "\nLEVELS: $log_level:$_log_level ... $level:$_level\n" if $self->{EVIL};

  if ( not defined $_level ) {
    unshift @$msg, ( $level = 'DEFAULT' );
    $log->write( ERROR, "Illegal log level '$level' setting it to $level");
    return $self->_check_level( $msg ) unless exists $level_cache{$level};
    $log->write( ERROR, "Illegal log level '$level' trouble setting it to $level");
    return undef;
  }

  return ($level, $_level, $log_level, $_log_level, $args);
}

sub write {
#  print STDERR __PACKAGE__," :: ", join(', ', caller()), "\n";
  my $self  = shift;
  ref $self or $self = $log;
  my @msg = @_;
  my ($level, $_level, $log_level, $_log_level, $args)  = $self->_check_level( \@msg );
  # this needs to be set up to log at any of severa levels which may be set simultaneously
  # eg log at WARN and TRACE
  # log levels should be a list
  # ie @_log_levels rather than $_log_level
  my $return = \@msg;
  my $status = 1;
  if ( my $e = $self->{exclusive} ) {
    $e =~ /$level/
      or $status = 0;# or return join( '', @$return );
  } else {
    $_level >= $_log_level 
      or $status = 0;
      #or return join( '', map { defined $_ ? $_ : 'undef' } @$return );
  }
  if ( $status ) {
    #warn "STATUS: $status ::: $level:$_level ... $log_level:$_log_level";
    @msg = $self->_prepare_message( $level, $args, @msg );
    $n = exists $args->{n} ? $args->{n} : ($self->{n} || "\n");
    $return = $self->_actually_log( %$args, -level => $level, -message => $return );
    
    if ( $level eq CRIT and $self->{handle_fatals} ) {
      if ( my $email = $self->{email} ) {
        # should we send a message to the bloke?
      }
      die "$0: `CRIT'ical error occurred :: $return";
    }
    if ( $level eq MESSAGE  ) {
      if ( my $email = $args->{email} ? $args->{email} : $self->{email} ) {
        # we should send a message to the bloke?
      } else {
        $log->write(ERROR, "No email address specified to send MESSAGE: $return");
      }
    }
    $BIG_WARN_ON{$level} and warn "$level : $return";
    $n = undef;
  }
  ref $return eq 'ARRAY' and $return = join('', map { defined $_ ? $_ : 'undef' } @$return);
  return wantarray ? ( $status, $return ) : $status ;
}
sub _actually_log {
  #print STDERR __PACKAGE__, " ", __LINE__, " ::: OH MY!\n";
  my $self    = shift;
  my $args = { @_ };
  $args->{-terse}   ||= $self->{terse};
  $args->{-level}   ||= INFO;
  $args->{-message} ||= ' - -- NO MESSAGE -- - ';
  my $fh = $self->_fh( %$args ) or warn "No filehandle for `$args->{-level}'";
  #print "MESSAGE: $message\n";
  return _WRITE( %$args, -FH => $fh );
};

#@f{qw(package filename line subroutine hasargs wantarray evaltext is_require hints bitmask )}=caller();
my @showf = qw(package filename line subroutine hasargs wantarray evaltext is_require );
sub _caller {
  my $f = shift || 0;
  my @caller = ();
  if ( $STACK_TRACE ) {
    # I wonder if there is a single call to give me a stack trace like I want, I know Carp will cluck() but why didn't I use that in the first place?
    # did I just do my own for some easier to read formatting?
    my $s = 0;
    my %mes;
    my @mes = ({map{$mes{$_}=!$mes{$_}?length$_:($mes{$_}<length$_)?length$_:$mes{$_};($_=>$_);}@showf});
    my $width = 0;
    my $depth = 0;
    while (1) {
      my %f;
      $depth = $f + ++$s;
      @f{ @showf, qw( hints bitmask )}= caller($depth);
      # this is probably a stupid way to break out of this loop, we basically keep stepping back up the stack until there is nothing left
      last unless join('',map{$f{$_}?$f{$_}:''}(@showf));
      $width=0;
      my $x = 0;
      #push @mes, "$s => \n\t", join("\n\t",map{(space( $_ . "(" . $x++ . ")") . " => " . ($f{$_}?$f{$_}:'undef')) }@showf), "\n";
      foreach (@showf) {$f{$_} ||= 'undef';$mes{$_}=!$mes{$_}?length$f{$_}:($mes{$_}<length$f{$_})?length$f{$_}:$mes{$_};$width+=$mes{$_};}
      $mes[$depth] = \%f;
    }
    my ($c, @c);
    my $sep = '';
    my @m = ( '_' x $width,"\n", join("", "\n", map { if($_){$c=$_;@c=map{(space($c->{$_},$mes{$_}+2,$sep) . ' | ');}@showf;$sep='';(@c,"\n");}else{()}}@mes),'_' x $width,"\n",);
    push @caller, @m;
  }

  # what we want here is the package name, subroutine name and line
  # number where the log call was made AND we want one level further
  # back, giving us the package, subroutine, and line number where the
  # subroutine with the log call was itself called

  #  _WRITE( -message => [ "$f => \n\t", join("\n\t",map{$_?$_:''}@f), "\n" ]);
  # this tells us where the log call was made from
  my @f = caller($f);
  my ( $package, $filename, $line, $subroutine ) = @f;
  #$log->write({prefix=>undef},$lll, '( $package, $filename, $line, $subroutine ) = : ', "( $package, $filename, $line, $subroutine)" );
  # this tells us where the subroutine containing log call was called from
  my @pf = caller($f+1);
  my ( $ppackage, $pfilename, $pline, $psubroutine ) = @pf;
  #$log->write({prefix=>undef},$lll, '( $ppackage, $pfilename, $pline, $psubroutine ) = : ', "( $ppackage, $pfilename, $pline, $psubroutine)" );
  # this tells us yet one more step back
  my @ppf = caller($f+2);
  my ( $pppackage, $ppfilename, $ppline, $ppsubroutine ) = @ppf;
  #$log->write({prefix=>undef},$lll, '( $pppackage, $ppfilename, $pline, $ppsubroutine ) = : ', "( $pppackage, $ppfilename, $ppline, $ppsubroutine)" );
  if ( $pline ) {
    push @caller, "at " . ($psubroutine ? $psubroutine : $package) . ":$line";
    push @caller, join('',"called from ", ($ppsubroutine ? $ppsubroutine : $ppackage), ":$pline");
  }else{
    push @caller, "at $package:$line";
    push @caller, "called from $package:$line";
  }
  return wantarray ? @caller : join('', @caller );
}

LOGS: { # a cache of open log objects for output
  # this may not be too desirable in the end because 
  # you lose individual control of the log level, file ... and such
  # although I may be able to fix that
  my %LOGS = ( STDOUT  => __PACKAGE__->object( { log_file  => 'STDOUT', log_level => $log_level } ),
               STDIN   => __PACKAGE__->object( { log_file  => 'STDIN' , log_level => $log_level } ),
               STDERR  => __PACKAGE__->object( { log_file  => 'STDERR', log_level => $log_level } ),
             );
  
  # unless otherwise specified we will use STDERR as our output stream
  $LOGS{DEFAULT} = $LOGS{$default_fh};
  #use Carp qw( cluck confess );
  #local $SIG{__WARN__} = \&cluck;
  #local $SIG{__DIE__} = \&confess;
  
  sub object {
    # there should probably be a better way of specifying which existing
    # logging object should be used rather than REALLOG
    my $self = shift;
    my $class = ref $self || $self;
    #carp(  " --  $self->object() CALLER  -- " );
    $self = $class->new( @_ ) unless ref $self;

    my @args = @_;
    my $args;
    
    if ( my $init = shift @args ) {
      ref $init eq 'HASH'  and $args = $init;
      ref $init eq 'ARRAY' and 1;
    }
    #my $log = $args->{log} || $self->tmpGet('LOG_OBJECT') || $class || 'DEFAULT';
    my $log = $args->{log} || $class || 'DEFAULT';
    $log = $LOGS{$log} ||= ($class eq __PACKAGE__ ? $self : __PACKAGE__->new(@_));
    
    return $log if $log;
    # hmmm failed?
    return delete $LOGS{$log};
  }
}


sub get_fh {
  my $self = shift;
  my $file = shift || $self->{log_file};
  #$log->write($lll, '$file: ', $file);
  my $fh = $self->_fh( log_file => $file );
  return $fh;
}

our %FHS = ();
# OK .. I'm not sure, but trying to use STDIN may be totally retarded
@FHS{qw( STDIN  STDOUT STDERR )} = ( \*STDIN , \*STDOUT, \*STDERR );
foreach my $fh ( @FHS{qw( STDOUT STDERR )} ) { _unbuffer( $fh ) }
FILEHANDLES : { # a cache of open filehandles for output
  sub _fh {
    my $self = shift;
    #return $FHS{STDERR};
    my $args = { @_ };
    #print STDOUT join(" ", @_), "\n";
    my $level = $args->{-level} || DEFAULT;
    my $file;
    my $fh;
    #_WRITE( "SHITBALLS", "  \$level  = '$level'\n" );
    if ( $level =~ /^STDERR|STDOUT|STDIN$/i ) {
      $fh = $FHS{"\U$level"};
    } else {
      $file = $args->{log_file}
        || $self->{"log_file_$level"}
          || $self->{log_file}
            || $default_fh;
      $fh = $args->{fh} || $FHS{$file};
    }
    #print STDOUT "FH: [$level] :: ", $fh, ":", fileno($fh), "\n";

    return $fh if ( $fh and fileno($fh) );
    #die;
    my $mode;
    my $file_clean = $file;
    if ( $file_clean =~ s/^\s*([>]{1,2})// ) {
      $mode = $1;
    } else {
      $mode = -f $file_clean ? '>>' : '>';
    }
    ( $fh = $FHS{$file} = new IO::File ) or die $!;
    #print STDERR "Opening new filehandle on '$mode' '$file_clean'\n";
    $fh->open( "$mode $file_clean" )
      and flock $fh, LOCK_EX || die $!;
    _unbuffer( $fh );
  }
  
  sub _unbuffer {
    my $fh = shift;
    my $selected = select;
    # disable buffering on this filehandle
    select $fh; $| = 1;
    # restore previously selected filehandle
    select $selected;
    return $fh;
  }
  
  sub _WRITE {
    my $message;
    my $fh;
    my $args = {};
    if ( $_[0] =~ /^-/ ) {
      $args = { @_ };
      $message = $args->{-message} or return undef;
      ref $message eq 'ARRAY' or $message = [ $message ] ;
      $fh = $args->{-FH};
    } else {
      shift @_ if ( $fh = $FHS{$_[0]} );
      $message = [ join ' ', _caller(), @_ ] ;
    }
    $fh ||= $FHS{$default_fh};
    my $return = join '', @$message;
    if ( $args->{-terse} ) {
      $return =~ s/\s+/ /mg;
    }
    print $fh $return, $n or die $!;
    return $return;
  }
  
}

END {
  #    delete $FHS{STDERR};
  #    delete $FHS{STDOUT};
  #    foreach my $fh ( values %FHS ) {
  #      $fh->close();
  #    }
}



1;
__END__
=head1 NAME

Log::Easy - Easy to use, feature rich general purpose logging utility

=head1 SYNOPSIS

  use Log::Easy;
  $log = new Log::Easy;

=item $log->write([{ OPTIONS }], <LOG_LEVEL>, @message );

This is the main function for this package. If the first argument is a
hash reference, it is taken as options to the logger for this log call
ONLY, and may contain values for ANY of the options that the logger
knows how to use. The first argument after the optional OPTIONS hash
MUST BE the log level for this log. If it ends up being something that
is not a log_level, then a default log_level is assigned to the write
call. If the $log->write($log_level, @message) is equal to or greater
than the $log->log_level() [or the $OPTIONS->{log_level}] then it will
be output, otherwise it will not. 

=item $log->clone( [$data] );

make a duplicate of the supplied $data or this log object if no data
is supplied. Uses data dumper to duplicate original, therefore CODE
references are not necessarily handled, although the contents of
$log->prefix() will be assigned to the new (cloned) object from the
original.  returns the cloned object

=head2 OPTIONS

=item $log->n();

set the message terminator for this log object, each log message
output will be terminated with the contents of this setting (default "\n")

=item  $log->log();

set the log object to use for actual write operation, this occurrs
AFTER the decision as to whether or not this log message will be
processed. This allows one to set the log object to another logging
module (such as running under apache)


=item  $log->log_file();

set the output file for messages processed through this log object (
can be a file handle or file path, default => 'STDERR')


=item  $log->log_level();

set the thrshold for which messages will actiually be logged, only
messages with a log_level set to a (nuerically) higher value will be
output (default => WARN)


=item  $log->dump_refs();

set the behavior when references are encountered in the message list
contents (default => 1) if true, use data dumper to dump out the
references


=item  $log->handle_fatals();

if true, log module will terminate program execution on any log calls
marked as fatal (CRIT for now [maybe add EMERG], default => 1)


=item  $log->exclusive();

if true, and set to a colon delimited set of log_level indicators,
this log object will only output its message if the current log call
is for a level listed in exclusive (default => undef)


=item  $log->stack_trace();

if true (and this log message is of sufficient log_level to be
output), issue a pretty little stack trace for the log call


=item  $log->email(); #NOT YET IMPLEMENTED

for a log level of MESSAGE, send the log message to the email address
listed here, if not set, and a MESSAGE log comes in, then send the
email to the owner of the process


=item  $log->prefix();

set ther prefix that each log message will have, may be either a
string, or a CODE ref


=head1 DESCRIPTION

  This logging facility has many features developers may find handy.

=item FILTERING

One of the coolest things is FILTERING (see log_level_filtered). Using
filtering we can greatly decrease the performance penalty of copious
log entries (each requireing >1 subroutine call) by filtering out log
messages at compile time. Here is the general idea:

 # FILTERED
 $log->write($dll, "Nifty stuff");

 # NOT-FILTERED, but will issue a warning if $ENV{WARN_FILTER} is true.
 # because it looks kind of like a log_level indicator that sould be filtered ($dll)
 $log->write(dll, "Nifty stuff");

 # NOT-FILTERED, functionally equivalent to previous example
 $log->write(DEBUG, "Nifty stuff");


=head2 EXPORT

None by default.

=over 8

=item log

exports a log object into your namespace. This is most likely an
application global log object meaning that if you wan't specific
logging behavior in any given package, you'll probably want to
intanntiate a new log object

=item log_level

exports several constants into your namespace:
   DEFAULT MESSAGE LOUD CLEAN QUIET
   EMERG ALERT CRIT ERROR WARN NOTICE INFO DEBUG
   TRACE SPEW


=item log_level_filtered

these are scalar variable ($) aliases for the constants mentioned in
log_level, the convention is that each alias begins with the same
letter as the real log_level, followed by 2 `l's (eg ERROR => $ell,
DEBUG => $dll, etc)

These log_level specifiers, when used with the leading dollar sign MAY
BE FILTERED OUT depending upon the settings for $ENV{LOG_FILTER}

=item log_level_not_filtered

in name, these are identical to the log_level_filtered variables, but
they are implemented as constants (no leading $) and they ARE NOT
SUBJECT TO FILTERING AS IS THE CASE FOR log_level_filtered

=back

=head1 HISTORY

=over 8

=item 0.01
Basic package w/ full functionality, but no docs yet

=item 0.01.1
Basic package w/ full functionality, but no docs yet, used make dist to create pause upload

=item 0.01.2
Added some documentation

=back

=head1 TODO

=over 8

=item 0.01

DOCUMENTATION DOCUMENTATION DOCUMENTATION DOCUMENTATION DOCUMENTATION !!!!!

=item 0.02

change the codes which represent the log_levels such that $xll style
log calls can have slightly different behavior in terms of being
programmer-debug calls, which will probably want to have detailed
prefix informtaion, while non-programmer-debug calls may want
different prefix info ($dll vs DEBUG)

=back


=head1 AUTHOR

Theo Lengyel, E<lt>theo@taowebs.net<gt>

=head1 SEE ALSO

L<perl>.

=cut
