import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const maxBytes = 500 * 1024 * 1024; // 500 MB
void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'OmniSend',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF0B6E4F), useMaterial3: true),
        home: const Home(),
      );
}

enum Ch { sms, whatsapp, messenger, telegram }

const chLabel = {Ch.sms: 'SMS (GSM)', Ch.whatsapp: 'WhatsApp', Ch.messenger: 'Messenger', Ch.telegram: 'Telegram'};
const chIcon = {Ch.sms: Icons.sms, Ch.whatsapp: Icons.chat, Ch.messenger: Icons.forum, Ch.telegram: Icons.send};

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final text = TextEditingController(), to = TextEditingController();
  final files = <PlatformFile>[];
  final sel = <Ch>{Ch.sms};
  List<Map<String, dynamic>> history = [];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final raw = p.getString('history');
      if (raw != null) setState(() => history = List<Map<String, dynamic>>.from(jsonDecode(raw)));
    });
  }

  void toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> pick(FileType t) async {
    final r = await FilePicker.platform.pickFiles(type: t, allowMultiple: true);
    if (r == null) return;
    for (final f in r.files) {
      if (f.size > maxBytes) {
        toast('${f.name} exceeds 500 MB limit');
      } else {
        setState(() => files.add(f));
      }
    }
  }

  String mb(int b) => (b / 1048576).toStringAsFixed(1);

  Future<bool> open(String url) async {
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> send() async {
    final msg = text.text.trim();
    final num = to.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (msg.isEmpty && files.isEmpty) return toast('Write a message or attach a file');
    if (sel.isEmpty) return toast('Select at least one channel');
    for (final ch in sel) {
      if (files.isNotEmpty) {
        // Attachments go through the Android share sheet; pick the target app for each channel.
        toast('${chLabel[ch]}: choose ${chLabel[ch]} in the share sheet');
        await Share.shareXFiles(files.map((f) => XFile(f.path!)).toList(), text: msg.isEmpty ? null : msg);
        continue;
      }
      final q = Uri.encodeComponent(msg);
      bool ok = false;
      switch (ch) {
        case Ch.sms:
          ok = await open('sms:$num?body=$q');
        case Ch.whatsapp:
          ok = await open(num.isEmpty ? 'https://wa.me/?text=$q' : 'https://wa.me/${num.replaceAll('+', '')}?text=$q');
        case Ch.telegram:
          ok = await open('https://t.me/share/url?url=%20&text=$q');
        case Ch.messenger:
          await Clipboard.setData(ClipboardData(text: msg));
          toast('Text copied - paste it in Messenger');
          ok = await open('fb-messenger://') || await open('https://m.me/');
      }
      if (!ok) toast('Could not open ${chLabel[ch]}');
    }
    history.insert(0, {
      't': DateTime.now().toIso8601String(),
      'to': to.text,
      'msg': msg,
      'files': files.map((f) => f.name).toList(),
      'ch': sel.map((c) => chLabel[c]).toList(),
    });
    final p = await SharedPreferences.getInstance();
    await p.setString('history', jsonEncode(history.take(200).toList()));
    setState(() {
      text.clear();
      files.clear();
    });
  }

  @override
  Widget build(BuildContext c) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(title: const Text('OmniSend'), bottom: const TabBar(tabs: [Tab(text: 'Compose'), Tab(text: 'History')])),
          body: TabBarView(children: [compose(), hist()]),
        ),
      );

  Widget compose() => ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: to, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Recipient number (+923...)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: text, minLines: 4, maxLines: 8, decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          ActionChip(avatar: const Icon(Icons.photo), label: const Text('Photo'), onPressed: () => pick(FileType.image)),
          ActionChip(avatar: const Icon(Icons.videocam), label: const Text('Video'), onPressed: () => pick(FileType.video)),
          ActionChip(avatar: const Icon(Icons.attach_file), label: const Text('Document'), onPressed: () => pick(FileType.any)),
        ]),
        for (final f in files)
          ListTile(
            dense: true,
            leading: const Icon(Icons.insert_drive_file),
            title: Text(f.name, overflow: TextOverflow.ellipsis),
            subtitle: Text('${mb(f.size)} MB / 500 MB'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => files.remove(f))),
          ),
        const Divider(),
        const Text('Send via', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(spacing: 8, children: [
          for (final ch in Ch.values)
            FilterChip(
              avatar: Icon(chIcon[ch], size: 18),
              label: Text(chLabel[ch]!),
              selected: sel.contains(ch),
              onSelected: (v) => setState(() => v ? sel.add(ch) : sel.remove(ch)),
            ),
        ]),
        if (files.isNotEmpty && sel.contains(Ch.sms))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Note: GSM SMS carries text only. Files need a data app (WhatsApp/Telegram/Messenger).', style: TextStyle(color: Colors.orange)),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: send, icon: const Icon(Icons.send), label: const Text('Send')),
      ]);

  Widget hist() => history.isEmpty
      ? const Center(child: Text('No messages yet'))
      : ListView(children: [
          for (final h in history)
            ListTile(
              title: Text(h['msg'].toString().isEmpty ? '(attachment)' : h['msg'], maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${(h['ch'] as List).join(', ')}  |  ${h['to']}  |  ${(h['files'] as List).length} file(s)\n${h['t'].toString().substring(0, 16)}'),
              isThreeLine: true,
            ),
        ]);
}
