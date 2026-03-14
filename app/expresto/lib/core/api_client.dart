import 'package:flutter/foundation.dart';
import 'package:gql/ast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static late ValueNotifier<GraphQLClient> client;
  static String? authToken;

  static Future<void> init() async {
    await initHiveForFlutter();

    final prefs = await SharedPreferences.getInstance();
    authToken = prefs.getString('auth_token');

    client = ValueNotifier(_buildClient());
  }

  /// Call this after login/register to update the existing ValueNotifier
  /// so GraphQLProvider picks up the new token without a rebuild.
  static Future<void> updateToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    authToken = token;
    client.value = _buildClient();
  }

  static GraphQLClient _buildClient() {
    final HttpLink httpLink = HttpLink('http://10.113.21.127:8000/graphql');

    final AuthLink authLink = AuthLink(
      getToken: () async => authToken != null ? 'Bearer $authToken' : null,
    );

    final WebSocketLink websocketLink = WebSocketLink(
      'ws://10.113.21.127:8000/graphql',
      config: SocketClientConfig(
        autoReconnect: true,
        inactivityTimeout: const Duration(seconds: 30),
        initialPayload: () async {
          return {
            'Authorization': authToken != null ? 'Bearer $authToken' : '',
          };
        },
      ),
    );

    Link link = authLink.concat(httpLink);
    link = Link.split(
      (request) => _isSubscription(request),
      websocketLink,
      link,
    );

    return GraphQLClient(
      link: link,
      cache: GraphQLCache(store: HiveStore()),
    );
  }

  static bool _isSubscription(Request request) {
    final definitions = request.operation.document.definitions;
    return definitions.whereType<OperationDefinitionNode>().any(
      (def) => def.type == OperationType.subscription,
    );
  }
}
