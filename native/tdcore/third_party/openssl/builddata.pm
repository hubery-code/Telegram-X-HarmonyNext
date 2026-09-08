package OpenSSL::safe::installdata;

use strict;
use warnings;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
    @PREFIX
    @libdir
    @BINDIR @BINDIR_REL_PREFIX
    @LIBDIR @LIBDIR_REL_PREFIX
    @INCLUDEDIR @INCLUDEDIR_REL_PREFIX
    @APPLINKDIR @APPLINKDIR_REL_PREFIX
    @ENGINESDIR @ENGINESDIR_REL_LIBDIR
    @MODULESDIR @MODULESDIR_REL_LIBDIR
    @PKGCONFIGDIR @PKGCONFIGDIR_REL_LIBDIR
    @CMAKECONFIGDIR @CMAKECONFIGDIR_REL_LIBDIR
    $COMMENT $VERSION @LDLIBS
);

our $COMMENT                    = 'This file should be used when building against this OpenSSL build, and should never be installed';
our @PREFIX                     = ( '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl' );
our @libdir                     = ( '' );
our @BINDIR                     = ( '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl/apps' );
our @BINDIR_REL_PREFIX          = ( 'apps' );
our @LIBDIR                     = ( '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl' );
our @LIBDIR_REL_PREFIX          = ( '' );
our @INCLUDEDIR                 = ( '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl/include', '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl/include' );
our @INCLUDEDIR_REL_PREFIX      = ( 'include', './include' );
our @APPLINKDIR                 = ( '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl/ms' );
our @APPLINKDIR_REL_PREFIX      = ( 'ms' );
our @ENGINESDIR                 = ( '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl/engines' );
our @ENGINESDIR_REL_LIBDIR      = ( 'engines' );
our @MODULESDIR                 = ( '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl/providers' );
our @MODULESDIR_REL_LIBDIR      = ( 'providers' );
our @PKGCONFIGDIR               = ( '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl' );
our @PKGCONFIGDIR_REL_LIBDIR    = ( '.' );
our @CMAKECONFIGDIR             = ( '/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/native/tdcore/third_party/openssl' );
our @CMAKECONFIGDIR_REL_LIBDIR  = ( '.' );
our $VERSION                    = '3.5.8';
our @LDLIBS                     =
    # Unix and Windows use space separation, VMS uses comma separation
    $^O eq 'VMS'
    ? split(/ *, */, '-ldl -pthread ')
    : split(/ +/, '-ldl -pthread ');

1;
