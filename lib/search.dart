import 'package:flutter/material.dart';

import 'api.dart';
import 'teams.dart';
import 'ui.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.api, this.user});
  final Api api;
  final Json? user;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = TextEditingController();
  List<dynamic> teams = [];
  List<dynamic> players = [];
  bool loading = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final query = controller.text.trim();
    if (query.length < 2) {
      setState(() => error = 'Іздеу үшін кемінде 2 таңба енгізіңіз.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.call(
        'GET',
        '/search?q=${Uri.encodeQueryComponent(query)}',
      );
      if (mounted) {
        setState(() {
          teams = result['teams'] as List<dynamic>;
          players = result['players'] as List<dynamic>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Іздеу')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => search(),
          decoration: InputDecoration(
            labelText: 'Команда немесе ойыншы аты',
            hintText: 'Мысалы: Астана немесе Айбек',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Іздеу',
              onPressed: loading ? null : search,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (loading) const LinearProgressIndicator(),
        if (error != null) errorBox(error!),
        if (!loading && error == null && teams.isEmpty && players.isEmpty)
          empty('Команда немесе ойыншыны іздеу үшін атауын жазыңыз.'),
        if (teams.isNotEmpty) ...[
          heading('Командалар'),
          ...teams.map(
            (team) => card(
              ListTile(
                leading: teamIcon(team),
                title: Text(team['name']),
                subtitle: Text(
                  '${team['city']} • ${(team['members'] as List).length} ойыншы',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(
                  TeamPage(api: widget.api, initial: team, user: widget.user),
                ),
              ),
            ),
          ),
        ],
        if (players.isNotEmpty) ...[
          heading('Ойыншылар'),
          ...players.map(
            (player) => card(
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(player['name']),
                subtitle: Text(
                  (player['teams'] as List).isEmpty
                      ? 'Командаға қосылмаған'
                      : (player['teams'] as List)
                          .map((team) => team['name'])
                          .join(', '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(PlayerProfilePage(api: widget.api, id: player['id'])),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class PlayerProfilePage extends StatefulWidget {
  const PlayerProfilePage({super.key, required this.api, required this.id});
  final Api api;
  final String id;

  @override
  State<PlayerProfilePage> createState() => _PlayerProfilePageState();
}

class _PlayerProfilePageState extends State<PlayerProfilePage> {
  Json? player;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final response = await widget.api.call('GET', '/players/${widget.id}');
      if (mounted) setState(() => player = response['player']);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ойыншы профилі')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null) errorBox(error!),
        if (player == null && error == null)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else if (player != null) ...[
          card(
            Column(
              children: [
                const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 38)),
                const SizedBox(height: 12),
                Text(player!['name'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Ойыншы'),
              ],
            ),
          ),
          heading('Командалары'),
          if ((player!['teams'] as List).isEmpty) empty('Ойыншы әзірге командаға қосылмаған.'),
          ...(player!['teams'] as List).map(
            (team) => card(
              ListTile(
                leading: teamIcon(team),
                title: Text(team['name']),
                subtitle: Text(team['city']),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
