import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport/api.dart';
import 'package:sport/main.dart';

class FakeApi extends Api {
  Map<String, dynamic>? account, team;
  String? failure;
  final List<dynamic> teams = [], invitations = [];
  final List<Map<String, dynamic>> calls = [];
  @override
  Future<Map<String, dynamic>> call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add({'method': method, 'path': path, 'body': body});
    if (failure != null) throw ApiException(failure!);
    if (path == '/me') return {'user': account, 'team': team};
    if (path == '/teams' && method == 'GET') return {'teams': teams};
    if (path == '/teams' && method == 'POST') {
      team = {
        'id': 't',
        'name': body!['name'],
        'city': body['city'],
        'description': body['description'],
        'logo': '',
        'active': 1,
        'coach_id': account!['id'],
        'members': [],
      };
      teams.add(team);
      return {'team': team};
    }
    if (path == '/tournaments') return {'tournaments': []};
    if (path == '/matches') return {'matches': []};
    if (path == '/notifications') return {'notifications': []};
    if (path == '/invitations') return {'invitations': invitations};
    if (path.startsWith('/invitations/') && method == 'PATCH') {
      invitations.first['status'] = body!['status'];
      return {'ok': true};
    }
    if (path == '/register') {
      account = {
        'id': '1',
        'name': body!['name'],
        'email': body['email'],
        'role': body['role'],
        'phone': body['phone'],
        'active': 1,
      };
      return {'token': 'test-token', 'user': account};
    }
    if (path == '/logout') {
      account = null;
      team = null;
      return {'ok': true};
    }
    throw ApiException('Unexpected route $method $path');
  }
}

void main() {
  testWidgets('mobile guest sees one user flow and no admin creation buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MyApp(api: FakeApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Командалар'));
    await tester.pumpAndSettle();
    expect(find.text('Команда құру'), findsNothing);
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тіркелу'));
    await tester.pumpAndSettle();
    expect(find.text('Пайдаланушы'), findsOneWidget);
    expect(find.text('Жаттықтырушы'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Әкімші'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('coach cannot skip team onboarding and creates a team', (
    tester,
  ) async {
    final api = FakeApi()
      ..account = {
        'id': 'c',
        'name': 'Coach',
        'email': 'coach@example.test',
        'phone': '',
        'role': 'coach',
        'active': 1,
      };
    await tester.pumpWidget(MyApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Командаңызды жасаңыз'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Команда құру'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Қыран');
    await tester.enterText(find.byType(TextFormField).at(1), 'Астана');
    await tester.enterText(find.byType(TextFormField).at(2), 'Жаңа команда');
    await tester.ensureVisible(find.text('Сақтау'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сақтау'));
    await tester.pumpAndSettle();
    expect(api.team!['name'], 'Қыран');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('user explicitly accepts invitation from profile', (
    tester,
  ) async {
    final api = FakeApi()
      ..account = {
        'id': 'p',
        'name': 'Player',
        'email': 'p@example.test',
        'phone': '',
        'role': 'user',
        'active': 1,
      };
    api.invitations.add({'id': 'i', 'team_name': 'Қыран', 'status': 'pending'});
    await tester.pumpWidget(MyApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Қабылдау'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Қабылдау'));
    await tester.pumpAndSettle();
    expect(
      api.calls.any(
        (c) =>
            c['path'] == '/invitations/i' && c['body']['status'] == 'accepted',
      ),
      true,
    );
    expect(find.text('Қабылданды'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('network errors have a retry action', (tester) async {
    final api = FakeApi()..failure = 'Серверге қосылу мүмкін болмады.';
    await tester.pumpWidget(MyApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Қайталау'), findsOneWidget);
    api.failure = null;
    await tester.tap(find.text('Қайталау'));
    await tester.pumpAndSettle();
    expect(find.text('Қайталау'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
