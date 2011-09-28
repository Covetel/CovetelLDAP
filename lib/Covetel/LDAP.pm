package Covetel::LDAP;
use Moose; 
use Net::LDAP;
use Net::LDAPS;
use Config::Any::YAML;
use utf8;
use Data::Dumper;
use 5.010;

has server  => (
    is      => "ro",
    isa     => "Net::LDAP",
    lazy    => 1,
    builder => "_build_server"
);

has message => (
    is      => "rw",
    isa     => "Net::LDAP::Message",
);

has config_file => (
    is      => "rw",
    isa     => "Str",
);

has base => (
    is      => "rw",
    isa     => "Str",
	lazy 	=> 1,
	builder => "_build_base",
);

has config => (is => "ro", isa => "HashRef", lazy => 1, builder => "_build_config" );

sub _build_config {
    my $self = shift; 
	my $default_file = 'config.yml';
    if ($ENV{COVETEL_LDAP_CONFIG}){
       $self->config_file($ENV{COVETEL_LDAP_CONFIG});
    }else{
		$self->config_file($default_file);
	} 
	my $c = Config::Any::YAML->load($self->config_file);
	return $c;	
}

sub _build_base {
	my $self = shift; 
	my $base = $self->config->{'Covetel::LDAP'}->{'base'};
	return $base;
}

sub person {
	my ($self, $attrs) = @_;
    $attrs = {objectClass => "posixAccount"} unless $attrs;
	my $filter;
	my @keys = keys %{$attrs};
	foreach (@keys){
		$filter .= "($_=$attrs->{$_})";
	}
	if ($#keys > 0){
		$filter = "(|".$filter.")";
	}
	my $base = $self->config->{'Covetel::LDAP'}->{'base_personas'};
	my $resp = $self->search({base => $base, filter => $filter, attrs =>
            ['uid','cn','sn','givenName','dn', 'uidNumber', 'mail', 'pager']});
	my @personas;
	if ($resp->count() > 0){
		foreach my $e ($resp->entries()){
            my $person = Covetel::LDAP::Person->new(
                {
                    uid       => $e->get_value('uid'),
                    firstname => $e->get_value('givenName'),
					lastname  => $e->get_value('sn'),
					uidNumber => $e->get_value('uidNumber'),
					email => $e->get_value('mail') // '--' ,
					ced => $e->get_value('pager') // '--',
					dn  => $e->dn,
                    ldap    => $self, 
                }
            );
			push @personas, $person;
		}	
		if (wantarray){
			return @personas; 
		} else {
			return $personas[0];
		}
	} else {
		return 0;
	}
}

sub group {
	my ($self, $attrs) = @_;
    $attrs = {objectClass => "posixGroup"} unless $attrs;
	my $filter;
	my @keys = keys %{$attrs};
	foreach (@keys){
		$filter .= "($_=$attrs->{$_})";
	}
	if ($#keys > 0){
		$filter = "(|".$filter.")";
	}
	my $base = $self->config->{'Covetel::LDAP'}->{'base_grupos'};
	my $resp = $self->search({base => $base, filter => $filter, attrs =>
            ['cn','description', 'gidNumber', 'memberUid']});
	my @grupos;
	if ($resp->count() > 0){
		foreach my $e ($resp->entries()){
            my $group = Covetel::LDAP::Group->new({
                    nombre       => $e->get_value('cn'),
                    description => $e->get_value('description'),
                    gidNumber => $e->get_value('gidNumber'),
                    members => [$e->get_value('memberUid')],
                    entry   => $e, 
                    ldap    => $self, 
                });
			push @grupos, $group;
		}	
		if (wantarray){
			return @grupos; 
		} else {
			return $grupos[0];
		}
	} else {
		return 0;
	}
}

sub search {
	my ($self, $options) = @_;
	my ($base, $attrs, $filter);
	
	#the base of the search. 
	if (!$options->{'base'}){
		$base = $self->base();
	} else {
		$base = $options->{'base'};
	}

    my $scope = $options->{'scope'} // 'sub';
	
	# attrs list.
	if (!$options->{'attrs'}){
		$attrs = ['cn','uid','mail'];
	} else {
		$attrs = $options->{'attrs'};
	}
	
	# default filter
	if (!$options->{'filter'}){
        $filter = '';
	} else {
		$filter = $options->{'filter'};
	}

    my $result = $self->server->search(
        base   => $base,
        scope  => $scope,
        filter => $filter,
        attrs  => $attrs
    );

	return $result;
}

sub _build_server {
	my $self = shift; 
	my $host = $self->config->{'Covetel::LDAP'}->{'host'};
	my $dn = $self->config->{'Covetel::LDAP'}->{'dn'};
	my $pw = $self->config->{'Covetel::LDAP'}->{'password'};
	my $ldap;	
	if ($self->config->{'Covetel::LDAP'}->{'start_tls'}){
		$ldap = Net::LDAPS->new($host);
	} else {
		$ldap = Net::LDAP->new($host);
	}
	$ldap->bind( $dn, password => $pw );	

	return $ldap;
}


sub create_ou {
	my ($self, $ou, $options) = @_;
	my $base = $options->{'base'};
	my $desc = $options->{'description'};

	if (!$base || $base eq ''){
		$base = $self->config->{'Covetel::LDAP'}->{'base'};
	}
	my $dn = 'ou='.$ou.','.$base;
    my $mesg = $self->server->add( $dn,
        attrs => [ ou => $ou, description => $desc , objectClass => ['organizationalUnit']]
	);
	
	if ($mesg->is_error()){
		return (0, $mesg->mesg_id());
	} else {
		return 1;
	}
}

sub delete_ou {
	my ($self, $ou, $options) = @_;
	my $base = $options->{'base'};
	if (!$base || $base eq ''){
		$base = $self->config->{'Covetel::LDAP'}->{'base'};
	}

	my $dn = 'ou='.$ou.','.$base;
	my $mesg = $self->server->delete( $dn );
	
	if ($mesg->is_error()){
		return (0, $mesg->mesg_id());
	} else {
		return 1;
	}
}

sub error_str {
	my $self = shift; 
	my $mesg = $self->message;
    my $str = "Error". $mesg->mesg_id;
    $str .= $mesg->error_desc();
    $str .= $mesg->error();
    $str .= $mesg->error_text();
    $str .= $mesg->server_error();
    return $str;
}

sub print_error {
	my $self = shift; 
	my $mesg = $self->message;
	print "Error (".$mesg->mesg_id."): \n\n";
	print $mesg->error_desc();
	print "\n\n";
	print $mesg->error();
	print "\n\n";
}

1;
