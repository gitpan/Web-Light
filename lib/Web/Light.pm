package Web::Light;

use warnings;
use strict;
our $VERSION = '0.01';
use 5.008009;
use FindBin::Real;
use Module::Find;
use Module::Load;
use HTTP::Engine;
use HTTP::Engine::Middleware;
use Getopt::Long;


my $Bin    = FindBin::Real::Bin();
my $Script = FindBin::Real::Script();

my $debug;
my $create;
my $help;
my $port;
my $interface;
my $detach;
my $listen;
my $nproc;
my $host;
my $pid;
my $log;
GetOptions (
    "debug"       => \$debug,
    "create"      => \$create,
    "help"        => \$help,
    "port=i"      => \$port,     # ServerSimple
    "interface=s" => \$interface,
    "detach"      => \$detach,
    "listen=s"    => \$listen,   # FCGI
    "nproc=i"     => \$nproc,    # FCGI
    "host=s"      => \$host,     # ServerSimple
    "pid=s"       => \$pid,      # BOTH
    "log=s"       => \$log,      # ServerSimple
);

if ($help) {
    print qq(--debug \t run in debug mode\n);
    print qq(--create \t create local plugin directories and Root.pm\n);
    print qq(--interface \t specify interface (FCGI, ServerSimple)\n);
    print qq(--host \t\t host to listen on (ServerSimple only)\n);
    print qq(--port \t\t specify port\n);
    print qq(--help \t\t this\n);
    exit;
}

sub new {

    my $class = shift;

    die "Subclass Web::Light. See perldoc Web::Light" if ($class eq __PACKAGE__);

    my %self = map { $_ } @_;

    $self{PLUGINS} ||= \@INC;
    $self{NOLOAD}  ||= [ ];

    die "NOLOAD must be array ref"  if ref($self{NOLOAD})  ne 'ARRAY';
    die "PLUGINS must be array ref" if ref($self{PLUGINS}) ne 'ARRAY';

    setmoduledirs( @{$self{PLUGINS}} );
    my @plugins = findallmod $class;

    for my $module (@plugins) {
            
            if (!grep($module eq $_, @{ $self{NOLOAD} })) {
                load $module;
                print "[debug] loaded:  $module\n" if $debug;
            }
            else {
                print "[debug] skipped: $module\n" if $debug;
            }
    }            

    $self{plugins} = \@plugins;

    bless \%self, $class;
}

sub stash {

    my $self = shift;
    
    my %stash = map { $_ } @_;

    $self->{stash} = \%stash;

    if ($debug) {
        for my $each (keys %stash) {
            print "[debug] stash: $each => $stash{$each}\n";
        }
    }
} 



sub dispatch {
    my $self = shift;
    
    my $class = ref $self;
    my %dispatch = map { $_ } @_;

    if ( !exists $dispatch{root} ) {
        print STDOUT "[debug] dispatch:  No dispatch set for root, setting to: ${class}::Plugin::Root\n" if $debug;
        
        $dispatch{root}{plugin}  ||= "${class}::Plugin::Root"; # set a default for /.  Yes.. Root.pm from Catalyst. I know
        $dispatch{root}{methods} ||= [ qw/ default /];         # default method

        if ($create) {

            # Need this here so we can retrieve $class.
            # I'm sure it'll work under any other
            # sub that gets called from our blessed package
            my ($class) = caller();
            if (!-e "$Bin/$class") {
                die $! if !mkdir("$Bin/$class",0755);
                print "Created directory: $Bin/$class\n";
            }
            if (!-e "$Bin/$class/Plugin") {
                die $! if !mkdir("$Bin/$class/Plugin",0755);
                print "Created directory: $Bin/$class/Plugin\n";
            }
            createRootPlugin($class);
            print "Created Plugin: ${class}::Plugin::Root\n";
            exit;
        }

        my $test = "${class}::Plugin::Root";
        if  ( !$test->can('default') )  {
            print "Fatal: either $test doesn't exist,
               or there is no default method.\n Maybe try $Script --create\n";
            exit;
        }

    }
    $self->{dispatch} = \%dispatch;

    if ($debug) {
        for my $each (keys %dispatch) {
            print "[debug] dispatch: $each => $dispatch{$each}\n";
        }
    }

    my @dispatch_errors = $self->dispatch_match( $self->{plugins}, $self->{dispatch} );

    if (@dispatch_errors) {
        print STDOUT "$_\n" for @dispatch_errors;
        exit;
    }  # wasn't that fun?


    my @method_errors = $self->method_match($self->{dispatch});

    if (@method_errors) {
        print STDOUT "$_\n" for @method_errors;
        exit;
    }

}

sub setup {
    my $self = shift;
    my $class = ref $self;
    my %args = map { $_ } @_;
    my $args = \%args;

    # was this app started with --interface ? 
    if ($interface) {
        if ($interface =~ /^(fcgi|fastcgi)$/i) {
            $interface = 'FCGI';
            print "[debug] FCGI interface\n" if $debug;
            $detach ||= 1;
            print "[debug] FCGI detach => $detach\n" if $debug;
            $nproc  ||= 1;
            print "[debug] FCGI nproc => $nproc\n" if $debug;
            $listen ||= "/tmp/$class\.sock";
            print "[debug] FCGI listen => $listen\n" if $debug;
            $pid    ||= "/tmp/$class\.pid";
            print "[debug] FCGI pidfile => $pid\n" if $debug;

            $args->{engine} = {
                interface => {
                    module => 'FCGI',
                    args => {
                        nproc => $nproc,
                        detach => $detach,
                        listen => $listen,
                    },
                },
            };
        }
        if ($interface =~ /^(serversimple|simple)$/i) {
            $port ||= 5000;
            print "[debug] ServerSimple interface\n" if $debug;
            $host ||= '127.0.0.1';
            print "[debug] ServerSimple host => $host\n" if $debug;
            $detach ||= 1;
            print "[debug] ServerSimple detach => $detach\n" if $debug;
            $pid    ||= "/tmp/$class\.pid";
            print "[debug] ServerSimple pidfile => $pid\n" if $debug;
            $log    ||= "/tmp/$class\.log";

    
            $args->{engine} = {
                interface => {
                    module => 'ServerSimple',
                    args => {
                        host => $host,
                        port => $port,
                        net_server => 'Net::Server',
                        net_server_configure => {
                            setsid => $detach,
                            pid_file    => $pid,
                            log_file => $log, 
                        }
                    },
                },
            };
        }
    }

    if (!exists $args->{engine}) {
        # we're here if either --interface was not used,
        # or setup( engine => $arg ) was not used.
        # set a default to ServerSimple
        # I could have put it somewhere above,
        # but I want it here for clarity
        $host ||= '127.0.0.1';  # myapp.pl --host ?
        $port ||= '5000';       # myapp.pl --port ?
        $args->{engine} = {
            interface => {
                module => 'ServerSimple',
                args => {
                    host => $host,
                    port => $port,
                },
            },
        };
    }
        
        

    

    my $mv = HTTP::Engine::Middleware->new({
        method_class => 'HTTP::Engine::Request'
    });
   
     
    if (exists $args->{middleware}) {
        $mv->install( %{ $args->{middleware} });
    }
    else { 
        if (exists $args->{session}) {
            $mv->install('HTTP::Engine::Middleware::HTTPSession' => $args->{session} );
        }
        if (exists $args->{static}) {
            $mv->install('HTTP::Engine::Middleware::Static' => $args->{static} );
        }
    }
    #$mv->install( %{ $args->{middleware} }) if exists $args->{middleware};
    $args->{engine} = $self->defaults if !exists $args->{engine};
    $args->{engine}{interface}{request_handler} = $mv->handler( sub { $self->handler(@_) }  );
    my $engine = HTTP::Engine->new( %{ $args->{engine}} );
    $engine->run();
}


sub handler {
    my $self = shift;
    my $req  = shift;

    my $response = HTTP::Engine::Response->new;
    my @path = ($req->path =~ /([a-zA-Z0-9]+)/g);

    shift @path if lc $path[0] eq $self->{MOUNT};

    # Root.pm from Catalyst .. yeah i know!
    my $plugin = defined($path[0]) ? lc $path[0] : 'root';

    my $sub    = defined($path[1]) ? lc $path[1] : 'default';

    my $output;

    # $args to send to the plugins
    my $args = {
        app   => $self,
        stash => $self->{stash},
        req   => $req,
    };

    # let's check to see if the plugin exists, and/or the method/sub exists too
    if (
        !exists( $self->{dispatch}{$plugin} ) or
        !$self->{dispatch}{$plugin}{plugin}->can($sub) or
        !grep($sub eq $_, @{$self->{dispatch}{$plugin}{methods} } )
    ) {
        # time for 404...
        # it's possible to call the method "new" with:  404 => 'MyApp::Plugin::My404',
        # and in that plugin, there should be a 'default' method. So.. another check!
        if (
            !exists( $self->{404} ) or
            !$self->{404}->can('default')
        ) {
            # fail. set the default 404...
            $output = "404, Sorry :(";
        }
        else {
            # there seems to be a 404 plugin and 'default' method, so do it!
            $output = $self->{404}->default($args);
        }
        $response->body($output);
        $response->status(404);
        return $response;

    }
    else {
        # If we got to this point, everything looks good. 
        # let's send some output from our plugins

        my $Plugin = $self->{dispatch}{$plugin}{plugin};


        # sessions! if session => \@list is supplied for
        # a plugin, we need to see if those session
        # variables are set, if not, force 'Auth' plugin
        if (exists $self->{dispatch}{$plugin}{session}) {

            
            # this will die if setup() doesn't have any
            # session stuff in there!
            my $session = $req->session;

            # loop through the session => \@list, check if they
            # are set.
            for my $require (@{ $self->{dispatch}{$plugin}{session} } ) {
                if (!$session->get($require)) {
                    # session variable isn't set, so we have
                    # to force 'Auth' Plugin
                    $Plugin = $self->{AUTH};
                    $sub    = 'default';
                    last;
                }
            }
        }
        $output = ${Plugin}->$sub($args);
        $response->body($output);
        $response->status(200);
        return $response;
    }
}

sub dispatch_match {


    my ($self,$plugins,$map) = @_;
    my $class = ref $self;
    my @errors;
    for my $each (keys %{$map}) {
        if (!grep($map->{$each}{plugin} eq $_, @{$plugins} )) {
            push(@errors,qq(Trying to map the URL: "/$each" to plugin: "$map->{$each}{plugin}", but no such plugin ) );
        }
    }
   return @errors;
}

sub method_match {

    shift;
    my ($map) = @_;
    my @errors;

    for my $each ( keys %{$map} ) {

        my $plugin = $map->{$each}{plugin};

        for my $method ( @{ $map->{$each}{methods}} ) {
            if (!${plugin}->can($method) ) {
                print "[debug] method_match: $plugin->$method FAILED\n" if $debug;
                push (@errors, qq(You specified method: $method for the plugin: $plugin, but no such method exists) );
            }
            else {
                print "[debug] method_match: $plugin->$method FOUND\n" if $debug;
            }
        }
    }
    return @errors;
}

sub createRootPlugin {
    my ($class) = shift;

    open (my $fh, ">", "$class/Plugin/Root.pm") or die $!;
    print $fh qq(package ${class}::Plugin::Root;),"\n\n";
    print $fh q(use strict;),"\n", q(use warnings;),"\n\n";
    print $fh q(sub default {),"\n",q(    my ($self,$app) = @_;),"\n";
    print $fh q(    my $req     = $app->{req};),"\n";
    print $fh q(    my $param   = $req->parameters;),"\n";
    print $fh q(    my $path    = $req->path;),"\n";
    print $fh q(    # do something with the above,),"\n";
    print $fh q(    # or just a simple Hello World),"\n\n";
    print $fh q(    my $out = "Hello World!";),"\n";
    print $fh q(    return $out;),"\n";
    print $fh q(}),"\n",q(1);
    close $fh;
    return;

}
=head1 NAME

Web::Light - Light weight web framework

=head1 VERSION

Version 0.01

=cut

=head1 SYNOPSIS

Use as a subclass
    
    # myapp.pl
    
    package MyApp;
    
    use base qw/ Web::Light /;
    my $app = __PACKAGE__->new();
    
    $app->stash();
    $app->dispatch();
    $app->setup();

Launch...

    $ perl myapp.pl
    
    or
    
    $ perl myapp.pl --help


=head1 Description 

Web::Light is a light-weight web framework.  It's basically just a wrapper around 
HTTP::Engine, and does some stuff to handle plugins.  If you are 
looking for a more tested, developed, and supported web framework, consider using Catalyst.

Web::Light by default launches a stand alone web server that you can connect to with your 
browser. Since Web::Light can do whatever HTTP::Engine can, you can specify different 
interfaces like ServerSimple and FastCGI.

=head1 Usage

=head2 new( %args )

Creates a Web::Light instance

=over 4

=item PLUGINS => \@locations


Web::Light can load all the modules under $class::* (or MyApp::* in this
example). You can specify a list of locations to use when loading modules.
The list just gets passed to Module::Find's setmoduledirs() method.

    # will default to @INC if PLUGINS is not defined

    new(
       PLUGINS => [ @INC, './' ],
    );

If you don't want to search @INC, and only want to use modules
in your current directory, an example of your directory
structure might look like this:

    $ ls

    -rw-r--r--    myapp.pl
    drwxr-xr-x    MyApp/
    drwxr-xr-x    MyApp/Plugin
    -rw-r--r--    MyApp/Plugin/Root.pm



=item NOLOAD => \@list


If there is a module you do not want loaded, you can do this:

    new(
       PLUGINS => [ @INC, './' ],
       NOLOAD  => [qw/ MyApp::Plugin::Something  MyApp::Foo::Bar /],
   );

=item 404 => $plugin


Specify a plugin to handle 404:

    new(
       404 => 'MyApp::Plugin::My404',
    );

=item AUTH => $plugin


Set the plugin to handle authentication. See dispatch() below on sessions.
If a session variable is not set, then the AUTH plugin will be forced.

    new(
       AUTH => 'MyApp::Plugin::MyAuth',
    );


=item MOUNT => 'path'

If you are using FastCGI, and wish to have the webserver handle static 
content, then you can't just Alias / to your application.

Your httpd.conf (Apache) might look like this:

    <VirtualHost 192.168.1.100:80>
        servername example.org 
        FastCGIExternalServer /fastcgi -socket /tmp/MyApp.sock
        Alias /dynamic /fastcgi/
        DocumentRoot /home/user/MyApp/static
    </VirtualHost>


With the above example, you would have to mount Web::Light
on 'dynamic'

    new(
        MOUNT => 'dynamic',
    );


You cannot mount Web::Light any deeper than one path.

    # INVALID!!!
    new(
        MOUNT => 'site/dynamic',
    );


=back

=head2 new() Example...

    # All together now ...
    
    package MyApp;

    use base qw/ Web::Light/;

    my $app = __PACKAGE__->new(
        PLUGINS => [ @INC, './' , '/path/to/lib' ],
        NOLOAD  => [ qw/ MyApp::Plugin::OLD  MyApp::Auth::File /],
    
        404     => 'MyApp::Plugin::Cool404',
        AUTH    => 'MyApp::Auth::Awesome',
        MOUNT   => 'dynamic',
    );



=head2 dispatch( %args )

Define how URLs get dispatched.

    dispatch(
       root => {
            plugin  => 'MyApp::Plugin::Root',
            methods => [qw/ default /],
       },
       home => {
            plugin  => 'MyApp::Plugin::CoolHome,
            methods => [qw/ default test /],
            session => [qw/ username /],
       },
    );


The above example will dispatch the following to the appropriate
plugin:

    http://localhost/          --> MyApp::Plugin::Root->default()
    http://localhost/hello     --> MyApp::Plugin::Cool404->default()

    http://localhost/home      --> MyApp::Plugin::CoolHome->default()  
    http://localhost/home/test --> MyApp::Plugin::CoolHome->test()


If 'session' contains a list, this forces Web::Light to check if
each variable in that list is set. If they aren't, the 'AUTH' 
plugin that was defined with new() will be forced.

I was going to auto add the 'default' method to the list, but
I felt having to specify the methods for each plugin will help 
remember that this is how it works.

=over 4

=item root => { plugin => ... }

Note:  If you do not dispatch a root URL somewhere, Web::Light will
set root to dispatch to MyApp::Plugin::Root by default. So either
create this plugin:

    $ perl myapp.pl --create
    
... or dispatch root to an already existing plugin:

    $app->dispatch(
        root => {
            plugin  => 'MyApp::Foo::Something',
            methods => [qw/ default /],
        },
    );
    

Also note that root can only have 1 (one) method, and it should
be 'default'.

=back

=head2 stash( %args )

Just a simple hash to pass around stuff to your plugins. Yes, I
"borrowed" this from Catalyst. Catalyst rocks, what can I say?

    use MyDatabase::Main;  # your DBIx::Class
    use Template;
    my $tt = Template->new;

    $app->stash(
        tt => $tt,
        db => MyDatabase::Main->connect(dbi:mysql .. ...),
    );



=head2 setup( %args )

Define your HTTP::Engine and Middleware preferences here. If no arguments are passed, 
Web::Light will use ServerSimple and port 5000 by default.

=over 4

=item engine => ( $args )

Define HTTP::Engine. Be aware that these settings can be defined on the command line too, like:

    $ perl myapp.pl --interface fcgi --nproc 1 --listen /tmp/MyApp.sock --detach

Otherwise, you can specify it like so: 

    $app->setup(
        engine => {    
            interface => {
                module => 'ServerSimple',
                args => {
                    host => '127.0.0.1',
                    port => 4000,
                }
            },
        }
    );
 

    # FastCGI?

    $app->setup(
        engine => {
            interface => {
                module => 'FCGI',
                args   => { },
            },
        },
    );

=item session => ( $args )

Define HTTP::Engine::Middleware::HTTPSession

    $app->setup(
        session => {
            store => {
                class => 'File',
                args => { dir => './tmp' },
            },
            state => {
                class => 'Cookie',
                args => {
                    name => 'MyApp',
                    path => '/',
                    domain => 'example.org',
                },
            }
        }
    );

=item static => ( $args )

Define HTTP::Engine::Middleware::Static to handle your static content

    $app->setup(
        static => {
            regexp => qr{^/(robots.txt|favicon.ico|(?:css|js|images)/.+)$},
            docroot => '/home/user/MyApp/',
        }
    );
 
=back

=head2 method_match()

Gets called by dispatch(). This just verifies that the methods you specify
in your dispatch map to an actual subroutine.

=head2 dispatch_match()

Gets called by dispatch(). This verifies that your dispatch maps to 
actual plugins

=head2 handler()

Handler subroutine sent to HTTP::Engine


=head2 createRootPlugin()

Creates the default *::Plugin::Root plugin when called with:

    $ perl myapp.pl --create


=head1 Creating Plugins

You can name your plugins anything, but in our example, 
the plugins need to be under MyApp::*

    $ mkdir -p MyApp/Foo

    # vi MyApp/Foo/Something.pm
    
    package MyApp::Foo::Something;
    
    use strict;
    use warnings;

    # default must exist
    sub default {

        my ($self,$app) = @_;
        
        # $app has everything!

        # perldoc HTTP::Engine::Request
        my $req     = $app->{req};
        
        # GET/POST paramenters
        my $param   = $req->paramenters;
        
        # perldoc HTTP::Session
        my $session = $req->session;

        my $tt   =  $app->{stash}{tt}; # using Template-Toolkit?
    
        my $schema = $app->{stash}{db};

        # you can return something:
        return "hello world!";

        # or return your template 
        $vars = {
            username => $session->get("username");
        };
        $tt->process('index.tt', $vars, \my $out) or return $tt->error();
        return $out;
    }
    
    sub test {
        return "Just a test method!";
    }

    1;

To use this plugin, make sure you dispatch it to a URL...

    $app->dispatch(
        newplugin => {
            plugin => 'MyApp::Foo::Something',
            methods => [qw/ default test /],
        },
    );
    

Then go to http://localhost/newplugin to see it in action

=head1 AUTHOR

Michael Kroher, C<< <mkroher at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-web-light at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Web-Light>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 See Also

L<HTTP::Engine>

L<HTTP::Engine::Middleware>



=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Web::Light


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Web-Light>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Web-Light>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Web-Light>

=item * Search CPAN

L<http://search.cpan.org/dist/Web-Light/>

=back


=head1 TO-DO

Not much. When I personally need more features or control,
I use Catalyst.


=head1 COPYRIGHT & LICENSE

Copyright 2010 Michael Kroher, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Web::Light
