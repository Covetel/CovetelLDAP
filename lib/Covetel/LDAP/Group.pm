package Covetel::LDAP::Group;
use Moose; 
use Covetel::LDAP;
use Net::LDAP::Entry;
use utf8;
use 5.010;

has entry    => (
    is      => "ro",
    isa     => "Net::LDAP::Entry",
    lazy    => 1,
    builder => "_build_entry"
);

has dn 	=> (
    is      => "ro",
	isa 	=> 'Str',
    lazy    => 1,
    builder => "_build_dn"
);

has ldap => (
	is 		=> "ro",
    isa     => "Covetel::LDAP",
    lazy    => 1,
    builder => "_build_ldap",
);

has nombre => (
    is      => "rw", 
    isa     => "Str", 
);

has description => (
    is      => "rw", 
    isa     => "Str", 
);

has gidNumber => (
	is 		=> 'rw',
	isa 	=> 'Int', 
	lazy 	=> 0, 
    builder => "_build_gidNumber",
);

has members => (
    is      => 'rw', 
    isa     => 'ArrayRef'
);

sub add_member {
	my ($self, $uid) = @_;
    my $members = $self->members; 

    unless ($uid ~~ @{$members}) {
        push @{$members}, $uid;
        $self->members($members);
    } 
} 

sub _base_groups {
    my $self = shift; 
    my $base = $self->ldap->config->{'Covetel::LDAP'}->{'base_grupos'};
    return $base;
}

sub _build_dn {
	my $self = shift;
	
    my $base = $self->ldap->config->{'Covetel::LDAP'}->{'base_grupos'};
	my $dn = 'cn='.$self->nombre.','.$base;
}


sub _build_gidNumber {
    my $self = shift; 

    my $base = $self->ldap->config->{'Covetel::LDAP'}->{'base_mantenimiento'};
    my $g_mantenimiento = $self->ldap->config->{'Covetel::LDAP'}->{'grupo_mantenimiento'};

    # Obtengo el uid del grupo de mantenimiento. 
    my $resp = $self->ldap->search({
            base => $base,
            filter => "($g_mantenimiento)", 
            scope => 'one', 
            attrs => ['gidNumber'] , 
    });

    if ($resp->count() > 0){
        my $gidNumber = $resp->entry(0)->get_value('gidNumber'); 
        return ++$gidNumber;
    } else {
        die "Problemas con el grupo de mantenimiento en el LDAP"; 
    }
    
}

sub _build_entry {
	my $self = shift;
	my $entry = Net::LDAP::Entry->new;

	$entry->dn($self->dn);

	$entry->add(objectClass => ['top', 'posixGroup']);
	$entry->add(cn => $self->nombre);
	$entry->add(gidNumber => $self->gidNumber);
    $entry->add(description => $self->description);
    $entry->add(memberUid => $self->members);

    return $entry;
}

sub _build_ldap {
	my $self = shift;
	my $ldap = Covetel::LDAP->new;
	return $ldap;
}

sub add {
	my $self = shift;

	my $mesg = $self->ldap->server->add($self->entry);
	$self->ldap->message($mesg);
	if ($mesg->is_error()){
		return 0;
	} else {
        # Incremento el valor uidNumber en el usuario de mantenimiento. 
        my $base = $self->ldap->config->{'Covetel::LDAP'}->{'base_mantenimiento'};
        my $g_mantenimiento = $self->ldap->config->{'Covetel::LDAP'}->{'grupo_mantenimiento'};
        my $dn = "$g_mantenimiento,$base";
        my $mesg = $self->ldap->server->modify( $dn,
            increment => {
                gidNumber => 1 # increment gidNumber by 1
            }
        );
        if ($mesg->is_error()){
            die "Problemas al incrementar el ID del grupo de mantenimiento";
        } else {
		    return 1;
        }
	}
}

sub del {
	my $self = shift;
	my $mesg = $self->ldap->server->delete($self->dn);
	$self->ldap->message($mesg);
	if ($mesg->is_error()){
		return 0;
	} else {
		return 1;
	}
}


sub update {
    my $self = shift; 
    my $entry = $self->entry;
    $entry->replace(
        description => $self->description, 
        gidNumber => $self->gidNumber,  
        memberUid => $self->members, 
    );
    my $mesg = $entry->update($self->ldap->server);
    if ($mesg->is_error()){
        die "Problemas al actualizar la entrada Group->update";
    } else {
       return 1;
    }
}

1;
