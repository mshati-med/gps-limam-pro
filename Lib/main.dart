import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GpsLimamApp());
}

class GpsLimamApp extends StatefulWidget {
  const GpsLimamApp({super.key});

  @override
  State<GpsLimamApp> createState() => _GpsLimamAppState();
}

class _GpsLimamAppState extends State<GpsLimamApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = prefs.getBool('dark_mode') ?? true
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  Future<void> _toggleTheme() async {
    final next = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', next == ThemeMode.dark);
    setState(() => _themeMode = next);
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF13B8D5);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GPS LIMAM',
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF081522),
        useMaterial3: true,
      ),
      home: HomePage(onToggleTheme: _toggleTheme, isDark: _themeMode == ThemeMode.dark),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onToggleTheme, required this.isDark});
  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController _mapController = MapController();
  int _tab = 0;
  LatLng _center = const LatLng(18.0735, -15.9582); // Nouakchott, initial map view
  String _status = 'الخريطة جاهزة — فعّل GPS لتحديد موقعك';
  bool _locating = false;

  Future<void> _locateMe() async {
    setState(() {
      _locating = true;
      _status = 'جارٍ تحديد الموقع...';
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => _status = 'شغّل خدمة الموقع GPS من إعدادات الهاتف');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _status = 'يلزم السماح للتطبيق بالوصول إلى الموقع');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _center = LatLng(pos.latitude, pos.longitude);
      _mapController.move(_center, 15);
      setState(() => _status = 'تم تحديد موقعك الحالي');
    } catch (_) {
      setState(() => _status = 'تعذر تحديد الموقع؛ تحقق من GPS والأذونات');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Widget _placeholder(String title, String detail, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _center, initialZoom: 11),
            children: [
              TileLayer(
                // Prototype online layer only. Do not bulk-download from the public OSM tile server.
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.gpslimam.app',
              ),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
              ),
            ],
          ),
          Positioned(
            top: 14,
            right: 14,
            left: 14,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.explore, color: Color(0xFF13B8D5), size: 30),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GPS LIMAM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          Text('خرائطك • أصدقاؤك • طريقك', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'تبديل المظهر',
                      onPressed: widget.onToggleTheme,
                      icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 22,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'locate',
              onPressed: _locating ? null : _locateMe,
              child: _locating
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_status, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
      _placeholder('الأصدقاء', 'ستضاف هنا طلبات الصداقة والارتباط ومشاركة الموقع بموافقة الطرفين.', Icons.people_alt_outlined),
      _placeholder('الدردشة', 'ستضاف هنا المحادثات الخاصة وإرسال المواقع بعد إعداد الخادم الآمن.', Icons.chat_bubble_outline),
      _placeholder('الخرائط المحفوظة', 'الخطوة التالية: تنزيل مناطق محددة وتخزينها محليًا لاستخدامها دون إنترنت.', Icons.download_for_offline_outlined),
      _placeholder('الإعدادات', 'المظهر الحالي محفوظ على الهاتف. ستضاف إعدادات الخصوصية والحساب واللغة لاحقًا.', Icons.settings_outlined),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'الخريطة'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'الأصدقاء'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), selectedIcon: Icon(Icons.chat), label: 'الدردشة'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'خرائطي'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
