import 'api_client.dart';
import 'failure.dart';

/// What resolving an `@name` produced.
///
/// A sealed result rather than a nullable id, because "no such account" and
/// "could not ask" are different things to tell somebody and the caller must
/// not be able to confuse them by checking for null.
sealed class MentionResult {
  const MentionResult();
}

/// The name belongs to this account.
final class MentionFound extends MentionResult {
  const MentionFound({required this.accountId, required this.username});

  final String accountId;

  /// The name as the server spells it, which is the authority. Compared
  /// against what was tapped before anything is opened.
  final String username;
}

/// No account has this name, or it has been deleted.
final class MentionUnknown extends MentionResult {
  const MentionUnknown();
}

/// The question could not be asked, or its answer could not be trusted.
final class MentionUnavailable extends MentionResult {
  const MentionUnavailable(this.kind);

  final FailureKind kind;
}

/// Turns an `@name` into an account id, and only when somebody asks.
///
/// **Nothing here runs while a chat is being read.** A message full of names
/// would otherwise be a message full of profile lookups — a burst of requests
/// that tells the server who is reading which conversation and when, for names
/// nobody may ever tap. Detection is local (see `MessageText`); this is the one
/// request, made on the tap that needs it.
///
/// It is also the reason a mention grants nothing. The lookup is the ordinary
/// authenticated route every profile screen already uses, so visibility,
/// blocking and every other rule are decided by the server exactly as before —
/// writing somebody's name in a message cannot open a door that was shut.
class MentionResolver {
  const MentionResolver(this._api);

  final PrivioApiClient _api;

  Future<MentionResult> resolve(String username) async {
    final wanted = username.toLowerCase();
    try {
      final json = await _api.lookup(wanted);
      final id = json['id'] as String?;
      final name = (json['username'] as String?)?.toLowerCase();
      // A reply that is not about the name that was asked for opens nothing.
      // This should not happen; if it ever does, the failure mode has to be
      // "nothing opened" rather than "somebody else's profile opened".
      if (id == null || id.isEmpty || name != wanted) {
        return const MentionUnavailable(FailureKind.unexpected);
      }
      return MentionFound(accountId: id, username: wanted);
    } on ApiException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 400) {
        // 400 is a name the server will not even look up — too short, wrong
        // characters. From here that is the same answer as 404: no such
        // account, and nothing to open.
        return const MentionUnknown();
      }
      return const MentionUnavailable(FailureKind.unreachableCheckConnection);
    } on StaleSessionException {
      return const MentionUnavailable(FailureKind.unreachableCheckConnection);
    } on Object {
      // No connection, a dead socket, a reply that would not parse.
      return const MentionUnavailable(FailureKind.unreachableCheckConnection);
    }
  }
}
