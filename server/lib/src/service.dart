import 'dart:convert';

import 'package:jose/jose.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'cloud_headers.dart';
import 'firestore_election_storage.dart';
import 'service_config.dart';
import 'service_exception.dart';
import 'token_helpers.dart';

part 'service.g.dart';

class VoteService {
  final FirestoreElectionStorage _storage;

  final ServiceConfig config;

  String get _projectId => config.projectId;

  final _store = JsonWebKeyStore();

  VoteService({
    required FirestoreElectionStorage storage,
    required this.config,
    required Iterable<Uri> keySetUrls,
  }) : _storage = storage {
    for (var uri in keySetUrls) {
      _store.addKeySetUrl(uri);
    }
  }

  @Route.get('/api/config.js')
  Response getConfig(Request request) => Response.ok(
        '''
firebase.initializeApp(${jsonEncode(config.firebaseConfig())});
firebase.analytics();
''',
        headers: {
          'content-type': 'application/javascript',
          'cache-control': 'public',
        },
      );

  @Route.put('/api/ballots/<electionId>/')
  Future<Response> updateBallot(Request request, String electionId) async {
    final userId = await _jwtSubjectFromRequest(request);

    final newRank = jsonDecode(await request.readAsString()) as double;
    await _storage.updateBallot(userId, newRank);

    return _okJsonResponse({});
  }

  @Route.post('/api/elections/<electionId>/update')
  Future<Response> updateElectionResult(
    Request request,
  ) async {
    final queueName = request.headers[googleCloudTaskQueueName];

    if (queueName != config.electionUpdateTaskQueueId) {
      throw ServiceException(
        ServiceExceptionKind.badUpdateRequest,
        'Bad value for `$googleCloudTaskQueueName` header. Got "$queueName", '
        'expected "${config.electionUpdateTaskQueueId}"',
      );
    }

    if (request.requestedUri.isScheme('https')) {
      await _jwtFromRequest(request, expectServiceRequest: true);
    } else {
      print('* Not HTTPS - assuming local request to ${request.requestedUri}');
    }

    await _storage.updateElection();

    return Response.ok('Update succeeded for election');
  }

  Router get router => _$VoteServiceRouter(this);

  Future<String> _jwtSubjectFromRequest(Request request) async {
    final jwt = await _jwtFromRequest(request, expectServiceRequest: false);

    final hasAudience = jwt.claims.audience?.contains(_projectId);

    if (hasAudience != true) {
      throw ServiceException.authorizationTokenValidation(
        'Audience does not contain expected project "$_projectId".',
      );
    }

    return jwt.claims.subject!;
  }

  Future<JsonWebToken> _jwtFromRequest(
    Request request, {
    required bool expectServiceRequest,
  }) async {
    JsonWebToken? jwt;
    try {
      jwt = await tokenFromRequest(request, _store);
    } catch (error, stack) {
      throw ServiceException(
        ServiceExceptionKind.authorizationTokenValidation,
        'Error parsing the authorization header.',
        innerError: error,
        innerStack: stack,
      );
    }

    if (jwt == null) {
      throw ServiceException.authorizationTokenValidation(
        'No authorization information present.',
      );
    }

    if (jwt.isVerified == true) {
      if (expectServiceRequest) {
        if (jwt.claims['email_verified'] == true &&
            jwt.claims['email'] == config.serviceAccountEmail) {
          return jwt;
        }

        print(prettyJson(jwt.claims));
        throw ServiceException.authorizationTokenValidation(
          'Expected a verified email associated with the configured service '
          'account.',
        );
      }
      return jwt;
    }

    throw ServiceException.authorizationTokenValidation(
      'Token could not be verified.',
    );
  }
}

Response _okJsonResponse(Object json) => Response.ok(
      jsonEncode(json),
      headers: {
        'Content-Type': 'application/json',
      },
    );
