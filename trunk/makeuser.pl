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


use Net::LDAP;
use Net::LDAP::LDIF;

#print welcome screen
print qq{
    _ Welcome To _   
   | |_   _  ___| |_ 
   | | | | |/ __| __|
   | | |_| | (__| |_ 
   |_|\\__,_|\\___|\\__|
+----------------------+
  Written by spike
      spike666\@mac.com
+----------------------+

};

#init
print "Initializing... ";

my @uidList = ();
my @loginList = ();
my $defaultGid = 100;
my $startUid = 5000;

my $baseDN = "dc=darkerhosting,dc=net";
my $adminDN = "cn=Manager,$baseDN";
my $userDN = "ou=people,$baseDN";

&makeLists();
#print "Start UID: $startUid\n";
print "done\n\n";

$input = "";

while ($input eq "") {
	print "User: ";
	chomp($input = <STDIN>);
	if (!&checkLogin($input)) {
		print "Invalid login\n";
		$input = "";
	}
}

$login = $input;

$input = "";

$realname = "";
print "Real name: ";
chomp($input = <STDIN>);
if ($input ne "") {
	$realname = $input;
}

$input = "";
        
$email = "";
print "Email [none]: ";   
chomp($input = <STDIN>);
if ($input ne "") {
        $email = $input;
}

#$input = "";
        
#$quota = 25000;
#print "Quota [${quota}K]: ";
#chomp($input = <STDIN>);
#if ($input ne "") {
#        $quota = $input;  
#}

$input = "";

$shell = "/bin/bash";
print "Shell [$shell]: ";
chomp($input = <STDIN>);
if ($input ne "") { 
	$shell = $input;
}

$input = "";

$uid = $startUid;
print "uid [$uid]: ";
chomp($input = <STDIN>);
if ($input ne "") {
	$uid = $input;
}
        
$input = "";

$gid = $defaultGid;
print "gid [$gid]: "; 
chomp($input = <STDIN>);
if ($input ne "") {
	$gid = $input;
}

$input = "";

$home = "/home/$login";
print "Home [$home]: ";
chomp($input = <STDIN>);
if ($input ne "") {
	$home = $input;
}

$input = "";
$password = &rand_password(8);
print "Password [$password]: ";
chomp($input = <STDIN>);
if ($input ne "") {
	$password = $input;
}

$input = "";
$domain = "";
print "Domain [none]: ";
chomp($input = <STDIN>);
if ($input ne "") {
	$domain = $input;
}

# ok, do all the work now...

$adminPW = "allah";

print "Connecting to LDAP server... ";
$ldap = Net::LDAP->new("localhost", port => 389, version => 3, scheme => 'ldap');
$result = $ldap->bind("$adminDN", password => $adminPW);
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
							'cn'	=> "$realname",
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
`ldappasswd -D "$adminDN" -w $adminPW -s $password -x "uid=$login,$userDN"`;
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

if ($realname ne "") {
	`echo "<html><head><title>$realname</title></head><body><center>Future home of <b>${realname}'s</b> website.</body></html>" > $home/public_html/index.html`;
} else {
	`echo "<html><head><title>$login</title></head><body><center>Future home of <b>${user}'s</b> website.</body></html>" > $home/public_html/index.html`;
}
print "\t$home/public_html/index.html\n";

$hostPath = "/etc/apache2/vhosts.d/$login.conf";
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

sub makeLists {
	# makes a list of all logins and uids to check for existing...
	# then determines what the next UID should be.
	
	my @t_users = split(/\n/, `getent passwd`);
	foreach (@t_users) {
		my @data = split(/:/, $_);
		&addLogin($data[0]);
		&addUid($data[2]);
	}

	@uidList = sort { $a <=> $b } @uidList;

	my $lastUid = 0;
	foreach (@uidList) {
		if ($_ > $startUid) {
			if ($_ != $lastUid + 1) {
				$startUid = $lastUid + 1;
				return;
			}
		}
		$lastUid = $_;
	}
}

sub addUid {
	my $uid = shift;
	
	foreach (@uidList) {
		if ($_ eq $uid) {
			return;
		}
	}

	$uidList[scalar @uidList] = $uid;
}

sub addLogin {
	my $login = shift;

	foreach (@loginList) {
		if ($_ eq $login) {
			return;
		}
	}

	$loginList[scalar @loginList] = $login;
}

sub checkLogin {
	my $login = shift;

	foreach (@loginList) {
		if ($_ eq $login) {
			return 0; #false...
		}
	}
	return 1; #true...
}

sub rand_password() {
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
