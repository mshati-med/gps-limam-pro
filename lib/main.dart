import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
  runApp(const GpsLimamApp());
}

class GpsLimamApp extends StatefulWidget {
  const GpsLimamApp({super.key});
  @override State<GpsLimamApp> createState() => _GpsLimamAppState();
}

class _GpsLimamAppState extends State<GpsLimamApp> {
  ThemeMode _mode = ThemeMode.dark;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _mode = (p.getBool('dark')?? true)? ThemeMode.dark : ThemeMode.light);
  }
  @override Widget build(BuildContext context) {
    const seed = Color(0xFF13B8D5);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GPS LIMAM PRO',
      themeMode: _mode,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light)),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark), scaffoldBackgroundColor: const Color(0xFF081522)),
      home: MainScreen(onToggle: () async {
        final p = await SharedPreferences.getInstance();
        final next = _mode == ThemeMode.dark? ThemeMode.light : ThemeMode.dark;
        await p.setBool('dark', next == ThemeMode.dark);
        setState(() => _mode = next);
      }, isDark: _mode == ThemeMode.dark),
    );
  }
}

class MainScreen extends StatefulWidget {
  final VoidCallback onToggle; final bool isDark;
  const MainScreen({super.key, required this.onToggle, required this.isDark});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;
  @override Widget build(BuildContext context) {
    final pages = [
      MapPage(isDark: widget.isDark, onToggle: widget.onToggle),
      const FriendsPage(),
      const ChatPagePro(),
      const OfflinePage(),
      SettingsPage(onToggle: widget.onToggle, isDark: widget.isDark),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'الخريطة'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'الأصدقاء'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'الدردشة'),
          NavigationDestination(icon: Icon(Icons.layers_outlined), selectedIcon: Icon(Icons.layers), label: 'خرائطي'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ================= MAP PAGE - LIVE =================
class MapPage extends StatefulWidget {
  final bool isDark; final VoidCallback onToggle;
  const MapPage({super.key, required this.isDark, required this.onToggle});
  @override State<MapPage> createState() => _MapPageState();
}
class _MapPageState extends State<MapPage> {
  final _mapCtrl = MapController();
  LatLng _myPos = const LatLng(18.0735, -15.9582);
  LatLng? _partnerPos;
  String _status = 'جاري التحميل...';
  StreamSubscription<Position>? _posSub;
  String myCode = ''; String partnerCode = ''; String chatId = '';

  @override void initState() { super.initState(); _initAll(); }

  Future<void> _initAll() async {
    final p = await SharedPreferences.getInstance();
    myCode = p.getString('my_code')?? '';
    partnerCode = p.getString('partner_code')?? '';
    if(myCode.isEmpty){
      myCode = (100000 + DateTime.now().millisecondsSinceEpoch % 900000).toString();
      await p.setString('my_code', myCode);
      await FirebaseFirestore.instance.collection('users').doc(myCode).set({'code': myCode, 'created': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
    if(partnerCode.isNotEmpty){
      List<String> ids = [myCode, partnerCode]..sort();
      chatId = ids.join('_');
      _listenPartner();
    }
    _startLocation();
  }

  void _listenPartner(){
    if(chatId.isEmpty) return;
    FirebaseFirestore.instance.collection('users').doc(partnerCode).snapshots().listen((doc){
      if(doc.exists && doc.data()!.containsKey('lat')){
        setState(() => _partnerPos = LatLng(doc['lat'], doc['lng']));
      }
    });
  }

  Future<void> _startLocation() async {
    if(!await Geolocator.isLocationServiceEnabled()){ setState(()=>_status='فعل GPS'); return; }
    var perm = await Geolocator.checkPermission();
    if(perm==LocationPermission.denied) perm = await Geolocator.requestPermission();
    if(perm==LocationPermission.denied || perm==LocationPermission.deniedForever){ setState(()=>_status='السماح بالموقع مطلوب'); return; }

    setState(()=>_status='يتم التتبع المباشر...');
    _posSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)).listen((pos) async {
      _myPos = LatLng(pos.latitude, pos.longitude);
      if(mounted){
        _mapCtrl.move(_myPos, _mapCtrl.camera.zoom);
        setState(()=>_status='مباشر - ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
      }
      // تحديث موقعي في Firebase ليظهر لصديقي
      if(myCode.isNotEmpty){
        await FirebaseFirestore.instance.collection('users').doc(myCode).update({'lat': pos.latitude, 'lng': pos.longitude, 'updated': FieldValue.serverTimestamp()});
      }
    });
  }

  @override void dispose(){ _posSub?.cancel(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return Stack(children: [
      FlutterMap(mapController: _mapCtrl, options: MapOptions(initialCenter: _myPos, initialZoom: 14), children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.gpslimam.app'),
        MarkerLayer(markers: [
          Marker(point: _myPos, width: 50, height: 50, child: const Icon(Icons.my_location, color: Colors.blue, size: 38)),
          if(_partnerPos!=null) Marker(point: _partnerPos!, width: 50, height: 50, child: const Icon(Icons.person_pin_circle, color: Colors.red, size: 42)),
        ]),
      ]),
      SafeArea(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        Card(child: ListTile(leading: const Icon(Icons.explore, color: Color(0xFF13B8D5)), title: const Text('GPS LIMAM PRO', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(_status, style: const TextStyle(fontSize: 11)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: widget.onToggle, icon: Icon(widget.isDark? Icons.light_mode: Icons.dark_mode)),
          IconButton(onPressed: () => Share.share('تابعني مباشر: https://maps.google.com/?q=${_myPos.latitude},${_myPos.longitude}'), icon: const Icon(Icons.share)),
        ]))),
        const Spacer(),
        Row(children: [
          FloatingActionButton.small(heroTag: 'my', onPressed: ()=>_mapCtrl.move(_myPos, 16), child: const Icon(Icons.my_location)),
          const SizedBox(width: 10),
          if(_partnerPos!=null) FloatingActionButton.small(heroTag: 'partner', backgroundColor: Colors.red, onPressed: ()=>_mapCtrl.move(_partnerPos!, 16), child: const Icon(Icons.person)),
        ]),
      ]))),
    ]);
  }
}

// ================= FRIENDS PRO =================
class FriendsPage extends StatefulWidget { const FriendsPage({super.key}); @override State<FriendsPage> createState() => _FriendsPageState(); }
class _FriendsPageState extends State<FriendsPage> {
  String myCode=''; String partner=''; final _ctrl=TextEditingController(); bool loading=true;
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    final p=await SharedPreferences.getInstance();
    myCode=p.getString('my_code')??'';
    partner=p.getString('partner_code')??'';
    if(myCode.isEmpty){ myCode=(100000+DateTime.now().millisecondsSinceEpoch%900000).toString(); await p.setString('my_code', myCode); await FirebaseFirestore.instance.collection('users').doc(myCode).set({'code':myCode}, SetOptions(merge:true)); }
    setState(()=>loading=false);
  }
  Future<void> _link() async {
    String pc=_ctrl.text.trim();
    if(pc.length<5) return;
    var doc=await FirebaseFirestore.instance.collection('users').doc(pc).get();
    if(!doc.exists){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرمز غير موجود، تأكد من صديقك'))); return; }
    final p=await SharedPreferences.getInstance();
    await p.setString('partner_code', pc);
    List<String> ids=[myCode,pc]..sort();
    await FirebaseFirestore.instance.collection('chats').doc(ids.join('_')).set({'users':ids}, SetOptions(merge:true));
    setState(()=>partner=pc);
  }
  @override Widget build(BuildContext context) {
    if(loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(appBar: AppBar(title: const Text('الأصدقاء - PRO')), body: Padding(padding: const EdgeInsets.all(20), child: ListView(children: [
      Card(elevation: 3, child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const Text('رمزك الاحترافي', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        QrImageView(data: myCode, size: 180, backgroundColor: Colors.white),
        const SizedBox(height: 12),
        Text(myCode, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 6)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: ()=>Share.share('رمز GPS LIMAM PRO: $myCode'), icon: const Icon(Icons.share), label: const Text('مشاركة الرمز')),
      ]))),
      const SizedBox(height: 20),
      if(partner.isEmpty)...[
        TextField(controller: _ctrl, decoration: const InputDecoration(labelText: 'رمز شريكك', border: OutlineInputBorder(), prefixIcon: Icon(Icons.vpn_key)), keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        FilledButton(onPressed: _link, child: const Text('ربط احترافي')),
      ] else Card(color: Theme.of(context).colorScheme.primaryContainer, child: ListTile(leading: const Icon(Icons.verified, color: Colors.green), title: Text('مرتبط مع $partner'), subtitle: const Text('التتبع المباشر والدردشة مفعلة'), trailing: IconButton(icon: const Icon(Icons.link_off), onPressed: () async { final p=await SharedPreferences.getInstance(); await p.remove('partner_code'); setState(()=>partner=''); }))),
    ])));
  }
}

// ================= CHAT PRO - REAL TIME =================
class ChatPagePro extends StatefulWidget { const ChatPagePro({super.key}); @override State<ChatPagePro> createState() => _ChatPageProState(); }
class _ChatPageProState extends State<ChatPagePro> {
  final _ctrl=TextEditingController(); String myCode=''; String partner=''; String chatId='';
  @override void initState(){ super.initState(); _init(); }
  Future<void> _init() async {
    final p=await SharedPreferences.getInstance();
    myCode=p.getString('my_code')??''; partner=p.getString('partner_code')??'';
    if(partner.isNotEmpty){ List<String> ids=[myCode,partner]..sort(); chatId=ids.join('_'); setState((){}); }
  }
  Future<void> _send(String t) async {
    if(t.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').add({'text':t.trim(),'sender':myCode,'time':FieldValue.serverTimestamp()});
    _ctrl.clear();
  }
  @override Widget build(BuildContext context) {
    if(partner.isEmpty) return const Scaffold(body: Center(child: Text('اربط مع صديق أولاً من تبويب الأصدقاء')));
    return Scaffold(appBar: AppBar(title: Text('دردشة مع $partner'), actions: [IconButton(icon: const Icon(Icons.my_location), onPressed: () async { final pos=await Geolocator.getCurrentPosition(); _send('https://maps.google.com/?q=${pos.latitude},${pos.longitude}'); })]),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').orderBy('time').snapshots(), builder: (c,s){
          if(!s.hasData) return const Center(child: CircularProgressIndicator());
          return ListView.builder(itemCount: s.data!.docs.length, padding: const EdgeInsets.all(12), itemBuilder: (c,i){
            var d=s.data!.docs[i].data() as Map<String,dynamic>;
            bool me=d['sender']==myCode;
            bool isLoc=(d['text'] as String).contains('maps.google.com');
            return Align(alignment: me? Alignment.centerRight:Alignment.centerLeft, child: GestureDetector(onTap: isLoc? () async { final uri=Uri.parse(d['text']); if(await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication); }:null, child: Container(margin: const EdgeInsets.symmetric(vertical:4), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: me? const Color(0xFF13B8D5):Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)), child: Text(d['text']??'', style: TextStyle(color: me? Colors.white: null, decoration: isLoc? TextDecoration.underline: null)))));
          });
        })),
        SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [Expanded(child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: 'رسالة...', border: OutlineInputBorder()), onSubmitted: _send)), const SizedBox(width:8), FilledButton(onPressed: ()=>_send(_ctrl.text), child: const Icon(Icons.send))]))),
      ]),
    );
  }
}

class OfflinePage extends StatelessWidget { const OfflinePage({super.key}); @override Widget build(BuildContext context){ return Scaffold(appBar: AppBar(title: const Text('خرائطي')), body: const Center(child: Text('قريباً: تحميل خرائط Offline للصحراء'))); }}
class SettingsPage extends StatelessWidget {
  final VoidCallback onToggle; final bool isDark;
  const SettingsPage({super.key, required this.onToggle, required this.isDark});
  @override Widget build(BuildContext context){ return Scaffold(appBar: AppBar(title: const Text('الإعدادات')), body: ListView(children: [
    SwitchListTile(title: const Text('الوضع الليلي'), value: isDark, onChanged: (_)=>onToggle()),
    ListTile(title: const Text('GPS LIMAM PRO v1.0'), subtitle: const Text('تتبع احترافي مباشر + دردشة')),
    ListTile(title: const Text('تواصل'), subtitle: const Text('gps-limam@example.com')),
  ]));}
}