#! /usr/bin/perl -w

##
##	Linux User Creation Tool
##	interactive utility for creating a new user and setting up custom settings
##		ie: vhost, custom home directory, custom shell, etc
##
##	spike grobstein
##	spikegrobstein@mac.com
##	http://spike.grobste.in
##

use strict;

# use LDAP stuff for communication to the LDAP database
use Net::LDAP;
use Net::LDAP::LDIF;

use Term::ReadKey; # used to prevent echoing of password on the commandline

&print_welcome();

#init
print "Initializing... ";

&check_root(); # gotta check to make sure we have proper privs before any time is wasted!

our $prompt_delimiter = ':'; #for prompting...

our @uid_list = ();
our @loginList = ();
our $start_uid = 5000;

# LDAP settings
our $ldap_port = 389; # non-encrypted...
our $ldap_host = 'localhost';
our $ldap_version = 3;
our $ldap_scheme = 'ldap';

our $baseDN = "dc=darkerhosting,dc=net";
our $adminDN = "cn=Manager,$baseDN";
our $userDN = "ou=people,$baseDN";

&makeLists();

my $default_gid = 100;

# the various default settings for the new user
my $login = '';
my $real_name = '';
my $email = '';
my $shell = '/bin/bash';
my $uid = $start_uid;
my $gid = $default_gid;
my $home = '/home/'; # this gets changed right before it's used
my $password = &rand_password(8);
my $domain = '';

print "done\n\n";

# read the login...
# make sure that it isn't already in use!
while ($login eq '') {
	$login = &read_input('Login', '', 0);
	if (!&check_login($login)) {
		print "Invalid login: already in use!\n";
		$login = '';
	}
}

# read in everything else...
$real_name = &read_input('Real Name', $real_name, 0);
$email = &read_input('Email', $email, 1);
$shell = &read_input('Shell', $shell, 1);
$uid = &read_input('uid', $uid, 1);
$gid = &read_input('gid', $gid, 1);
$home = &read_input('Home', $home . $login, 1);
$password = &read_input('Password', $password, 1);
$domain = &read_input('Domain', $domain, 1);

print "\n";
print "Creating LDAP entries...\n\n";

my $ldap_bind_pw = &read_ldap_password();

print "Password: " . $ldap_bind_pw;

exit;

# ok, do all the work now...

print "Connecting to LDAP server... ";

my $ldap = Net::LDAP->new($ldap_host, port => $ldap_port, version => $ldap_version, scheme => $ldap_scheme);
my $result = $ldap->bind("$adminDN", password => $ldap_bind_pw);
if ($result->code()) {
	print "ERROR: " . $result->error  . "\n\n";
	exit;
}

print "\n";
print "Adding entry... ";
$result = $ldap->add(	"uid=$login,$userDN",
						attr => [
							'uid'	=> "$login",
							'sn'	=> "$login",
							'cn'	=> "$real_name",
							'objectClass' => ['person', 'organizationalPerson',
								'inetOrgPerson', 'posixAccount', 'top',
								'shadowAccount'],
							'shadowLastChange' => '100000',
							'shadowMax' => '99999',
							'loginShell' => "$shell",
							'uidNumber' => "$uid",
							'gidNumber' => "$gid",
							'homeDirectory' => "$home",
							'userPassword' => '*' ] );

if ($result->code()) {
	print "ERROR (" . $result->error() . ")\n\n";
	exit;
}

print "\n";
print "Closing LDAP connection...\n";
$ldap->unbind();

print "Setting LDAP password... ";
$result = `ldappasswd -D "$adminDN" -w $ldap_bind_pw -s $password -x "uid=$login,$userDN"`;
if ($?) {
	print "ERROR (" . $result->error() . ")\n\n";
	exit;
}
print "\n";

print "Creating files...";
`cp -R /etc/skel/ $home`;
`chown -R $login:users $home`;
`chmod -R 711 $home`;
`chmod o+r $home/public_html`;

if ($real_name ne "") {
	`echo "<html><head><title>$real_name</title></head><body><center>Future home of <b>${real_name}'s</b> website.</body></html>" > $home/public_html/index.html`;
} else {
	`echo "<html><head><title>$login</title></head><body><center>Future home of <b>${login}'s</b> website.</body></html>" > $home/public_html/index.html`;
}
print "\t$home/public_html/index.html\n";

my $hostPath = "/etc/apache2/vhosts.d/$login.conf";
if ($domain ne "") {
	`echo "" >> $hostPath`;
	`echo "<VirtualHost *:80>" >> $hostPath`;
	`echo "    ServerAlias *.$domain" >> $hostPath`;
	if ($email ne "") {
		`echo "    ServerAdmin $email" >> $hostPath`;
	}
	`echo "    DocumentRoot $home/public_html/" >> $hostPath`;
	`echo "    ServerName $domain" >> $hostPath`;
	`echo "</VirtualHost>" >> $hostPath`;

	print "\t$hostPath updated.\n";

	`apache2ctl restart`;
	print "Apache restarted...\n";
}
print "done.\n";

print "User creation complete!\n\n";
exit;

sub print_welcome() {
	#print welcome screen
	print qq{
     _ Welcome To _   
    | |_   _  ___| |_ 
    | | | | |/ __| __|
    | | |_| | (__| |_ 
    |_|\\__,_|\\___|\\__|
+------------------------+
 Linux User Creation Tool
   Written by spike
      spike666\@mac.com
+------------------------+

};
}

sub check_root() {
	my $whoami = `whoami`;
	chomp($whoami);

	if ($whoami ne 'root') {
		print "You must be root to run this script!\n\n";
		exit;
	}
}

sub read_input() {
	my $prompt = shift;
	my $default = shift;
	my $show_default = shift;

	my $input = '';

	my $full_prompt = $prompt;

	if ($show_default) {
		$full_prompt .= ' [' . $default . ']';
	}

	$full_prompt .= $prompt_delimiter . ' ';

	print $full_prompt;
	chomp ($input = <STDIN>);

	if ($input eq '') {
		return $default;
	}

	return $input;
}

sub read_ldap_password() {
	##
	##	prompts for and reads the LDAP bind password
	##	doesnt' echo back to the shell in the process
	##
	
	our $prompt_delimiter;
	
	ReadMode('noecho');
	print 'LDAP Bind Password' . $prompt_delimiter . ' ';
	my $pass = ReadLine(0);
	chomp($pass);
	ReadMode(0);
	print "\n";
	
	return $pass;
}

sub makeLists {
	# makes a list of all logins and uids to check for existing...
	# then determines what the next UID should be.
	
	#first, make a list of all the passwd data
	my @t_users = split(/\n/, `getent passwd`);
	foreach (@t_users) {
		my @data = split(/:/, $_);
		&addLogin($data[0]); #add the login to the login list
		&addUid($data[2]); #add the UID to the UID list
	}
	
	our @uid_list;
	our $start_uid;
	
	# sort the UID list
	@uid_list = sort { $a <=> $b } @uid_list;

	#calculate what the highest UID is and set the start_uid to that+1
	my $lastUid = 0;
	foreach (@uid_list) {
		if ($_ > $start_uid) {
			if ($_ != $lastUid + 1) {
				$start_uid = $lastUid + 1;
				return;
			}
		}
		$lastUid = $_;
	}
}

sub addUid {
	##
	##	add a uid to the uid list, making sure it doesn't already exist on there
	##
	my $uid = shift;
	
	foreach (@uid_list) {
		if ($_ eq $uid) {
			return;
		}
	}

	$uid_list[scalar @uid_list] = $uid;
}

sub addLogin {
	##
	## add a login to the login list and avoid dupes
	##
	
	my $login = shift;

	foreach (@loginList) {
		if ($_ eq $login) {
			return;
		}
	}

	$loginList[scalar @loginList] = $login;
}

sub check_login {
	##
	## make sure that the login that's passed to this function isn't already in the list
	##
	
	my $login = shift;

	foreach (@loginList) {
		if ($_ eq $login) {
			return 0; #false...
		}
	}
	return 1; #true...
}

sub rand_password() {
	##
	##	generate a random password 
	##
	
	my $len = shift; #password length
	$len = 8 if $len == 0;

	my @chars = ('a' .. 'z', 'A' .. 'Z');

	srand;

	my $password = "";

	for (my $i = 0; $i <= $len; $i++) {
		$password .= $chars[int(rand scalar @chars)];
	}

	return $password;
}
