#!/usr/bin/perl

use warnings;
use strict;

use Sys::Syslog qw(:standard :macros);
use Net::LDAP;

my $facility = LOG_AUTH;
my $ourname = 'ldap_auth.pl';

my $ldapserver = 'windowsdc';
my $domain = 'example.com';
my $vpngroup = 'vpnauth';

# base DN for the search; adjust the code if the vpn group isn't directly in here.
my $basedn = 'ou=Users,dc=example,dc=com';

my $ldap_uri = "ldap://${ldapserver}.${domain}";

# these are passed by OpenVPN
my $username = $ENV{'username'};
my $password = $ENV{'password'};

openlog($ourname, 'nofatal,pid', $facility);

# filter can/should be customized
my @filter = ( "(sAMAccountName=${username})",
               "(memberOf=cn=${vpngroup},${basedn})",
               '(accountStatus=active)',
             );

# using userAccountControl seems to work better at detecting active users
# see https://github.com/waldner/openvpn-ldap/commit/9f2d0e835514f0aecc6cbb31a7dabe6367d410bf#comments
# Thanks to https://github.com/smanross
# my @filter = ( "(sAMAccountName=${username})",
#               "(memberOf=cn=${vpngroup},${basedn})",
#               '(!(userAccountControl:1.2.840.113556.1.4.803:=2))',
#             );

# bind as the authenticating user
my $bindname = $username . '@' . $domain;

syslog(LOG_INFO, "Attempting to authenticate user $username ($bindname)");

my $ldap;

if (not ($ldap = Net::LDAP->new($ldap_uri))) {
  syslog(LOG_ERR, "Connect to $ldap_uri failed, error: %m");
  closelog();
  exit 1;
}

my $result = $ldap->bind($bindname, password => $password);

if ($result->code()) {
  syslog(LOG_ERR, "LDAP binding failed (wrong user/password?), error: " . $result->error);
  closelog();
  exit 1;
}

$result = $ldap->search( base => $basedn, filter => "(&" . join("", @filter) . ")" );

if ($result->code()) {
  syslog(LOG_ERR, "LDAP search failed, error: " . $result->error);
  closelog();
  exit 1;
}

my $count = $result->count();

if ($count == 1) {
  syslog(LOG_INFO, "User $username authenticated successfully");
} else {
  syslog(LOG_ERR, "User $username not authenticated (user not in group?)");
}

closelog();

exit ($count == 1 ? 0 : 1);
