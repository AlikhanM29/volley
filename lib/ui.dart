import 'package:flutter/material.dart';

const blue = Color(0xFF1354C7),
    navy = Color(0xFF102B57),
    yellow = Color(0xFFFFD447),
    muted = Color(0xFF64748B);
const roles = {
  'user': 'Пайдаланушы',
  'coach': 'Жаттықтырушы',
  'admin': 'Әкімші',
};
typedef Json = Map<String, dynamic>;
Widget card(Widget child) => Container(
  margin: const EdgeInsets.only(bottom: 14),
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFFE0E8F5)),
  ),
  child: child,
);
Widget heading(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 16),
  child: Text(
    text,
    style: const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      color: navy,
    ),
  ),
);
Widget empty(String text) => card(
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: muted, fontSize: 16),
      ),
    ),
  ),
);
Widget errorBox(String? text) => text == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: const TextStyle(color: Colors.red)),
      );
Widget pageBody(List<Widget> children, {double width = 900}) => Align(
  alignment: Alignment.topCenter,
  child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: width),
    child: ListView(padding: const EdgeInsets.all(20), children: children),
  ),
);
String localDate(dynamic value) {
  final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return d == null ? '' : d.toString().substring(0, 16);
}

String isoDate(String value) {
  final d = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (d == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(value) ||
      d.toString().substring(0, 16) != value) {
    throw Exception('Күн мен уақыт қате. Мысалы: 2026-12-01 18:30');
  }
  return d.toUtc().toIso8601String();
}

Future<bool> confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Растау'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бас тарту'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Растау'),
          ),
        ],
      ),
    ) ??
    false;
Widget field(
  String label,
  TextEditingController controller, {
  bool required = true,
  int lines = 1,
  bool enabled = true,
  bool secret = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: TextFormField(
    controller: controller,
    enabled: enabled,
    obscureText: secret,
    minLines: lines,
    maxLines: lines,
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: lines > 1,
    ),
    validator: (v) =>
        required && (v ?? '').trim().isEmpty ? 'Бұл өрісті толтырыңыз' : null,
  ),
);
Widget teamIcon(Json team) => CircleAvatar(
  backgroundColor: yellow,
  child: (team['logo'] ?? '').toString().isEmpty
      ? const Icon(Icons.sports_volleyball, color: navy)
      : ClipOval(
          child: Image.network(
            team['logo'],
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) =>
                const Icon(Icons.sports_volleyball, color: navy),
          ),
        ),
);
