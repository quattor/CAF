#============================================================================
#
# AppConfig::Sys.pm
#
# Perl5 module providing platform-specific information and operations as 
# required by other AppConfig::* modules.
#
# Written by Andy Wardley <abw@cre.canon.co.uk>
#
# Copyright (C) 1998 Canon Research Centre Europe Ltd.
# All Rights Reserved.
#
#----------------------------------------------------------------------------
#
# $Id: Sys.pm,v 1.1 2003/02/04 15:13:17 gcancio Exp $
#
#============================================================================

package AppConfig::Sys;

require 5.004;

use strict;
use vars qw( $VERSION $AUTOLOAD $OS %CAN %METHOD);

$VERSION = sprintf("%d.%02d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/);

BEGIN {
    # define the methods that may be available
    %METHOD = (
	'getpwnam' => sub { getpwnam(defined $_[0] ? shift : '') },
	'getpwuid' => sub { getpwuid(defined $_[0] ? shift : $<) },
    );

    # try out each METHOD to see if it's supported on this platform;
    # it's important we do this before defining AUTOLOAD which would
    # otherwise catch the unresolved call
    foreach my $method  (keys %METHOD) {
	eval { &{ $METHOD{ $method } }() };
    	$CAN{ $method } = ! $@;
    }
}
    


#========================================================================
#                      -----  PUBLIC METHODS -----
#========================================================================

#========================================================================
#
# new($os)
#
# Module constructor.  An optional operating system string may be passed
# to explicitly define the platform type.
#
# Returns a reference to a newly created AppConfig::Sys object.
#
#========================================================================

sub new {
    my $class = shift;
    
    my $self = {
	METHOD => \%METHOD,
	CAN    => \%CAN,
    };

    bless $self, $class;

    $self->_configure(@_);
	
    return $self;
}



#========================================================================
#
# AUTOLOAD
#
# Autoload function called whenever an unresolved object method is 
# called.  If the method name relates to a METHODS entry, then it is 
# called iff the corresponding CAN_$method is set true.  If the 
# method name relates to a CAN_$method value then that is returned.
#
#========================================================================

sub AUTOLOAD {
    my $self = shift;
    my $method;


    # splat the leading package name
    ($method = $AUTOLOAD) =~ s/.*:://;

    # ignore destructor
    $method eq 'DESTROY' && return;

    # can_method()
    if ($method =~ s/^can_//i && exists $self->{ CAN }->{ $method }) {
	return $self->{ CAN }->{ $method };
    }
    # method() 
    elsif (exists $self->{ METHOD }->{ $method }) {
	return &{ $self->{ METHOD }->{ $method } }(@_);
    } 
    # variable
    elsif (exists $self->{ uc $method }) {
	return $self->{ uc $method };
    }
    else {
	warn("AppConfig::Sys->", $method, "(): no such method or variable\n");
    }

    return undef;
}



#========================================================================
#                      -----  PRIVATE METHODS -----
#========================================================================

#========================================================================
#
# _configure($os)
#
# Uses the first parameter, $os, the package variable $AppConfig::Sys::OS,
# the value of $^O, or as a last resort, the value of
# $Config::Config('osname') to determine the current operating
# system/platform.  Sets internal variables accordingly.
#
#========================================================================

sub _configure {
    my $self = shift;

    # operating system may be defined as a parameter or in $OS
    my $os = shift || $OS;


    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
    # The following was lifted (and adapated slightly) from Lincoln Stein's 
    # CGI.pm module, version 2.36...
    #
    # FIGURE OUT THE OS WE'RE RUNNING UNDER
    # Some systems support the $^O variable.  If not
    # available then require() the Config library
    unless ($os) {
	unless ($os = $^O) {
	    require Config;
	    $os = $Config::Config{'osname'};
	}
    }
    if ($os =~ /Win/i) {
	$os = 'WINDOWS';
    } elsif ($os =~ /vms/i) {
	$os = 'VMS';
    } elsif ($os =~ /Mac/i) {
	$os = 'MACINTOSH';
    } elsif ($os =~ /os2/i) {
	$os = 'OS2';
    } else {
	$os = 'UNIX';
    }


    # The path separator is a slash, backslash or semicolon, depending
    # on the platform.
    my $ps = {
	UNIX      => '/',
	OS2       => '\\',
	WINDOWS   => '\\',
	MACINTOSH => ':',
	VMS       => '\\'
    }->{ $os };
    #
    # Thanks Lincoln!
    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 


    $self->{ OS      } = $os;
    $self->{ PATHSEP } = $ps;
}



#========================================================================
#
# _dump()
#
# Dump internals for debugging.
#
#========================================================================

sub _dump {
    my $self = shift;

    print "=" x 71, "\n";
    print "Status of AppConfig::Sys (Version $VERSION) object: $self\n";
    print "    Operating System : ", $self->{ OS      }, "\n";
    print "      Path Separator : ", $self->{ PATHSEP }, "\n";
    print "   Available methods :\n";
    foreach my $can (keys %{ $self->{ CAN } }) {
	printf "%20s : ", $can;
	print  $self->{ CAN }->{ $can } ? "yes" : "no", "\n";
    }
    print "=" x 71, "\n";
}



1;

__END__

=head1 NAME

AppConfig::Sys - Perl5 module defining platform-specific information and methods for other AppConfig::* modules.

=head1 SYNOPSIS

    use AppConfig::Sys;
    my $sys = AppConfig::Sys->new();

    @fields = $sys->getpwuid($userid);
    @fields = $sys->getpwnam($username);

=head1 OVERVIEW

AppConfig::Sys is a Perl5 module provides platform-specific information and
operations as required by other AppConfig::* modules.

AppConfig::Sys is distributed as part of the AppConfig bundle.

=head1 DESCRIPTION

=head2 USING THE AppConfig::State MODULE

To import and use the AppConfig::Sys module the following line should
appear in your Perl script:

     use AppConfig::Sys;

AppConfig::Sys is implemented using object-oriented methods.  A new
AppConfig::Sys object is created and initialised using the
AppConfig::Sys->new() method.  This returns a reference to a new
AppConfig::Sys object.  

    my $sys = AppConfig::Sys->new();

This will attempt to detect your operating system and create a reference to
a new AppConfig::Sys object that is applicable to your platform.  You may 
explicitly specify an operating system name to override this automatic 
detection:

    $unix_sys = AppConfig::Sys->new("Unix");

Alternatively, the package variable $AppConfig::Sys::OS can be set to an
operating system name.  The valid operating system names are: Win, VMS,
Mac, OS2 and Unix.  They are not case-specific.

=head2 AppConfig::Sys METHODS

AppConfig::Sys defines the following methods:

=over 4

=item getpwnam()

Calls the system function getpwnam() if available and returns the result.
Returns undef if not available.  The can_getpwnam() method can be called to
determine if this function is available.

=item getpwuid()

Calls the system function getpwuid() if available and returns the result.
Returns undef if not available.  The can_getpwuid() method can be called to
determine if this function is available.

=item 

=head1 AUTHOR

Andy Wardley, C<E<lt>abw@cre.canon.co.ukE<gt>>

Web Technology Group, Canon Research Centre Europe Ltd.

=head1 REVISION

$Revision: 1.1 $

=head1 COPYRIGHT

Copyright (C) 1998 Canon Research Centre Europe Ltd.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under 
the term of the Perl Artistic License.

=head1 SEE ALSO

AppConfig, AppConfig::File

=cut
