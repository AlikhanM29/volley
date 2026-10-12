import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class TeamEditor extends StatefulWidget {
  const TeamEditor({
    super.key,
    required this.api,
    required this.user,
    this.team,
  });
  final Api api;
  final Json user;
  final Json? team;
  @override
  State<TeamEditor> createState() => _TeamEditorState();
}

class _TeamEditorState extends State<TeamEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.team?['name'] ?? ''),
      city = TextEditingController(text: widget.team?['city'] ?? ''),
      description = TextEditingController(
        text: widget.team?['description'] ?? '',
      ),
      logo = TextEditingController(text: widget.team?['logo'] ?? '');
  late String? coach = widget.team?['coach_id'];
  late bool active = widget.team?['active'] != 0;
  List<dynamic> coaches = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.user['role'] == 'admin') loadCoaches();
  }

  Future<void> loadCoaches() async {
    try {
      final r = await widget.api.call('GET', '/admin/users');
      if (mounted) {
        setState(
          () => coaches = (r['users'] as List)
              .where((u) => u['role'] == 'coach' && u['active'] == 1)
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    for (final c in [name, city, description, logo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.call(
        widget.team == null ? 'POST' : 'PATCH',
        '/teams${widget.team == null ? '' : '/${widget.team!['id']}'}',
        {
          'name': name.text,
          'city': city.text,
          'description': description.text,
          'logo': logo.text,
          if (widget.user['role'] == 'admin') 'coach_id': coach,
          if (widget.user['role'] == 'admin') 'active': active ? 1 : 0,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.team == null ? 'Команда құру' : 'Команданы өңдеу'),
    ),
    body: Form(
      key: form,
      child: pageBody([
        heading('Команда туралы'),
        field('Команда атауы', name),
        field('Қала', city),
        field('Сипаттама', description, lines: 3),
        field(
          'Логотип сілтемесі (HTTPS, міндетті емес)',
          logo,
          required: false,
        ),
        if (widget.user['role'] == 'admin') ...[
          DropdownButtonFormField<String>(
            initialValue: coaches.any((c) => c['id'] == coach) ? coach : null,
            decoration: const InputDecoration(labelText: 'Жаттықтырушы'),
            items: coaches
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c['id'],
                    child: Text(
                      '${c['name']} (${c['email']})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => coach = v),
            isExpanded: true,
          ),
          SwitchListTile(
            title: const Text('Белсенді команда'),
            value: active,
            onChanged: (v) => setState(() => active = v),
          ),
        ],
        errorBox(error),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Сақталуда…' : 'Сақтау'),
        ),
      ], width: 650),
    ),
  );
}

class TeamPage extends StatefulWidget {
  const TeamPage({
    super.key,
    required this.api,
    required this.initial,
    required this.user,
  });
  final Api api;
  final Json initial;
  final Json? user;
  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  late Json team = widget.initial;
  List<dynamic> invites = [], results = [];
  final search = TextEditingController();
  String? error;
  bool busy = false;
  bool get manage =>
      widget.user != null &&
      (widget.user!['role'] == 'admin' ||
          widget.user!['role'] == 'coach' &&
              widget.user!['id'] == team['coach_id']);
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.call('GET', '/teams/${team['id']}');
      final i = manage
          ? await widget.api.call('GET', '/teams/${team['id']}/invitations')
          : {'invitations': []};
      if (mounted) {
        setState(() {
          team = r['team'];
          invites = i['invitations'];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> action(String method, String path, [Json? body]) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.call(method, path, body);
      if (!(method == 'DELETE' && path == '/teams/${team['id']}')) {
        await load();
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> find() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.call(
        'GET',
        '/users/search?q=${Uri.encodeQueryComponent(search.text.trim())}',
      );
      if (mounted) setState(() => results = r['users']);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TeamEditor(api: widget.api, user: widget.user!, team: team),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(team['name']),
      actions: [
        if (manage)
          IconButton(
            onPressed: busy ? null : edit,
            icon: const Icon(Icons.edit),
            tooltip: 'Өңдеу',
          ),
      ],
    ),
    body: pageBody([
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            teamIcon(team),
            heading(team['name']),
            Text(team['city']),
            Text(team['description']),
            Text(
              team['active'] == 1 ? 'Белсенді' : 'Белсенді емес',
              style: const TextStyle(color: muted),
            ),
          ],
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      errorBox(error),
      heading('Команда құрамы'),
      if ((team['members'] as List? ?? []).isEmpty)
        empty('Қабылданған ойыншылар әлі жоқ.'),
      ...(team['members'] as List? ?? []).map(
        (m) => card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${m['name']}${m['captain'] == 1 ? ' • Капитан' : ''}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (manage)
                Wrap(
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              'PATCH',
                              '/teams/${team['id']}/members/${m['id']}',
                              {'captain': m['captain'] == 1 ? 0 : 1},
                            ),
                      child: Text(
                        m['captain'] == 1 ? 'Капитаннан алу' : 'Капитан ету',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (await confirm(
                                context,
                                'Ойыншыны командадан шығару керек пе?',
                              )) {
                                await action(
                                  'DELETE',
                                  '/teams/${team['id']}/members/${m['id']}',
                                );
                              }
                            },
                      child: const Text('Құрамнан шығару'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      if (manage) ...[
        heading('Ойыншы шақыру'),
        const Text(
          'Тек тіркелген пайдаланушылар. Құрамға қабылданған шақырудан кейін ғана қосылады.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: search,
          decoration: const InputDecoration(
            labelText: 'Аты, email, телефон немесе профиль ID',
          ),
          onSubmitted: (_) => find(),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: busy ? null : find,
          icon: const Icon(Icons.search),
          label: const Text('Іздеу'),
        ),
        ...results.map((u) {
          final invited = invites.any((i) => i['user_id'] == u['id']);
          return card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u['name']),
                Text(u['email'], style: const TextStyle(color: muted)),
                TextButton(
                  onPressed: busy || invited
                      ? null
                      : () => action(
                          'POST',
                          '/teams/${team['id']}/invitations',
                          {'user_id': u['id']},
                        ),
                  child: Text(invited ? 'Шақыру жіберілген' : 'Шақыру'),
                ),
              ],
            ),
          );
        }),
        heading('Жіберілген шақырулар'),
        ...invites.map(
          (i) => ListTile(
            title: Text(i['name']),
            subtitle: Text(invitationStatus(i['status'])),
          ),
        ),
      ],
      if (widget.user?['role'] == 'admin')
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  if (await confirm(
                    context,
                    'Команданы жою керек пе? Тарихи нәтижелер сақталады.',
                  )) {
                    await action('DELETE', '/teams/${team['id']}');
                    if (context.mounted && error == null) {
                      Navigator.pop(context);
                    }
                  }
                },
          child: const Text('Команданы жою'),
        ),
    ]),
  );
}

String invitationStatus(dynamic s) =>
    {
      'pending': 'Жауап күтілуде',
      'accepted': 'Қабылданды',
      'rejected': 'Қабылданбады',
      'cancelled': 'Күші жойылды',
    }[s] ??
    '$s';
