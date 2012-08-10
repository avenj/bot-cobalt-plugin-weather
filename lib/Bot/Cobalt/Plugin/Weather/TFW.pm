package Bot::Cobalt::Plugin::Weather::TFW;
our $VERSION = '0.001';

use Bot::Cobalt;
use Bot::Cobalt::Common;

use strictures 1;

use HTML::TokeParser;

use HTTP::Request;

use URI::Escape;

sub BASE () { 0 }

sub new { 
  bless [
    'http://www.thefuckingweather.com/?where=',
  ], shift
}

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  register( $self, 'SERVER', qw/
    public_cmd_tfw
    fuckingweather_resp_recv
  / );

  logger->info("TFW registered");

  PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;

  logger->info("TFW unregistered");
  
  PLUGIN_EAT_NONE
}

sub Bot_public_cmd_tfw {
  my ($self, $core) = splice @_, 0, 2;
  
  my $msg = ${ $_[0] };
  
  my $zip = $msg->message_array->[0];

  unless (defined $zip && $zip =~ /^[0-9]{5}$/) {
    broadcast( 'message', $msg->context, $msg->channel,
      "I need a fucking zipcode to look up!"
    );

    return PLUGIN_EAT_ALL
  }
  
  my $req_url = $self->[BASE] . $zip ;

  broadcast( 'www_request',
    HTTP::Request->new( GET => $req_url ),
    'fuckingweather_resp_recv',
    [ $msg ]
  );

  PLUGIN_EAT_ALL
}

sub Bot_fuckingweather_resp_recv {
  my ($self, $core) = splice @_, 0, 2;
  
  my $response = ${ $_[1] };
  my $args     = ${ $_[2] };
  my ($msg)    = @$args;

  unless ($response->is_success) {
    broadcast( 'message', $msg->context, $msg->channel,
      "Failed to retrieve the fucking weather! ".$response->status_line,
    );
    
    return PLUGIN_EAT_ALL
  }
  
  my $content = $response->decoded_content;
  
  my $html = HTML::TokeParser->new( \$content );
  
  my ($location, $temp, $remark, $flavor);

  while (my $tok = $html->get_tag('span', 'p') ) {
    my $args = ref $tok->[1] eq 'HASH' ? $tok->[1] : next ;
    
    ## Location
    if ($tok->[0] eq 'span' 
        && ($args->{id}||'') eq 'locationDisplaySpan') {

      $location = $html->get_text('/span');
    }

    ## Temperature
    if ($tok->[0] eq 'span' && ($args->{class}||'') eq 'temperature') {
      $temp = ( $args->{tempf}||'undef ' ) . 'F' ;
    }
    
    ## Remark
    if ($tok->[0] eq 'p' && ($args->{class}||'') eq 'remark') {
      $remark = $html->get_text('/p');
    }
    
    ## Flavor
    if ($tok->[0] eq 'p' && ($args->{class}||'') eq 'flavor') {
      $flavor = $html->get_text('/p');
    }
  }

  my $string = "$location $temp - $remark ($flavor)";

  broadcast( 'message', $msg->context, $msg->channel,
    $string
  );

  PLUGIN_EAT_ALL
}

1;
