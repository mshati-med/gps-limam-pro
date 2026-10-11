import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GpsLimamApp());
}

class GpsLimamApp extends StatefulWidget {
  const GpsLimamApp({super.key});
  @override State<GpsLimamApp> createState() => _GpsLimamAppState();
}

class _GpsLimamAppState extends State<GpsLimamApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  @override void initState() { super.initState(); _loadTheme(); }
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _themeMode = (prefs.getBool('dark_mode')?? true)? ThemeMode.dark : ThemeMode.light; });
  }
  Future<void> _toggleTheme() async {
    final next = _themeMode == ThemeMode.dark? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', next == ThemeMode.dark);
    setState(() => _themeMode = next);
  }
  @override Widget build(BuildContext context) {
    const seed = Color(0xFF13B8D5);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GPS LIMAM',
      themeMode: _themeMode,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark), scaffoldBackgroundColor: const Color(0xFF081522), useMaterial3: true),
      home: HomePage(onToggleTheme: _toggleTheme, isDark: _themeMode == ThemeMode.dark),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onToggleTheme, required this.isDark});
  final VoidCallback onToggleTheme; final bool isDark;
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController _mapController = MapController();
  int _tab = 0;
  LatLng _center = const LatLng(18.0735, -15.9582);
  String _status = 'الخريطة جاهزة - فعل GPS';
  bool _locating = false;

  Future<void> _locateMe() async {
    setState(() { _locating = true; _status = 'جار تحديد الموقع...'; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) { setState(()=>_status='شغل GPS'); return; }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) { setState(()=>_status='يلزم السماح بالموقع'); return; }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _center = LatLng(pos.latitude, pos.longitude);
      _mapController.move(_center, 15);
      setState(()=>_status='تم تحديد موقعك');
    } catch (_) { setState(()=>_status='تعذر تحديد الموقع'); }
    finally { if(mounted) setState(()=>_locating=false); }
  }

  @override Widget build(BuildContext context) {
    final pages = <Widget>[
      Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: _center, initialZoom: 11), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.gpslimam.app'),
          MarkerLayer(markers: [Marker(point: _center, width: 40, height: 40, child: const Icon(Icons.my_location, color: Colors.blue, size: 36))]),
          const RichAttributionWidget(attributions: [TextSourceAttribution('© OSM')]),
        ]),
        Positioned(top: 14, right: 14, left: 14, child: Card(elevation: 4, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [
          const Icon(Icons.explore, color: Color(0xFF13B8D5), size: 30),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GPS LIMAM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)), Text('خرائطك • اصدقاؤك • طريقك', style: TextStyle(fontSize: 12))])),
          IconButton(onPressed: widget.onToggleTheme, icon: Icon(widget.isDark? Icons.light_mode : Icons.dark_mode)),
          IconButton(onPressed: (){ Share.share('موقعي: https://maps.google.com/?q=${_center.latitude},${_center.longitude}'); }, icon: const Icon(Icons.share)),
        ])))),
        Positioned(bottom: 22, right: 16, child: FloatingActionButton(heroTag: 'locate', onPressed: _locating? null : _locateMe, child: _locating? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location))),
        Positioned(bottom: 24, left: 16, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha:.94), borderRadius: BorderRadius.circular(14)), child: Text(_status, style: const TextStyle(fontSize: 12)))),
      ]),
      const FriendsPage(),
      const ChatPage(),
      const Center(child: Text('الخرائط المحفوظة قريبا - Offline')),
      const SettingsPage(),
    ];
    return Scaffold(body: SafeArea(child: pages[_tab]), bottomNavigationBar: NavigationBar(selectedIndex: _tab, onDestinationSelected: (i)=>setState(()=>_tab=i), destinations: const [
      NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'الخريطة'),
      NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'الاصدقاء'),
      NavigationDestination(icon: Icon(Icons.chat_outlined), selectedIcon: Icon(Icons.chat), label: 'الدردشة'),
      NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'خرائطي'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الاعدادات'),
    ]));
  }
}

class FriendsPage extends StatefulWidget { const FriendsPage({super.key}); @override State<FriendsPage> createState() => _FriendsPageState(); }
class _FriendsPageState extends State<FriendsPage> {
  String myCode = ''; String partner = ''; final _ctrl = TextEditingController();
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    String code = p.getString('my_code')?? '';
    if(code.isEmpty){ code = (100000 + DateTime.now().millisecondsSinceEpoch % 900000).toString(); await p.setString('my_code', code); }
    setState(() { myCode = code; partner = p.getString('partner_code')?? ''; });
  }
  Future<void> _link() async {
    if(_ctrl.text.length < 4) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('partner_code', _ctrl.text.trim());
    setState(()=> partner = _ctrl.text.trim());
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الربط! اذهب للدردشة')));
  }
  Future<void> _unlink() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('partner_code'); setState(()=> partner = '');
  }
  @override Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(20), child: ListView(children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Text('رمزك الخاص'), const SizedBox(height: 8),
        Text(myCode, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 5)),
        const SizedBox(height: 8),
        ElevatedButton.icon(onPressed: ()=> Share.share('رمز GPS LIMAM الخاص بي: $myCode'), icon: const Icon(Icons.share), label: const Text('شارك رمزك')),
      ]))),
      const SizedBox(height: 20),
      if(partner.isEmpty)...[
        TextField(controller: _ctrl, decoration: const InputDecoration(labelText: 'ادخل رمز شريكك', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton(onPressed: _link, child: const Text('ربط الان')),
      ] else...[
        Card(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15), child: ListTile(leading: const Icon(Icons.link, color: Colors.green), title: Text('مرتبط مع: $partner'), subtitle: const Text('يمكنكم الدردشة الان'), trailing: IconButton(icon: const Icon(Icons.link_off), onPressed: _unlink))),
      ],
    ]));
  }
}

class ChatPage extends StatefulWidget { const ChatPage({super.key}); @override State<ChatPage> createState() => _ChatPageState(); }
class _ChatPageState extends State<ChatPage> {
  final _msgCtrl = TextEditingController(); List<Map> _msgs = []; String partner = '';
  @override void initState() { super.initState(); _loadMsgs(); }
  Future<void> _loadMsgs() async {
    final p = await SharedPreferences.getInstance();
    partner = p.getString('partner_code')?? '';
    String raw = p.getString('chat_msgs')?? '[]';
    try { _msgs = List<Map>.from(jsonDecode(raw)); } catch(_){ _msgs=[]; }
    setState((){});
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('chat_msgs', jsonEncode(_msgs));
  }
  void _send(String text, {bool loc=false}) async {
    if(text.trim().isEmpty) return;
    _msgs.add({'text': text, 'me': true, 'time': DateTime.now().toString().substring(11,16), 'loc': loc});
    await _save(); setState((){}); _msgCtrl.clear();
  }
  Future<void> _sendLocation() async {
    try{
      var perm = await Geolocator.checkPermission();
      if(perm==LocationPermission.denied) perm = await Geolocator.requestPermission();
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _send('https://maps.google.com/?q=${pos.latitude},${pos.longitude}', loc: true);
    } catch(_){}
  }
  @override Widget build(BuildContext context) {
    if(partner.isEmpty){
      return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('اذهب لتبويب الاصدقاء واربط مع شريكك اولا', textAlign: TextAlign.center)));
    }
    return Column(children: [
      ListTile(title: Text('شريكي: $partner'), trailing: IconButton(icon: const Icon(Icons.my_location), onPressed: _sendLocation)),
      const Divider(height: 1),
      Expanded(child: ListView.builder(itemCount: _msgs.length, padding: const EdgeInsets.all(12), itemBuilder: (c,i){
        var m = _msgs[i];
        return Align(alignment: m['me']? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: m['me']? const Color(0xFF13B8D5) : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m['text'], style: TextStyle(color: m['me']? Colors.white : null)),
          const SizedBox(height: 2),
          Text(m['time'], style: TextStyle(fontSize: 10, color: m['me']? Colors.white70 : Colors.grey)),
        ])));
      })),
      SafeArea(child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        IconButton(icon: const Icon(Icons.location_on, color: Colors.red), onPressed: _sendLocation),
        Expanded(child: TextField(controller: _msgCtrl, decoration: const InputDecoration(hintText: 'اكتب رسالة...', border: OutlineInputBorder()), onSubmitted: (v)=>_send(v))),
        const SizedBox(width: 6),
        FilledButton(onPressed: ()=>_send(_msgCtrl.text), child: const Icon(Icons.send)),
      ]))),
    ]);
  }
}

class SettingsPage extends StatelessWidget { const SettingsPage({super.key}); @override Widget build(BuildContext context) { return const Center(child: Text('الاعدادات')); } }