import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'ui.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.api});
  final Api api;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<dynamic> users = [], codes = [], events = [], legacy = [];
  String? error;
  bool busy = false;
  int tab = 0;
  final hours = TextEditingController(text: '24'),
      uses = TextEditingController(text: '1');
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    hours.dispose();
    uses.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final r = await Future.wait(
        [
          '/admin/users',
          '/admin/codes',
          '/admin/audit',
          '/admin/legacy',
        ].map((p) => widget.api.call('GET', p)),
      );
      if (mounted) {
        setState(() {
          users = r[0]['users'];
          codes = r[1]['codes'];
          events = r[2]['events'];
          legacy = r[3]['tournaments'];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> issue() async {
    setState(() {
      error = null;
      busy = true;
    });
    try {
      final r = await widget.api.call('POST', '/admin/codes', {
        'max_uses': int.tryParse(uses.text) ?? 0,
        'hours': int.tryParse(hours.text) ?? 0,
      });
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Қолжетімділік коды'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Код тек бір рет көрсетіледі. Қауіпсіз арнамен жіберіңіз.',
              ),
              const SizedBox(height: 12),
              SelectableText(r['code']),
              Text(
                'Мерзімі: ${localDate(DateTime.fromMillisecondsSinceEpoch(r['expires']).toIso8601String())}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: r['code'])),
              child: const Text('Көшіру'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Жабу'),
            ),
          ],
        ),
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Әкімші панелі')),
    body: pageBody([
      Wrap(
        spacing: 8,
        children:
            [
                  'Пайдаланушылар',
                  'Қолжетімділік кодтары',
                  'Әрекеттер журналы',
                  'Бұрынғы турнирлер',
                ].indexed
                .map(
                  (e) => ChoiceChip(
                    label: Text(e.$2),
                    selected: tab == e.$1,
                    onSelected: (_) => setState(() => tab = e.$1),
                  ),
                )
                .toList(),
      ),
      if (busy) const LinearProgressIndicator(),
      errorBox(error),
      if (tab == 0)
        ...users.map(
          (u) => card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u['name'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('${u['email']} • ${roles[u['role']]}'),
                Text(u['active'] == 1 ? 'Белсенді' : 'Бұғатталған'),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileEditor(
                                api: widget.api,
                                user: u,
                                admin: true,
                              ),
                            ),
                          );
                          if (mounted) await load();
                        },
                  child: const Text('Пайдаланушыны басқару'),
                ),
              ],
            ),
          ),
        ),
      if (tab == 1) ...[
        heading('Жаңа әкімші коды'),
        field('Жарамдылық мерзімі (1–168 сағат)', hours),
        field('Қолдану саны (1–20)', uses),
        FilledButton(
          onPressed: busy ? null : issue,
          child: const Text('Код жасау'),
        ),
        const SizedBox(height: 20),
        ...codes.map(
          (c) => card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('ID: ${c['id']}'),
                Text('${c['uses']}/${c['max_uses']} қолданылды'),
                Text(
                  'Мерзімі: ${localDate(DateTime.fromMillisecondsSinceEpoch(c['expires']).toIso8601String())}',
                ),
                Text(
                  c['revoked'] == 1
                      ? 'Күші жойылған'
                      : c['expires'] < DateTime.now().millisecondsSinceEpoch
                      ? 'Мерзімі өткен'
                      : 'Белсенді',
                ),
                if (c['revoked'] == 0)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (!await confirm(
                              context,
                              'Кодтың күшін жою керек пе?',
                            )) {
                              return;
                            }
                            try {
                              await widget.api.call(
                                'DELETE',
                                '/admin/codes/${c['id']}',
                              );
                              await load();
                            } catch (e) {
                              if (mounted) setState(() => error = '$e');
                            }
                          },
                    child: const Text('Күшін жою'),
                  ),
              ],
            ),
          ),
        ),
      ],
      if (tab == 2)
        ...events.map(
          (e) => card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auditLabel(e['action']),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(localDate(e['created_at'])),
                SelectableText(
                  'Орындаушы: ${e['actor_id'] ?? 'Сервер'}\nНысан: ${e['target_id'] ?? '–'}',
                ),
                Text(e['details']),
              ],
            ),
          ),
        ),
      if (tab == 3) ...[
        const Text(
          'Алдыңғы нұсқадан сақталған архив. Жаңа турнирге тек тіркелген командалар қосылады.',
        ),
        ...legacy.map(
          (t) => card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['title'] ?? ''),
                Text('${t['date'] ?? ''} • ${t['location'] ?? ''}'),
                Text((t['teams'] as List? ?? []).join(', ')),
              ],
            ),
          ),
        ),
      ],
    ]),
  );
}

String auditLabel(String action) =>
    {
      'admin_code.create': 'Әкімші коды жасалды',
      'admin_code.bootstrap': 'Алғашқы әкімші коды жасалды',
      'admin_code.revoke': 'Әкімші кодының күші жойылды',
      'admin.grant': 'Әкімші құқығы берілді',
      'schema.migrate': 'Дерекқор жаңартылды',
      'user.update': 'Пайдаланушы өзгертілді',
      'team.create': 'Команда құрылды',
      'team.update': 'Команда өзгертілді',
      'team.delete': 'Команда жойылды',
      'match.create': 'Матч құрылды',
      'match.update': 'Матч өзгертілді',
      'match.result': 'Матч нәтижесі сақталды',
      'match.delete': 'Матч жойылды',
      'tournament.create': 'Турнир құрылды',
      'tournament.update': 'Турнир өзгертілді',
      'tournament.delete': 'Турнир жойылды',
      'tournament.generate': 'Турнир матчтары жасалды',
    }[action] ??
    action;

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.api,
    required this.user,
    this.admin = false,
  });
  final Api api;
  final Json user;
  final bool admin;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final name = TextEditingController(text: widget.user['name']),
      phone = TextEditingController(text: widget.user['phone'] ?? '');
  late bool active = widget.user['active'] == 1;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.api.call(
        'PATCH',
        widget.admin ? '/admin/users/${widget.user['id']}' : '/me',
        {
          'name': name.text,
          'phone': phone.text,
          if (widget.admin) 'active': active ? 1 : 0,
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
    appBar: AppBar(title: const Text('Профильді өңдеу')),
    body: pageBody([
      field('Аты-жөні', name),
      field('Телефон', phone, required: false),
      if (widget.admin)
        SwitchListTile(
          title: const Text('Белсенді аккаунт'),
          value: active,
          onChanged: (v) => setState(() => active = v),
        ),
      errorBox(error),
      FilledButton(onPressed: busy ? null : save, child: const Text('Сақтау')),
    ], width: 600),
  );
}
