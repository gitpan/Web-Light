use inc::Module::Install;

name        'Web-Light';
all_from    'lib/Web/Light.pm';
requires    'FindBin::Real';
requires    'HTTP::Engine'  => '0.03';
requires    'HTTP::Engine::Middleware' => '0.18';
requires    'Module::Find' => '0.08';
requires    'Module::Load' => '0.16';
abstract_from   'lib/Web/Light.pm';
author          'Michael Kroher <infrared@cpan.org>';
version_from    'lib/Web/Light.pm';
license_from    'lib/Web/Light.pm';
perl_version_from   'lib/Web/Light.pm';

WriteAll;
