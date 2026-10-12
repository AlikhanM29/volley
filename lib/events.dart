import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class EventEditor extends StatefulWidget {
  const EventEditor({
    super.key,
    required this.api,
    required this.tournament,
    this.initial,
  });
  final Api api;
  final bool tournament;
  final Json? initial;
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.initial?['title'] ?? ''),
      location = TextEditingController(text: widget.initial?['location'] ?? ''),
      date = TextEditingController(
        text: localDate(widget.initial?['start_at']),
      ),
      interval = TextEditingController(
        text: '${widget.initial?['round_minutes'] ?? 1440}',
      );
  late String kind = widget.initial?['kind'] ?? 'playoff',
      format = widget.initial?['format'] ?? 'indoor';
  late int best = widget.initial?['best_of'] ?? 5;
  late String? a = widget.initial?['team_a'], b = widget.initial?['team_b'];
  late Set<String> selected = (widget.initial?['teams'] as List? ?? [])
      .map((t) => t['id'] as String)
      .toSet();
  List<dynamic> teams = [];
  bool busy = false, loading = true;
  String? error;
  bool get locked => widget.initial?['generated'] == 1;
  bool get bracketMatch => widget.initial?['tournament_id'] != null;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [name, location, date, interval]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.call('GET', '/teams');
      if (mounted) {
        setState(
          () => teams = (r['teams'] as List)
              .where(
                (t) =>
                    t['active'] == 1 ||
                    selected.contains(t['id']) ||
                    a == t['id'] ||
                    b == t['id'],
              )
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = <String, dynamic>{
        'location': location.text,
        'start_at': locked ? widget.initial!['start_at'] : isoDate(date.text),
        'format': format,
        'best_of': best,
      };
      if (widget.tournament) {
        body.addAll({
          'title': name.text,
          'kind': kind,
          'team_ids': selected.toList(),
          'round_minutes': int.tryParse(interval.text) ?? 0,
        });
      } else {
        if (!bracketMatch || a != null) body['team_a'] = a;
        if (!bracketMatch || b != null) body['team_b'] = b;
      }
      await widget.api.call(
        widget.initial == null ? 'POST' : 'PATCH',
        '/${widget.tournament ? 'tournaments' : 'matches'}${widget.initial == null ? '' : '/${widget.initial!['id']}'}',
        body,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickDateTime() async {
    final initial =
        DateTime.tryParse(date.text.replaceFirst(' ', 'T')) ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Матч күнін таңдаңыз',
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Матч уақытын таңдаңыз',
    );
    if (pickedTime == null || !mounted) return;
    final value = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() {
      date.text =
          '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.tournament ? 'Турнирді баптау' : 'Матчты баптау'),
    ),
    body: Form(
      key: form,
      child: pageBody([
        if (loading) const LinearProgressIndicator(),
        if (widget.tournament) field('Турнир атауы', name),
        field('Өтетін орын', location),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            controller: date,
            readOnly: true,
            enabled: !locked,
            onTap: locked ? null : pickDateTime,
            decoration: InputDecoration(
              labelText: 'Күн мен уақыт',
              hintText: 'Күнтізбеден таңдаңыз',
              suffixIcon: IconButton(
                tooltip: 'Күнтізбені ашу',
                onPressed: locked ? null : pickDateTime,
                icon: const Icon(Icons.calendar_month),
              ),
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Күн мен уақытты таңдаңыз'
                : null,
          ),
        ),
        if (widget.tournament) ...[
          DropdownButtonFormField<String>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: 'Турнир форматы'),
            items: const [
              DropdownMenuItem(value: 'playoff', child: Text('Плей-офф')),
              DropdownMenuItem(
                value: 'round_robin',
                child: Text('Айналмалы турнир'),
              ),
            ],
            onChanged: locked ? null : (v) => setState(() => kind = v!),
          ),
          const SizedBox(height: 16),
          field('Кезеңдер аралығы (минут)', interval, enabled: !locked),
        ],
        DropdownButtonFormField<String>(
          initialValue: format,
          decoration: const InputDecoration(labelText: 'Волейбол форматы'),
          items: const [
            DropdownMenuItem(value: 'indoor', child: Text('Классикалық 6×6')),
            DropdownMenuItem(value: 'beach', child: Text('Жағажай 2×2')),
          ],
          onChanged: locked || bracketMatch
              ? null
              : (v) => setState(() => format = v!),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: best,
          decoration: const InputDecoration(labelText: 'Ең көп сет саны'),
          items: [1, 3, 5]
              .map((v) => DropdownMenuItem(value: v, child: Text('$v сет')))
              .toList(),
          onChanged: locked || bracketMatch
              ? null
              : (v) => setState(() => best = v!),
        ),
        const SizedBox(height: 16),
        if (widget.tournament) ...[
          heading('Қатысатын командалар'),
          if (teams.isEmpty && !loading)
            empty('Алдымен белсенді командалар тіркелуі керек.'),
          ...teams.map(
            (t) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t['name']),
              subtitle: Text(t['city']),
              value: selected.contains(t['id']),
              onChanged: locked
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        selected.add(t['id']);
                      } else {
                        selected.remove(t['id']);
                      }
                    }),
            ),
          ),
        ] else if (bracketMatch)
          const Text(
            'Турнир матчы: командалар мен формат кесте арқылы анықталады.',
          )
        else ...[
          teamSelect('Бірінші команда', a, (v) => setState(() => a = v)),
          const SizedBox(height: 16),
          teamSelect('Екінші команда', b, (v) => setState(() => b = v)),
        ],
        errorBox(error),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || loading ? null : save,
          child: Text(busy ? 'Сақталуда…' : 'Сақтау'),
        ),
      ], width: 700),
    ),
  );
  Widget teamSelect(
    String label,
    String? value,
    ValueChanged<String?> change,
  ) => DropdownButtonFormField<String>(
    initialValue: teams.any((t) => t['id'] == value && t['active'] == 1)
        ? value
        : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: teams
        .where((t) => t['active'] == 1)
        .map(
          (t) => DropdownMenuItem<String>(
            value: t['id'],
            child: Text(
              '${t['name']} • ${t['city']}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: change,
    validator: (v) => v == null ? 'Команда таңдаңыз' : null,
  );
}

class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, this.onTap});
  final Json match;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => card(
    InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${localDate(match['start_at'])} • ${match['location']}',
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            '${match['a_name'] ?? 'Жеңімпаз күтілуде'}  ${match['score_a'] ?? '–'}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Text(
            '${match['b_name'] ?? (match['bye'] == 1 ? 'Қарсылассыз өту' : 'Жеңімпаз күтілуде')}  ${match['score_b'] ?? '–'}',
            style: const TextStyle(fontSize: 17),
          ),
          if (match['deleted'] == 1)
            const Text('Матч жойылған', style: TextStyle(color: Colors.red))
          else if (match['winner_name'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '✓ ${match['winner_name']}',
                style: const TextStyle(
                  color: blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> manageMatch(
  BuildContext context,
  Api api,
  Json match,
  VoidCallback refresh,
) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MatchPage(api: api, match: match),
    ),
  );
  refresh();
}

class MatchPage extends StatefulWidget {
  const MatchPage({super.key, required this.api, required this.match});
  final Api api;
  final Json match;
  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  late Json match = widget.match;
  late int a = (match['best_of'] + 1) ~/ 2, b = 0;
  String? error;
  bool busy = false;
  Future<void> score() async {
    if (!await confirm(context, 'Матч нәтижесін сақтау керек пе?')) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.call(
        'POST',
        '/matches/${match['id']}/result',
        {'score_a': a, 'score_b': b},
      );
      if (mounted) setState(() => match = r['match']);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Матчты басқару')),
    body: pageBody([
      MatchCard(match: match),
      errorBox(error),
      if (match['deleted'] != 1 &&
          match['bye'] != 1 &&
          match['team_a'] != null &&
          match['team_b'] != null) ...[
        heading('Сеттер нәтижесі'),
        Text('Жеңіс үшін ${(match['best_of'] + 1) ~/ 2} сет қажет.'),
        const SizedBox(height: 16),
        scoreSelect(match['a_name'], a, (v) => setState(() => a = v!)),
        const SizedBox(height: 16),
        scoreSelect(match['b_name'], b, (v) => setState(() => b = v!)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : score,
          child: const Text('Нәтижені сақтау'),
        ),
      ],
      if (match['deleted'] != 1) ...[
        OutlinedButton(
          onPressed: busy
              ? null
              : () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EventEditor(
                        api: widget.api,
                        tournament: false,
                        initial: match,
                      ),
                    ),
                  );
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Матчты өңдеу'),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  if (!await confirm(
                    context,
                    'Матчты жою керек пе? Кестедегі келесі кезең қатысушысы алынып тасталады.',
                  )) {
                    return;
                  }
                  try {
                    await widget.api.call('DELETE', '/matches/${match['id']}');
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) setState(() => error = '$e');
                  }
                },
          child: const Text('Матчты жою'),
        ),
      ],
    ], width: 650),
  );
  Widget scoreSelect(String label, int value, ValueChanged<int?> change) =>
      DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: List.generate(
          (match['best_of'] + 1) ~/ 2 + 1,
          (i) => DropdownMenuItem(value: i, child: Text('$i')),
        ),
        onChanged: change,
      );
}

class TournamentPage extends StatefulWidget {
  const TournamentPage({
    super.key,
    required this.api,
    required this.initial,
    required this.user,
  });
  final Api api;
  final Json initial;
  final Json? user;
  @override
  State<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends State<TournamentPage> {
  late Json event = widget.initial;
  bool busy = false;
  String? error;
  bool get admin => widget.user?['role'] == 'admin';
  Future<void> load() async {
    try {
      final r = await widget.api.call('GET', '/tournaments/${event['id']}');
      if (mounted) setState(() => event = r['tournament']);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> generate() async {
    if (!await confirm(
      context,
      'Командалар мен формат бекітіліп, матчтар автоматты түрде жасалады. Жалғастыру керек пе?',
    )) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.call(
        'POST',
        '/tournaments/${event['id']}/generate',
      );
      if (mounted) setState(() => event = r['tournament']);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = event['matches'] as List;
    final rounds = matches.map((m) => m['round'] as int).toSet().toList()
      ..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(event['title']),
        actions: [
          IconButton(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Жаңарту',
          ),
        ],
      ),
      body: pageBody([
        heading(event['title']),
        Text('${localDate(event['start_at'])} • ${event['location']}'),
        Text(event['kind'] == 'playoff' ? 'Плей-офф' : 'Айналмалы турнир'),
        Wrap(
          spacing: 8,
          children: (event['teams'] as List)
              .map((t) => Chip(label: Text(t['name'])))
              .toList(),
        ),
        errorBox(error),
        if (busy) const LinearProgressIndicator(),
        if (admin) ...[
          if (event['generated'] == 0)
            FilledButton.icon(
              onPressed: busy ? null : generate,
              icon: const Icon(Icons.account_tree),
              label: const Text('Матчтарды автоматты түрде жасау'),
            ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EventEditor(
                          api: widget.api,
                          tournament: true,
                          initial: event,
                        ),
                      ),
                    );
                    if (mounted) await load();
                  },
            child: const Text('Турнирді өңдеу'),
          ),
        ],
        if (matches.isEmpty) empty('Матчтар әлі жасалмады.'),
        if (event['kind'] == 'round_robin' && matches.isNotEmpty) ...[
          heading('Турнирлік кесте'),
          const Text(
            'Ұпай, жеңіс, сет айырмасы бойынша. Теңдік болса — ортақ көрсеткіштер, атау бойынша реттеу.',
            style: TextStyle(color: muted),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Команда')),
                DataColumn(label: Text('Ойын')),
                DataColumn(label: Text('Жеңіс')),
                DataColumn(label: Text('Ұпай')),
                DataColumn(label: Text('Сеттер')),
              ],
              rows: (event['standings'] as List)
                  .map(
                    (r) => DataRow(
                      cells: [
                        DataCell(Text(r['name'])),
                        DataCell(Text('${r['played']}')),
                        DataCell(Text('${r['wins']}')),
                        DataCell(Text('${r['points']}')),
                        DataCell(Text('${r['sets_for']}:${r['sets_against']}')),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        if (matches.isNotEmpty) ...[
          heading('Матчтар мен турнир торы'),
          const Text(
            'Кезеңдер арасында көлденең жылжытыңыз.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rounds
                  .map(
                    (r) => SizedBox(
                      width: 290,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event['kind'] == 'playoff' && r == rounds.last
                                  ? 'ФИНАЛ'
                                  : '$r-КЕЗЕҢ',
                              style: const TextStyle(
                                color: blue,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...matches
                                .where((m) => m['round'] == r)
                                .map(
                                  (m) => MatchCard(
                                    match: m,
                                    onTap: admin
                                        ? () => manageMatch(
                                            context,
                                            widget.api,
                                            m,
                                            load,
                                          )
                                        : null,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        if (admin)
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    if (!await confirm(
                      context,
                      'Турнирді және оның матчтарын жою керек пе?',
                    )) {
                      return;
                    }
                    try {
                      await widget.api.call(
                        'DELETE',
                        '/tournaments/${event['id']}',
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    }
                  },
            child: const Text('Турнирді жою'),
          ),
      ]),
    );
  }
}
