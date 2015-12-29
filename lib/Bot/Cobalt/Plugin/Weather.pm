package Bot::Cobalt::Plugin::Weather;

use List::Objects::WithUtils;

use Bot::Cobalt;
use Bot::Cobalt::Common;

use POE;
use POEx::Weather::OpenWeatherMap;

sub new { bless +{}, shift }

sub pwx { $_[1] ? $_[0]->{pwx} = $_[1] : $_[0]->{pwx} }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  POE::Session->create(
    object_states => [
      $self => [ qw/
        _start

        pwx_error
        pwx_weather
        pwx_forecast
      / ],
    ],
  );

  register( $self, SERVER =>
    'public_cmd_wx',
  );

  logger->info("Loaded: wx");

  PLUGIN_EAT_NONE
}


sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  logger->info("Shutting down POEx::Weather::OpenWeatherMap ...");
  $self->pwx->stop if $self->pwx;
  logger->info("wx unloaded");
  PLUGIN_EAT_NONE
}


sub _start {
  my $self = $_[OBJECT];

  my $pcfg = core->get_plugin_cfg($self);
  my $api_key  = $pcfg->{API_Key};
  my $do_cache = $pcfg->{DisableCache} ? 0 : 1;

  unless (defined $api_key) {
    logger->warn($_) for
      "No 'API_Key' found in plugin configuration!",
      "Requests will likely fail."
  }

  # FIXME configurable cache_dir / cache_expiry
  $self->pwx(
    POEx::Weather::OpenWeatherMap->new(
      ( defined $api_key ? (api_key => $api_key) : () ),
      ( $do_cache ? (cache => 1) : () ),
      event_prefix  => 'pwx_',
    )
  );

  $self->pwx->start;
}

sub pwx_error {
  my $self    = $_[OBJECT];
  my $err     = $_[ARG0];
  my $tag     = $err->request->tag;

  logger->warn("POEx::Weather::OpenWeatherMap failure: $err");
  broadcast( 
    message => $tag->context => $tag->channel =>
      "wx: error: $err"
  );
}

sub pwx_weather {
  my $self    = $_[OBJECT];
  my $res     = $_[ARG0];
  my $tag     = $res->request->tag;

  my $place   = $res->name;

  my $tempf   = $res->temp_f;
  my $tempc   = $res->temp_c;
  my $humid   = $res->humidity;

  my $wind    = $res->wind_speed_mph;
  my $gust    = $res->wind_gust_mph;
  my $winddir = $res->wind_direction;

  my $terse   = $res->conditions_terse;
  my $verbose = $res->conditions_verbose;

  my $hms = $res->dt->hms;

  my $str = "$place at ${hms}UTC: ${tempf}F/${tempc}C";
  $str .= " and ${humid}% humidity;";
  $str .= " wind is ${wind}mph $winddir";
  $str .= " gusting to ${gust}mph" if $gust;
  $str .= ". Current conditions: ${terse}: $verbose";

  broadcast( message => $tag->context => $tag->channel => $str );
}

sub pwx_forecast {
  my $self    = $_[OBJECT];
  my $res     = $_[ARG0];
  my $tag     = $res->request->tag;
  my $place   = $res->name;

  broadcast( 
    message => $tag->context => $tag->channel => 
      "Forecast for $place ->"
  );

  if ($res->hourly) {
    for my $hr ($res->as_array->sliced(1..3)->all) {
      my $date    = $hr->dt->hms;
      my $temp    = $hr->temp;
      my $temp_c  = $hr->temp_c;

      my $terse   = $hr->conditions_terse;
      my $verbose = $hr->conditions_verbose;

      my $wind    = $hr->wind_speed_mph;
      my $winddir = $hr->wind_direction;

      my $rain    = $hr->rain;
      my $snow    = $hr->snow;

      my $str = "${date}UTC: ${temp}F/${temp_c}C";
      $str .= ", wind $winddir at ${wind}mph";
      $str .= ", ${terse}: $verbose";
      $str .= ", rain ${rain}in" if $rain;
      $str .= ", snow ${snow}in" if $snow;
      broadcast( message => $tag->context => $tag->channel => $str );
    }
  } else {
    my $itr = $res->iter;
    while (my $day = $itr->()) {
      my $date = $day->dt->day_name;

      my $temp_hi_f = $day->temp_max_f;
      my $temp_lo_f = $day->temp_min_f;
      my $temp_hi_c = $day->temp_max_c;
      my $temp_lo_c = $day->temp_min_c;

      my $terse     = $day->conditions_terse;
      my $verbose   = $day->conditions_verbose;

      my $wind      = $day->wind_speed_mph;
      my $winddir   = $day->wind_direction;

      my $str = "${date}: High of ${temp_hi_f}F/${temp_hi_c}C";
      $str .= ", low of ${temp_lo_f}F/${temp_lo_c}C";
      $str .= ", wind $winddir at ${wind}mph";
      $str .= "; $terse: $verbose";

      broadcast( message => $tag->context => $tag->channel => $str );
    }
  }
}


sub Bot_public_cmd_wx {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${ $_[0] };

  my ($location, $fcast, $hourly);
  my @parts = @{ $msg->message_array };
  if ( ($parts[0] || '') eq 'forecast' ) {
    $location = join ' ', @parts[1 .. $#parts];
    $fcast++
  } elsif ( ($parts[0] || '') eq 'hourly' ) {
    $location = join ' ', @parts[1 .. $#parts];
    $hourly++;
  } elsif (!@parts) {
    broadcast( message => $msg->context => $msg->channel =>
      $msg->src_nick . ": no location specified"
    );
    return PLUGIN_EAT_NONE
  } else {
    $location = join ' ', @parts
  }

  my $tag = hash(
    context => $msg->context,
    channel => $msg->channel,
  )->inflate;

  $self->pwx->get_weather(
    location => $location,
    tag      => $tag,
    ( $fcast  ? (forecast => 1, days => 3) : () ),
    ( $hourly ? (forecast => 1, hourly => 1, days => 1) : () ),
  );

  PLUGIN_EAT_NONE
}

1;

=pod

=head1 NAME

Bot::Cobalt::Plugin::Weather - Weather retrieval plugin for Bot::Cobalt

=head1 SYNOPSIS

  # In your plugins.conf:
  WX:
    Module: Bot::Cobalt::Plugin::Weather
    Opts:
      API_Key: "my OpenWeatherMap API key here"
      # Optionally disable caching:
      #DisableCache: 1

  # On IRC:
  > !wx Boston, MA
  > !wx forecast Toronto, Canada
  > !wx hourly Moscow, Russia

=head1 DESCRIPTION

A weather conditions/forecast retrieval plugin for L<Bot::Cobalt>.

Uses L<http://www.openweathermap.org/> via L<POEx::Weather::OpenWeatherMap> /
L<Weather::OpenWeatherMap> for retrieval.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
