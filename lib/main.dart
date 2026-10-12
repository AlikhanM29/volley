import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';
import 'teams.dart';
import 'events.dart';
import 'admin.dart';
import 'search.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.api});
  final Api? api;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Volley',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF1F5FC),
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        primary: blue,
        secondary: yellow,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: blue,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
    ),
    home: WelcomePage(api: api),
  );
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, this.api});
  final Api? api;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Container(
              width: 112,
              height: 112,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: blue,
                shape: BoxShape.circle,
              ),
              child: const Text('🏐', style: TextStyle(fontSize: 54)),
            ),
            const SizedBox(height: 32),
            const Text(
              'Қош келдіңіз!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'Volley - волейбол командаларын, матчтар мен турнирлерді бір жерде басқаруға арналған қосымша.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.45, color: Color(0xFF4A5568)),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => Home(api: api)),
              ),
              child: const Text('Жалғастыру'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Командаңды құр, матчтарды бақыла және турнирлерге қатыс.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF718096)),
            ),
          ],
        ),
      ),
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, this.api});
  final Api? api;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final api = widget.api ?? Api();
  Json? user, ownTeam;
  List<dynamic> teams = [],
      matches = [],
      tournaments = [],
      invitations = [],
      notifications = [];
  bool loading = false;
  String? error;
  int tab = 0;
  Timer? poll;
  bool get admin => user?['role'] == 'admin';
  bool get onboarding => user?['role'] == 'coach' && ownTeam == null;
  @override
  void initState() {
    super.initState();
    load();
    poll = Timer.periodic(const Duration(seconds: 20), (_) => inbox());
  }

  @override
  void dispose() {
    poll?.cancel();
    api.close();
    super.dispose();
  }

  Future<void> inbox() async {
    if (user == null) return;
    final uid = user!['id'];
    try {
      final r = await Future.wait([
        api.call('GET', '/invitations'),
        api.call('GET', '/notifications'),
      ]);
      if (mounted && user?['id'] == uid) {
        setState(() {
          invitations = r[0]['invitations'];
          notifications = r[1]['notifications'];
        });
      }
    } catch (_) {
      /* Keep the current inbox; explicit refresh reports connection errors. */
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await Future.wait([
        api.call('GET', '/me'),
        api.call('GET', '/teams'),
        api.call('GET', '/matches'),
        api.call('GET', '/tournaments'),
      ]);
      if (mounted) {
        setState(() {
          user = r[0]['user'];
          ownTeam = r[0]['team'];
          teams = r[1]['teams'];
          matches = r[2]['matches'];
          tournaments = r[3]['tournaments'];
          if (user == null) {
            invitations = [];
            notifications = [];
          }
        });
      }
      await inbox();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await load();
  }

  Future<void> auth(bool register) async {
    await open(AuthPage(api: api, register: register));
    if (mounted) setState(() => tab = 4);
  }

  Future<void> action(String method, String path, [Json? body]) async {
    setState(() => error = null);
    try {
      await api.call(method, path, body);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          Icon(Icons.sports_volleyball, color: yellow),
          SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                'VOLLEY',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (user != null)
          IconButton(
            tooltip: 'Хабарламалар',
            onPressed: () => setState(() => tab = 4),
            icon: Badge(
              isLabelVisible: notifications.any((n) => n['read_at'] == null),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        IconButton(
          tooltip: 'Іздеу',
          onPressed: () => open(SearchPage(api: api, user: user)),
          icon: const Icon(Icons.search),
        ),
        IconButton(
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Жаңарту',
        ),
      ],
    ),
    body: pageBody([
      if (loading) const LinearProgressIndicator(),
      if (error != null) ...[
        errorBox(error),
        TextButton(onPressed: load, child: const Text('Қайталау')),
      ],
      if (onboarding) ...[
        heading('Командаңызды жасаңыз'),
        empty(
          'Жаттықтырушы тіркелуін аяқтау үшін команда атауын, қаласын және сипаттамасын енгізіңіз.',
        ),
        FilledButton.icon(
          onPressed: () => open(TeamEditor(api: api, user: user!)),
          icon: const Icon(Icons.groups),
          label: const Text('Команда құру'),
        ),
        TextButton(onPressed: logout, child: const Text('Шығу')),
      ] else if (tab == 0)
        ...home()
      else if (tab == 1)
        ...matchList()
      else if (tab == 2)
        ...tournamentList()
      else if (tab == 3)
        ...teamList()
      else
        ...profile(),
    ]),
    bottomNavigationBar: onboarding
        ? null
        : NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (v) => setState(() => tab = v),
            indicatorColor: yellow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Басты бет',
              ),
              NavigationDestination(
                icon: Icon(Icons.sports_volleyball_outlined),
                label: 'Матчтар',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_tree_outlined),
                label: 'Турнирлер',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_outlined),
                label: 'Командалар',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Профиль',
              ),
            ],
          ),
  );
  List<Widget> home() => [
    Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [blue, Color(0xFF093384)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ҚАЗАҚСТАН • ВОЛЕЙБОЛ',
            style: TextStyle(
              color: yellow,
              letterSpacing: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Бір команда.\nОртақ жеңіс.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Командалар, матчтар және турнирлер — бір жерде.',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: yellow,
              foregroundColor: navy,
            ),
            onPressed: () => setState(
              () => tab = admin
                  ? 2
                  : user == null
                  ? 4
                  : 3,
            ),
            child: Text(
              admin
                  ? 'Турнирлерді басқару'
                  : user == null
                  ? 'Қауымдастыққа қосылу'
                  : 'Командаларды көру',
            ),
          ),
        ],
      ),
    ),
    heading('Алдағы матчтар'),
    if (matches.isEmpty && !loading && error == null) empty('Әзірге матч жоқ.'),
    ...matches
        .where((m) => m['winner_id'] == null)
        .take(3)
        .map(
          (m) => MatchCard(
            match: m,
            onTap: admin ? () => open(MatchPage(api: api, match: m)) : null,
          ),
        ),
    heading('Турнирлер'),
    ...tournamentCards(tournaments.take(3).toList()),
  ];
  List<Widget> matchList() => [
    heading('Матчтар'),
    if (admin)
      FilledButton.icon(
        onPressed: () => open(EventEditor(api: api, tournament: false)),
        icon: const Icon(Icons.add),
        label: const Text('Матч құру'),
      ),
    const SizedBox(height: 16),
    if (matches.isEmpty && !loading && error == null) empty('Әзірге матч жоқ.'),
    ...matches.map(
      (m) => MatchCard(
        match: m,
        onTap: admin ? () => open(MatchPage(api: api, match: m)) : null,
      ),
    ),
  ];
  List<Widget> tournamentList() => [
    heading('Турнирлер'),
    if (admin)
      FilledButton.icon(
        onPressed: () => open(EventEditor(api: api, tournament: true)),
        icon: const Icon(Icons.add),
        label: const Text('Турнир құру'),
      ),
    const SizedBox(height: 16),
    ...tournamentCards(tournaments),
  ];
  List<Widget> tournamentCards(List<dynamic> list) => [
    if (list.isEmpty && !loading && error == null) empty('Әзірге турнир жоқ.'),
    ...list.map(
      (t) => card(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            backgroundColor: yellow,
            child: Icon(Icons.emoji_events, color: navy),
          ),
          title: Text(
            t['title'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${localDate(t['start_at'])}\n${t['location']} • ${(t['teams'] as List).length} команда',
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => open(TournamentPage(api: api, initial: t, user: user)),
        ),
      ),
    ),
  ];
  List<Widget> teamList() => [
    heading('Командалар'),
    if (admin)
      FilledButton.icon(
        onPressed: () => open(TeamEditor(api: api, user: user!)),
        icon: const Icon(Icons.add),
        label: const Text('Команда құру'),
      ),
    const SizedBox(height: 12),
    if (teams.isEmpty && !loading && error == null)
      empty('Командалар әлі қосылмады.'),
    ...teams.map(
      (t) => card(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: teamIcon(t),
          title: Text(t['name']),
          subtitle: Text(
            '${t['city']} • ${(t['members'] as List).length} ойыншы${t['active'] == 0 ? ' • Белсенді емес' : ''}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => open(TeamPage(api: api, initial: t, user: user)),
        ),
      ),
    ),
  ];
  Future<void> logout() async {
    try {
      await api.call('POST', '/logout');
      api.token = null;
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> redeem() async {
    String code = '';
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Әкімші шақыру коды'),
        content: TextField(
          onChanged: (v) => code = v,
          decoration: const InputDecoration(labelText: 'Қолжетімділік коды'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Бас тарту'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, code),
            child: const Text('Кодты қолдану'),
          ),
        ],
      ),
    );
    if (value != null) await action('POST', '/admin/redeem', {'code': value});
  }

  List<Widget> profile() => [
    heading(user == null ? 'Қош келдіңіз!' : 'Жеке кабинет'),
    if (user == null) ...[
      empty(
        'Қонақ та пайдаланушы ретінде матчтарды, командаларды және турнирлерді қарай алады. Шақыру алу үшін тіркеліңіз.',
      ),
      FilledButton(onPressed: () => auth(false), child: const Text('Кіру')),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: () => auth(true), child: const Text('Тіркелу')),
    ] else ...[
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user!['name'],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(roles[user!['role']] ?? ''),
            Text(user!['email']),
            Text(user!['phone'] ?? ''),
            const SizedBox(height: 10),
            SelectableText(
              'ID: ${user!['id']}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            TextButton(
              onPressed: () => open(ProfileEditor(api: api, user: user!)),
              child: const Text('Профильді өңдеу'),
            ),
          ],
        ),
      ),
      if (ownTeam != null)
        FilledButton.icon(
          onPressed: () => open(
            TeamPage(
              api: api,
              initial: {...ownTeam!, 'members': []},
              user: user,
            ),
          ),
          icon: const Icon(Icons.groups),
          label: const Text('Менің командам'),
        ),
      if (admin)
        FilledButton.icon(
          onPressed: () => open(AdminPage(api: api)),
          icon: const Icon(Icons.admin_panel_settings),
          label: const Text('Әкімші панелі'),
        ),
      if (!admin)
        TextButton(
          onPressed: redeem,
          child: const Text('Әкімші шақыру кодын енгізу'),
        ),
      heading('Командаға шақырулар'),
      if (invitations.isEmpty) empty('Жаңа шақыру жоқ.'),
      ...invitations.map(
        (i) => card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i['team_name'],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(invitationStatus(i['status'])),
              if (i['status'] == 'pending')
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: loading
                          ? null
                          : () => action('PATCH', '/invitations/${i['id']}', {
                              'status': 'accepted',
                            }),
                      child: const Text('Қабылдау'),
                    ),
                    OutlinedButton(
                      onPressed: loading
                          ? null
                          : () => action('PATCH', '/invitations/${i['id']}', {
                              'status': 'rejected',
                            }),
                      child: const Text('Бас тарту'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      heading('Хабарламалар'),
      ...notifications.map(
        (n) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            n['read_at'] == null
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_read_outlined,
            color: blue,
          ),
          title: Text(n['message']),
          subtitle: Text(localDate(n['created_at'])),
          onTap: n['read_at'] == null
              ? () => action('POST', '/notifications/${n['id']}/read')
              : null,
        ),
      ),
      heading('Мен қатысатын командалар'),
      ...teams
          .where(
            (t) => (t['members'] as List).any((m) => m['id'] == user!['id']),
          )
          .map(
            (t) => ListTile(
              title: Text(t['name']),
              onTap: () => open(TeamPage(api: api, initial: t, user: user)),
            ),
          ),
      const SizedBox(height: 20),
      OutlinedButton(onPressed: logout, child: const Text('Шығу')),
    ],
  ];
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.api, required this.register});
  final Api api;
  final bool register;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  String role = 'user';
  String? error;
  bool busy = false;
  bool passwordVisible = false;
  @override
  void dispose() {
    for (final c in [name, email, phone, password, code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.call(
        'POST',
        widget.register ? '/register' : '/login',
        {
          'name': name.text,
          'email': email.text,
          'phone': phone.text,
          'password': password.text,
          'role': role,
          if (role == 'user' && code.text.trim().isNotEmpty)
            'admin_code': code.text.trim(),
        },
      );
      widget.api.token = r['token'];
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.register ? 'Тіркелу' : 'Кіру')),
    body: Form(
      key: form,
      child: pageBody([
        heading(
          widget.register ? 'Қауымдастыққа қосылыңыз' : 'Қайта қош келдіңіз!',
        ),
        if (widget.register) ...[
          Wrap(
            spacing: 8,
            children: ['user', 'coach']
                .map(
                  (r) => ChoiceChip(
                    label: Text(roles[r]!),
                    selected: role == r,
                    onSelected: busy ? null : (_) => setState(() => role = r),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          field('Аты-жөні', name),
          field('Телефон (міндетті емес)', phone, required: false),
        ],
        field('Электрондық пошта', email),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            controller: password,
            obscureText: !passwordVisible,
            decoration: InputDecoration(
              labelText: 'Құпиясөз (кемінде 8 таңба)',
              suffixIcon: IconButton(
                tooltip: passwordVisible ? 'Құпиясөзді жасыру' : 'Құпиясөзді көрсету',
                onPressed: () => setState(() => passwordVisible = !passwordVisible),
                icon: Icon(passwordVisible ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Бұл өрісті толтырыңыз'
                : null,
          ),
        ),
        if (widget.register && role == 'coach')
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('Тіркелгеннен кейін өз командаңызды жасау қажет.'),
          ),
        if (widget.register && role == 'user')
          ExpansionTile(
            title: const Text('Әкімші шақыру коды бар ма?'),
            children: [field('Қолжетімділік коды', code, required: false)],
          ),
        errorBox(error),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(
            busy
                ? 'Күтіңіз…'
                : widget.register
                ? 'Аккаунт құру'
                : 'Кіру',
          ),
        ),
      ], width: 600),
    ),
  );

}
