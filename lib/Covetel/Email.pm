package Covetel::Email;
use Moose;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP;
use Email::MIME::Creator;
use Email::Simple;
use Try::Tiny;
use Template;
use Data::Dumper;
use utf8;

has to => ( is => 'rw', isa => 'Str');
has from => ( is => 'rw', isa => 'Str');
has subject => ( is => 'rw', isa => 'Str');
has body => ( is => 'rw', isa => 'Str');
has mta  => (
    is      => "rw",
    isa     => "Email::Sender::Transport::SMTP",
    lazy    => 1,
    builder => '_mta_default',  
);

sub _mta_default {
    my $self = shift; 
    my $transport = Email::Sender::Transport::SMTP->new({
        host => 'mail.cantv.net',
        port => 25,
    });
} 

sub send {
    my $self = shift;
    
    my @mimeparts = (
        Email::MIME->create(
            attributes => { 
                content_type => 'text/plain', 
                charset => 'utf8',
            },
            body => $self->body(),
        )
    );
    
    my $message = Email::MIME->create(
        header => [
            From    => $self->from, 
            To      => $self->to, 
            Cc      => 'walter@covetel.com.ve', 
            Subject => $self->subject, 
        ], 
        parts => [@mimeparts],
    );
    
    $message->charset_set('utf8');
    $message->encoding_set( '8bit' );
    
    try {
        sendmail($message, { transport => $self->mta });
        print "Sending mail to ".$self->to." OK. \n"
    } catch {
        warn "Sending failed: $_";
    }
}

sub body_process {
    my ($self, $vars) = @_;
    my $output;
    my $template = Template::->new({ENCODING => 'utf8'});
    my $input = $vars->{'input'};
    $template->process($input, $vars, \$output);
    $self->body($output);
}


1;
