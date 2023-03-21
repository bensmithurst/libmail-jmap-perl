package Mail::JMAP;

use strict;
use warnings;
use Moose;

use Data::Dumper;
use English qw(-no_match_vars);
use JSON;
use LWP;
use Readonly;

Readonly my $KEY_FILE => "$ENV{HOME}/.fastmail-api-key";

Readonly my $PARAM_CORE => 'urn:ietf:params:jmap:core';
Readonly my $PARAM_SUBMISSION => 'urn:ietf:params:jmap:submission';
Readonly my $PARAM_MAIL => 'urn:ietf:params:jmap:mail';

Readonly my $PARAM_MASKED_EMAIL => 'https://www.fastmail.com/dev/maskedemail';

Readonly my $SESSION => 'https://api.fastmail.com/jmap/session';

has apiKey => (is => 'ro', isa => 'Str', lazy => 1, default => \&__makeApiKey);

has accountId => (is => 'rw', isa => 'Str');

has __apiUrl => (is => 'rw', isa => 'Str');

has __ua => (is => 'rw', isa => 'LWP::UserAgent', lazy => 1, default => sub {
	return LWP::UserAgent->new;
});

sub init {
	my ($self) = @_;

	my $session = $self->__apiRequest('GET', $SESSION);
	$self->accountId($session->{primaryAccounts}->{$PARAM_MAIL})
		or die 'Cannot find your primary account';

	$self->__apiUrl($session->{apiUrl});

	return;
}

sub getFromQuery {
	my ($self, $object, $filter) = @_;

	my $ids = $self->query($object, $filter);

	return [] unless @$ids;

	# arbtirary limit
	@$ids = @{$ids}[0..999] if scalar(@$ids) > 1000;

	return $self->get($object, $ids);
}

sub get {
	my ($self, $object, $ids) = @_;

	my $scope = $self->__getScopeForObject($object);
	my $response = $self->apiCall({
		using => $scope,
		methodCalls => [
			[ "$object/get", {
				accountId => $self->accountId,
				ids => $ids,
			}, ++$self->{__call} ],
		],
	});

	my $list = $response->{methodResponses}->[0]->[1]->{list};
	die Dumper($response) unless $list;

	return $list;
}

sub query {
	my ($self, $object, $filter) = @_;

	my $response = $self->apiCall({
		using => [ $PARAM_MAIL ],
		methodCalls => [
			[ "$object/query", {
				accountId => $self->accountId,
				filter => $filter,
			}, ++$self->{__call} ],
		],
	});

	my $ids = $response->{methodResponses}->[0]->[1]->{ids};
	die Dumper($ids) unless $ids;

	return $ids;
}

sub update {
	my ($self, $object, $changes) = @_;

	$self->set($object, 'update', $changes);

	return;
}

sub create {
	my ($self, $object, $data) = @_;

	$self->set($object, 'create', $data);

	return;
}

sub set {
	my ($self, $object, $action, $data) = @_;

	# TODO check for failure
	my $scope = $self->__getScopeForObject($object);
	my $response = $self->apiCall({
		using => $scope,
		methodCalls => [
			[ "$object/set", {
				accountId => $self->accountId,
				$action => $data,
			}, ++$self->{__call} ],
		],
	});

	print Dumper $response;

	return;
}

sub apiCall {
	my ($self, $data) = @_;
	return $self->__apiRequest('POST', $self->__apiUrl, encode_json($data));
}

sub __apiRequest {
	my ($self, $method, $url, $content) = @_;

	my $request = HTTP::Request->new($method, $url, undef, $content);
	$request->header('Authorization', 'Bearer '.$self->apiKey);
	$request->header('Content-Type', 'application/json') if defined $content;

	my $response = $self->__ua->request($request);

	if (!$response->is_success) {
		die $request->as_string()."\n".$response->as_string();
	}

	return decode_json($response->content);
}

sub __makeApiKey {
	my ($self) = @_;

	my $file = $ENV{JMAP_KEY_FILE} // $KEY_FILE;

	my $fh = IO::File->new($file, 'r') or die "Cannot open $file: $ERRNO";
	my $key = <$fh>;

	die "EOF on $file" unless defined $key;

	chop($key);
	return $key;
}

sub __getScopeForObject {
	my ($self, $object) = @_;

	return [ $PARAM_MASKED_EMAIL ] if $object eq 'MaskedEmail';

	return [ $PARAM_SUBMISSION ] if $object eq 'Identity';

	return [ $PARAM_MAIL ];
}

1;
