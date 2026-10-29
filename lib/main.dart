import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services.dart';

const _forest = Color(0xFF365A49);
const _ink = Color(0xFF253C31);
const _paper = Color(0xFFF7F8F2);
const _sage = Color(0xFFE9EFE5);
const _peach = Color(0xFFF5E6DC);

void main() => runApp(const GlowlyApp());

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.price,
    required this.priceLabel,
    required this.currency,
    required this.imageUrl,
    required this.productUrl,
    required this.source,
    required this.category,
    required this.description,
    required this.priceCheckedAt,
    this.rating,
    this.reviewsCount,
  });

  final String id;
  final String name;
  final String brand;
  final double? price;
  final String priceLabel;
  final String currency;
  final String imageUrl;
  final String productUrl;
  final String source;
  final String category;
  final String description;
  final String priceCheckedAt;
  final double? rating;
  final int? reviewsCount;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: '${json['id'] ?? json['name']}',
        name: '${json['name'] ?? 'Skincare product'}',
        brand: '${json['brand'] ?? json['source'] ?? 'Retailer'}',
        price: (json['price'] as num?)?.toDouble(),
        priceLabel: '${json['price_label'] ?? ''}',
        currency: '${json['currency'] ?? 'INR'}',
        imageUrl: '${json['image_url'] ?? ''}',
        productUrl: '${json['product_url'] ?? ''}',
        source: '${json['source'] ?? 'Online retailer'}',
        category: '${json['category'] ?? 'Skincare'}',
        description: '${json['description'] ?? ''}',
        priceCheckedAt: '${json['price_verified_at'] ?? ''}',
        rating: (json['rating'] as num?)?.toDouble(),
        reviewsCount: (json['reviews'] as num?)?.toInt(),
      );
}

class RoutineStep {
  RoutineStep({
    required this.id,
    required this.title,
    required this.product,
    required this.time,
    required this.period,
    this.done = false,
  });

  final int id;
  final String title;
  final String product;
  final String time;
  final String period;
  bool done;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'product': product,
        'time': time,
        'period': period,
        'done': done,
      };

  factory RoutineStep.fromJson(Map<String, dynamic> json) => RoutineStep(
        id: json['id'] as int,
        title: '${json['title']}',
        product: '${json['product']}',
        time: '${json['time']}',
        period: '${json['period']}',
        done: json['done'] as bool? ?? false,
      );
}

class ProductReview {
  ProductReview({
    required this.id,
    required this.product,
    required this.rating,
    required this.skinType,
    required this.duration,
    required this.reaction,
    required this.notes,
    required this.date,
  });

  final String id;
  final String product;
  final int rating;
  final String skinType;
  final String duration;
  final String reaction;
  final String notes;
  final String date;

  Map<String, dynamic> toJson() => {
        'id': id,
        'product': product,
        'rating': rating,
        'skinType': skinType,
        'duration': duration,
        'reaction': reaction,
        'notes': notes,
        'date': date,
      };

  factory ProductReview.fromJson(Map<String, dynamic> json) => ProductReview(
        id: '${json['id']}',
        product: '${json['product']}',
        rating: json['rating'] as int,
        skinType: '${json['skinType']}',
        duration: '${json['duration']}',
        reaction: '${json['reaction']}',
        notes: '${json['notes']}',
        date: '${json['date']}',
      );
}

class GlowlyApp extends StatefulWidget {
  const GlowlyApp({super.key});

  @override
  State<GlowlyApp> createState() => _GlowlyAppState();
}

class _GlowlyAppState extends State<GlowlyApp> {
  final _api = GlowlyApi();
  final _navigatorKey = GlobalKey<NavigatorState>();
  int _tab = 0;
  String _userId = 'guest';
  bool _loaded = false;
  List<RoutineStep> _routine = [];
  List<ProductReview> _reviews = [];

  @override
  void initState() {
    super.initState();
    _loadLocal();
    RoutineReminderService.instance.initialize();
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString('glowly_user_id');
    if (userId == null) {
      userId = '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(9999)}';
      await prefs.setString('glowly_user_id', userId);
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final routineRaw = prefs.getStringList('glowly_routine') ?? [];
    final reviewsRaw = prefs.getStringList('glowly_reviews') ?? [];
    final routine = routineRaw
        .map((s) => RoutineStep.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    // Completion resets each new day while reminders continue at their saved time.
    if (prefs.getString('glowly_completion_day') != today) {
      for (final item in routine) {
        item.done = false;
      }
      await prefs.setString('glowly_completion_day', today);
    }
    if (!mounted) return;
    setState(() {
      _userId = userId!;
      _routine = routine;
      _reviews = reviewsRaw
          .map((s) => ProductReview.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
      _loaded = true;
    });
  }

  Future<void> _persistRoutine() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'glowly_routine',
      _routine.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> _persistReviews() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'glowly_reviews',
      _reviews.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> _addRoutine(RoutineStep item) async {
    setState(() => _routine.add(item));
    await _persistRoutine();
    await RoutineReminderService.instance.schedule(item.id, item.title, item.time);
  }

  Future<void> _toggleRoutine(RoutineStep item) async {
    setState(() => item.done = !item.done);
    await _persistRoutine();
  }

  Future<void> _deleteRoutine(RoutineStep item) async {
    setState(() => _routine.removeWhere((step) => step.id == item.id));
    await _persistRoutine();
    await RoutineReminderService.instance.cancel(item.id);
  }

  Future<void> _addReview(ProductReview review) async {
    setState(() => _reviews.insert(0, review));
    await _persistReviews();
    try {
      await _api.saveReview({
        'client_id': review.id,
        'user_id': _userId,
        'product_name': review.product,
        'rating': review.rating,
        'skin_type': review.skinType,
        'duration': review.duration,
        'reaction': review.reaction,
        'notes': review.notes,
      });
    } catch (_) {
      // Keep the review on this device if the optional cloud sync is unavailable.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your product review is saved.')),
      );
    }
  }

  Future<void> _deleteReview(ProductReview review) async {
    setState(() => _reviews.remove(review));
    await _persistReviews();
    try {
      await _api.deleteReview(review.id, _userId);
    } catch (_) {
      // The device copy is still removed if the backend cannot be reached.
    }
  }

  Future<void> _openReviewEditor([String initialProduct = '']) async {
    final navigatorContext = _navigatorKey.currentState?.overlay?.context;
    if (navigatorContext == null) return;
    final result = await showDialog<ProductReview>(
      context: navigatorContext,
      builder: (_) => ReviewEditor(initialProduct: initialProduct),
    );
    if (result != null) await _addReview(result);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        routine: _routine,
        reviews: _reviews,
        onExplore: () => setState(() => _tab = 1),
        onScan: () => setState(() => _tab = 2),
        onRoutine: () => setState(() => _tab = 3),
        onShelf: () => setState(() => _tab = 4),
        onAddReview: () => _openReviewEditor(),
      ),
      DiscoverPage(
        api: _api,
        onAddRoutine: _addRoutine,
        onReviewProduct: (name) => _openReviewEditor(name),
      ),
      SkinReviewPage(
        api: _api,
        onAddRoutine: _addRoutine,
        onReviewProduct: (name) => _openReviewEditor(name),
      ),
      RoutinePage(
        routine: _routine,
        onAdd: _addRoutine,
        onToggle: _toggleRoutine,
        onDelete: _deleteRoutine,
      ),
      ShelfPage(
        reviews: _reviews,
        onAddReview: () => _openReviewEditor(),
        onDelete: _deleteReview,
      ),
    ];
    return MaterialApp(
      title: 'Glowly',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _paper,
        colorScheme: ColorScheme.fromSeed(seedColor: _forest, surface: _paper),
        appBarTheme: const AppBarTheme(
          backgroundColor: _paper,
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: Color(0xFF909A91)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE6EAE2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE6EAE2)),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE9ECE5)),
          ),
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: _loaded ? IndexedStack(index: _tab, children: pages) : const Center(child: CircularProgressIndicator()),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          backgroundColor: Colors.white,
          indicatorColor: _sage,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Discover'),
            NavigationDestination(icon: Icon(Icons.face_retouching_natural_outlined), selectedIcon: Icon(Icons.face_retouching_natural), label: 'AI review'),
            NavigationDestination(icon: Icon(Icons.notifications_none_rounded), selectedIcon: Icon(Icons.notifications_active_rounded), label: 'Routine'),
            NavigationDestination(icon: Icon(Icons.spa_outlined), selectedIcon: Icon(Icons.spa_rounded), label: 'My shelf'),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.routine, required this.reviews, required this.onExplore, required this.onScan, required this.onRoutine, required this.onShelf, required this.onAddReview});
  final List<RoutineStep> routine;
  final List<ProductReview> reviews;
  final VoidCallback onExplore;
  final VoidCallback onScan;
  final VoidCallback onRoutine;
  final VoidCallback onShelf;
  final VoidCallback onAddReview;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
    final todaySteps = routine.where((item) => item.period == (hour < 16 ? 'AM' : 'PM')).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
      Row(children: [
        Container(width: 42, height: 42, decoration: const BoxDecoration(color: _forest, shape: BoxShape.circle), child: const Icon(Icons.spa_rounded, color: Colors.white, size: 22)),
        const SizedBox(width: 11), const Text('glowly', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -1, color: _ink)),
        const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: _sage, borderRadius: BorderRadius.circular(30)), child: Text(DateFormat('EEE, d MMM').format(DateTime.now()), style: const TextStyle(fontSize: 12, color: _forest, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 26),
      Text('$greeting ✨', style: const TextStyle(color: _forest, fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6), const Text('Your skin,\nyour kind of care.', style: TextStyle(fontSize: 32, height: 1.08, letterSpacing: -1.4, color: _ink, fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      InkWell(
        borderRadius: BorderRadius.circular(24), onTap: onScan,
        child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: _forest, borderRadius: BorderRadius.circular(24)), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('YOUR SKIN CHECK-IN', style: TextStyle(color: Color(0xFFC5D3C5), fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w700)), const SizedBox(height: 9), const Text('Get a gentle\nAI skin review', style: TextStyle(color: Colors.white, fontSize: 22, height: 1.12, fontWeight: FontWeight.w600)), const SizedBox(height: 15), Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)), child: const Text('Start a review  →', style: TextStyle(color: _forest, fontWeight: FontWeight.w700, fontSize: 12)))])),
          const SizedBox(width: 10), Container(width: 102, height: 102, decoration: BoxDecoration(color: const Color(0xFF6D8C76), borderRadius: BorderRadius.circular(32)), child: const Icon(Icons.face_3_rounded, size: 67, color: Color(0xFFE0E8D8))),
        ])),
      ),
      const SizedBox(height: 24),
      Row(children: [const Expanded(child: SectionHeading(title: 'Your rhythm', subtitle: 'Small steps, steady glow')), TextButton(onPressed: onRoutine, child: const Text('See all'))]),
      if (todaySteps.isEmpty) _EmptyRoutineCard(onTap: onRoutine) else ...todaySteps.take(2).map((item) => Padding(padding: const EdgeInsets.only(bottom: 9), child: RoutinePreview(item: item, onTap: onRoutine))),
      const SizedBox(height: 17),
      Row(children: [Expanded(child: _QuickCard(icon: Icons.shopping_bag_outlined, title: 'Find your next favourite', body: 'Compare live prices & picks', color: _peach, onTap: onExplore)), const SizedBox(width: 12), Expanded(child: _QuickCard(icon: Icons.auto_awesome_outlined, title: 'Your product diary', body: '${reviews.length} ${reviews.length == 1 ? 'review' : 'reviews'} saved', color: _sage, onTap: reviews.isEmpty ? onAddReview : onShelf))]),
      const SizedBox(height: 23),
      const Text('A note for you', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10), Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFFCF2E7), borderRadius: BorderRadius.circular(19)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.wb_sunny_outlined, color: Color(0xFFA76E3D)), SizedBox(width: 12), Expanded(child: Text('Daily sunscreen is a lovely last step in your morning routine. Reapply as directed on the product label.', style: TextStyle(color: _ink, height: 1.4, fontSize: 13)))])),
    ]);
  }
}

class _EmptyRoutineCard extends StatelessWidget {
  const _EmptyRoutineCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE9ECE5))), child: const Row(children: [Icon(Icons.add_circle_outline, color: _forest), SizedBox(width: 11), Expanded(child: Text('Add a routine step to get started', style: TextStyle(color: _ink, fontWeight: FontWeight.w600))), Icon(Icons.chevron_right, color: _forest)])));
}

class RoutinePreview extends StatelessWidget {
  const RoutinePreview({super.key, required this.item, required this.onTap});
  final RoutineStep item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(17), child: Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE9ECE5))), child: Row(children: [Container(width: 37, height: 37, decoration: const BoxDecoration(color: _sage, shape: BoxShape.circle), child: Icon(item.done ? Icons.check : Icons.water_drop_outlined, color: _forest, size: 18)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)), Text(item.product, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF778278), fontSize: 12))])), Text(item.time, style: const TextStyle(fontWeight: FontWeight.w600, color: _forest, fontSize: 12))])));
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.title, required this.body, required this.color, required this.onTap});
  final IconData icon; final String title; final String body; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Container(height: 144, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: _forest), const Spacer(), Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 14, height: 1.2)), const SizedBox(height: 4), Text(body, style: const TextStyle(color: Color(0xFF738075), fontSize: 11))])));
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, required this.subtitle});
  final String title; final String subtitle;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 18, color: _ink, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: Color(0xFF818B82), fontSize: 12))]);
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.api, required this.onAddRoutine, required this.onReviewProduct});
  final GlowlyApi api;
  final Future<void> Function(RoutineStep) onAddRoutine;
  final ValueChanged<String> onReviewProduct;
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _search = TextEditingController(text: '');
  final _maxPrice = TextEditingController();
  List<Product> _products = [];
  final Set<String> _compareIds = {};
  String _skinType = 'All';
  String _category = 'All';
  String _sort = 'relevance';
  bool _loading = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _compareIds.clear(); });
    try {
      final items = await widget.api.searchProducts(
        query: _search.text.trim(), skinType: _skinType, category: _category,
        sort: _sort, maxPrice: double.tryParse(_maxPrice.text),
      );
      if (mounted) setState(() => _products = items.map(Product.fromJson).toList());
    } catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _filters() async {
    var skin = _skinType, category = _category, sort = _sort;
    final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: _paper, builder: (context) => StatefulBuilder(builder: (context, setSheet) => Padding(padding: EdgeInsets.fromLTRB(22, 18, 22, 24 + MediaQuery.of(context).viewInsets.bottom), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD9DED8), borderRadius: BorderRadius.circular(4))),), const SizedBox(height: 17), const Text('Refine your search', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: _ink)),
      const SizedBox(height: 13), const Text('Skin type', style: TextStyle(color: _ink, fontWeight: FontWeight.w600)), const SizedBox(height: 8), Wrap(spacing: 7, children: ['All','Oily','Dry','Combination','Sensitive'].map((value) => ChoiceChip(label: Text(value), selected: skin == value, onSelected: (_) => setSheet(() => skin = value))).toList()),
      const SizedBox(height: 12), const Text('Category', style: TextStyle(color: _ink, fontWeight: FontWeight.w600)), const SizedBox(height: 8), Wrap(spacing: 7, children: ['All','Cleanser','Serum','Moisturizer','Sunscreen'].map((value) => ChoiceChip(label: Text(value), selected: category == value, onSelected: (_) => setSheet(() => category = value))).toList()),
      const SizedBox(height: 12), DropdownButtonFormField<String>(value: sort, decoration: const InputDecoration(labelText: 'Sort by'), items: const [DropdownMenuItem(value: 'relevance', child: Text('Recommended')), DropdownMenuItem(value: 'price_asc', child: Text('Price: low to high')), DropdownMenuItem(value: 'price_desc', child: Text('Price: high to low')), DropdownMenuItem(value: 'rating', child: Text('Top rated'))], onChanged: (v) => setSheet(() => sort = v ?? 'relevance')),
      const SizedBox(height: 16), Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))), const SizedBox(width: 10), Expanded(child: FilledButton(onPressed: () { _skinType=skin; _category=category; _sort=sort; Navigator.pop(context, true); }, child: const Text('Apply filters')))]),
    ]))));
    if (result == true) _load();
  }

  void _compare() {
    final selected = _products.where((p) => _compareIds.contains(p.id)).toList();
    showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Compare products'), content: SizedBox(width: 550, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: [const DataColumn(label: Text('')), ...selected.map((p) => DataColumn(label: SizedBox(width: 125, child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis))))], rows: [
      DataRow(cells: [const DataCell(Text('Price')), ...selected.map((p) => DataCell(Text(p.priceLabel.isNotEmpty ? p.priceLabel : 'Not listed')))]),
      DataRow(cells: [const DataCell(Text('Merchant')), ...selected.map((p) => DataCell(Text(p.brand)))]),
      DataRow(cells: [const DataCell(Text('Rating')), ...selected.map((p) => DataCell(Text(p.rating == null ? 'Not listed' : '★ ${p.rating}')))]),
      DataRow(cells: [const DataCell(Text('Source')), ...selected.map((p) => DataCell(Text(p.source)))]),
    ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))]));
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 100), children: [
    const SectionHeading(title: 'Find your favourites', subtitle: 'Browse live prices and compare options'),
    const SizedBox(height: 18),
    Row(children: [Expanded(child: TextField(controller: _search, textInputAction: TextInputAction.search, onSubmitted: (_) => _load(), decoration: InputDecoration(hintText: 'Search cleanser, SPF, serum…', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () { _search.clear(); _load(); }, icon: const Icon(Icons.close))))), const SizedBox(width: 9), IconButton.filledTonal(onPressed: _filters, icon: const Icon(Icons.tune_rounded), style: IconButton.styleFrom(backgroundColor: _sage, foregroundColor: _forest, fixedSize: const Size(52, 52))) ]),
    const SizedBox(height: 11),
    Row(children: [Expanded(child: TextField(controller: _maxPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.currency_rupee, size: 19), hintText: 'Max price')),), const SizedBox(width: 8), FilledButton.tonal(onPressed: _load, child: const Text('Apply'))]),
    const SizedBox(height: 13),
    Text('Prices and stock come from current retailer listings. Check the merchant page before purchase.', style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 11, height: 1.3)),
    if (_compareIds.length >= 2) Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton.icon(onPressed: _compare, icon: const Icon(Icons.compare_arrows_rounded), label: Text('Compare ${_compareIds.length} products'))),
    const SizedBox(height: 14),
    if (_loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
    else if (_error != null) _ErrorCard(message: _error!, onRetry: _load)
    else if (_products.isEmpty) _EmptyState(icon: Icons.search_off_rounded, title: 'No products found', body: 'Try a broader search or remove a filter.')
    else ..._products.map((product) => Padding(padding: const EdgeInsets.only(bottom: 12), child: ProductCard(product: product, selected: _compareIds.contains(product.id), onCompare: () => setState(() => _compareIds.contains(product.id) ? _compareIds.remove(product.id) : _compareIds.add(product.id)), onReview: () => widget.onReviewProduct(product.name), onRoutine: () => _addToRoutine(product), onOpen: () => _openProduct(product)))),
  ]);

  Future<void> _addToRoutine(Product product) async {
    final now = TimeOfDay.now();
    final time = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
    await widget.onAddRoutine(RoutineStep(id: DateTime.now().microsecondsSinceEpoch.remainder(1 << 31), title: _guessStep(product.name), product: product.name, time: time, period: now.hour < 16 ? 'AM' : 'PM'));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to your routine with a daily reminder.')));
  }

  String _guessStep(String name) {
    final lower=name.toLowerCase(); if(lower.contains('cleanser')||lower.contains('wash')) return 'Cleanse'; if(lower.contains('serum')) return 'Serum'; if(lower.contains('sunscreen')||lower.contains('spf')) return 'Sunscreen'; if(lower.contains('moistur')) return 'Moisturize'; return 'Skincare';
  }
  Future<void> _openProduct(Product product) async { final uri=Uri.tryParse(product.productUrl); if(uri!=null&&uri.hasScheme) await launchUrl(uri,mode:LaunchMode.externalApplication); }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.selected, required this.onCompare, required this.onReview, required this.onRoutine, required this.onOpen, this.showCompare = true});
  final Product product; final bool selected; final VoidCallback onCompare; final VoidCallback onReview; final VoidCallback onRoutine; final VoidCallback onOpen; final bool showCompare;
  @override
  Widget build(BuildContext context) => Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    InkWell(onTap: onOpen, borderRadius: const BorderRadius.vertical(top: Radius.circular(22)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), bottomRight: Radius.circular(17)), child: Container(width: 112, height: 118, color: _sage, child: product.imageUrl.isNotEmpty ? Image.network(product.imageUrl, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.spa_outlined, color: _forest, size: 35)) : const Icon(Icons.spa_outlined,color:_forest,size:35))),
      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(13, 13, 9, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(product.brand.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, letterSpacing: .8, color: Color(0xFF7C897E), fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text(product.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, height: 1.25)), const SizedBox(height: 8), Text(product.priceLabel.isNotEmpty ? product.priceLabel : (product.price == null ? 'Price unavailable' : NumberFormat.simpleCurrency(name: product.currency).format(product.price!)), style: const TextStyle(fontSize: 15, color: _forest, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(product.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF89928A))), if (product.priceCheckedAt.isNotEmpty) Text(_fetchedLabel(product.priceCheckedAt), style: const TextStyle(fontSize: 9, color: Color(0xFF9AA198)))]))),
      if (showCompare) Checkbox(value: selected, onChanged: (_) => onCompare(), activeColor: _forest) else const SizedBox(width: 10),
    ])),
    Padding(padding: const EdgeInsets.fromLTRB(13, 0, 13, 11), child: Row(children: [if(product.rating!=null) ...[const Icon(Icons.star_rounded,color:Color(0xFFE2AC5C),size:17), Text('${product.rating}',style:const TextStyle(fontWeight:FontWeight.w700,fontSize:12)), const SizedBox(width:5)], const Spacer(), TextButton.icon(onPressed:onReview,icon:const Icon(Icons.rate_review_outlined,size:15),label:const Text('Review'),style:TextButton.styleFrom(visualDensity:VisualDensity.compact)), IconButton(onPressed:onRoutine,tooltip:'Add to routine',icon:const Icon(Icons.add_alarm_outlined,size:19,color:_forest)), TextButton(onPressed:onOpen,child:const Text('View deal  ↗',style:TextStyle(fontSize:11,fontWeight:FontWeight.w700))) ])),
  ]));
}

String _fetchedLabel(String timestamp) {
  final value = DateTime.tryParse(timestamp)?.toLocal();
  if (value == null) return '';
  return 'Fetched ${DateFormat('d MMM · h:mm a').format(value)}';
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message; final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(19), decoration: BoxDecoration(color: const Color(0xFFFFF1ED), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.cloud_off_outlined, color: Color(0xFFAA5B49)), const SizedBox(height: 8), const Text('Could not load live prices', style: TextStyle(fontWeight: FontWeight.w700, color: _ink)), const SizedBox(height: 5), Text(message, style: const TextStyle(color: Color(0xFF705E59), fontSize: 12, height: 1.35)), const SizedBox(height: 10), TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again'))]));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.body});
  final IconData icon; final String title; final String body;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 45), child: Column(children: [Icon(icon, size: 45, color: const Color(0xFF91A296)), const SizedBox(height: 12), Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 17)), const SizedBox(height: 5), Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF7B867E), fontSize: 13))]));
}

class SkinReviewPage extends StatefulWidget {
  const SkinReviewPage({
    super.key,
    required this.api,
    required this.onAddRoutine,
    required this.onReviewProduct,
  });
  final GlowlyApi api;
  final Future<void> Function(RoutineStep) onAddRoutine;
  final ValueChanged<String> onReviewProduct;
  @override
  State<SkinReviewPage> createState() => _SkinReviewPageState();
}

class _SkinReviewPageState extends State<SkinReviewPage> {
  final _picker = ImagePicker();
  final _goals = TextEditingController();
  File? _image;
  Map<String, dynamic>? _result;
  List<Product> _recommendedProducts = [];
  String? _searchingFor;
  bool _loading = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    final chosen = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1600);
    if (chosen != null) setState(() { _image = File(chosen.path); _result = null; _error = null; });
  }

  Future<void> _analyze() async {
    if (_image == null) return;
    setState(() { _loading = true; _error = null; _result = null; });
    try { final result = await widget.api.analyzeSkin(_image!, _goals.text.trim()); if (mounted) setState(() => _result = result); }
    catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _findProducts(String query) async {
    setState(() => _searchingFor = query);
    try {
      final results = await widget.api.searchProducts(query: query);
      if (mounted) setState(() => _recommendedProducts = results.map(Product.fromJson).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _searchingFor = null);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(20, 23, 20, 100), children: [
    const SectionHeading(title: 'A closer look', subtitle: 'Gentle, visual guidance for your routine'),
    const SizedBox(height: 18),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: _sage, borderRadius: BorderRadius.circular(20)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.shield_outlined,color:_forest),SizedBox(width:11),Expanded(child:Text('Your photo is sent to your configured AI provider for this review and is not saved by Glowly. AI observations are cosmetic guidance, not a diagnosis.',style:TextStyle(color:_ink,fontSize:12,height:1.4)))])),
    const SizedBox(height: 16),
    InkWell(onTap: () => _pick(ImageSource.gallery), borderRadius: BorderRadius.circular(23), child: Container(height: 245, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: const Color(0xFFE9ECE4), borderRadius: BorderRadius.circular(23)), child: _image == null ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width:65,height:65,decoration:const BoxDecoration(color:Colors.white,shape:BoxShape.circle),child:const Icon(Icons.add_a_photo_outlined,color:_forest,size:29)),const SizedBox(height:12),const Text('Add a clear, natural-light selfie',style:TextStyle(color:_ink,fontWeight:FontWeight.w700)),const SizedBox(height:5),const Text('Tap to choose a photo from your gallery',style:TextStyle(color:Color(0xFF79847B),fontSize:12))]) : Stack(fit:StackFit.expand,children:[Image.file(_image!,fit:BoxFit.cover),Positioned(right:10,top:10,child:IconButton.filled(onPressed:()=>setState(()=>_image=null),icon:const Icon(Icons.close),style:IconButton.styleFrom(backgroundColor:Colors.white)))]))),
    const SizedBox(height: 15),
    TextField(controller:_goals,maxLines:2,decoration:const InputDecoration(labelText:'What are you focusing on?',hintText:'For example: keeping my routine simple',prefixIcon:Icon(Icons.notes_rounded))),
    const SizedBox(height: 13),
    Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>_pick(ImageSource.camera),icon:const Icon(Icons.camera_alt_outlined),label:const Text('Take a photo'))),const SizedBox(width:10),Expanded(child:FilledButton.icon(onPressed:_image==null||_loading?null:_analyze,icon:_loading?const SizedBox(width:17,height:17,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.auto_awesome),label:Text(_loading?'Reviewing…':'Review my skin')))]),
    if(_error!=null) Padding(padding:const EdgeInsets.only(top:14),child:_ErrorCard(message:_error!,onRetry:_analyze)),
    if(_result!=null) ..._buildResult(_result!),
  ]);

  List<Widget> _buildResult(Map<String,dynamic> result) {
    List<String> list(dynamic value) => value is List ? value.map((e)=>'$e').toList() : [];
    return [
      const SizedBox(height: 22),
      const SectionHeading(title: 'Your review', subtitle: 'Approximate observations from this photo'),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8EBE4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${result['summary'] ?? 'A gentle starting point'}', style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 16, height: 1.3)),
          const SizedBox(height: 12),
          ...list(result['observations']).map((v) => _Bullet(text: v)),
          if (list(result['routine_ideas']).isNotEmpty) ...[
            const SizedBox(height: 13), const Text('Routine ideas', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            ...list(result['routine_ideas']).map((v) => _Bullet(text: v)),
          ],
          if (list(result['ingredients_to_consider']).isNotEmpty) ...[
            const SizedBox(height: 13), const Text('Ingredients to consider', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            ...list(result['ingredients_to_consider']).map((v) => _Bullet(text: v)),
          ],
          if ('${result['caution'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12), Text('${result['caution']}', style: const TextStyle(color: Color(0xFF7B5C3E), fontSize: 12, height: 1.35)),
          ],
          const SizedBox(height: 14),
          Text('${result['disclaimer'] ?? 'AI observations are not a diagnosis.'}', style: const TextStyle(color: Color(0xFF8A9188), fontSize: 10, height: 1.4)),
        ]),
      ),
      if (list(result['product_searches']).isNotEmpty) ...[
        const SizedBox(height: 20),
        const SectionHeading(title: 'Shop gentle ideas', subtitle: 'Search live listings with current prices and retailer links'),
        const SizedBox(height: 9),
        Wrap(spacing: 8, runSpacing: 6, children: list(result['product_searches']).map((query) => ActionChip(
          avatar: _searchingFor == query ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search, size: 16),
          label: Text(query), onPressed: _searchingFor == null ? () => _findProducts(query) : null,
        )).toList()),
      ],
      if (_recommendedProducts.isNotEmpty) ..._recommendedProducts.map((product) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ProductCard(
          product: product, selected: false, onCompare: () {},
          onReview: () => widget.onReviewProduct(product.name),
          onRoutine: () {
            final now = TimeOfDay.now();
            final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
            widget.onAddRoutine(RoutineStep(id: DateTime.now().microsecondsSinceEpoch.remainder(1 << 31), title: 'Skincare', product: product.name, time: time, period: now.hour < 16 ? 'AM' : 'PM'));
          },
          onOpen: () { final uri = Uri.tryParse(product.productUrl); if (uri != null && uri.hasScheme) launchUrl(uri, mode: LaunchMode.externalApplication); },
          showCompare: false,
        ),
      )),
    ];
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text}); final String text;
  @override
  Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(top:8),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const Padding(padding:EdgeInsets.only(top:5),child:Icon(Icons.circle,size:6,color:_forest)),const SizedBox(width:9),Expanded(child:Text(text,style:const TextStyle(color:Color(0xFF53645A),height:1.4,fontSize:13)))]));
}

class RoutinePage extends StatelessWidget {
  const RoutinePage({super.key, required this.routine, required this.onAdd, required this.onToggle, required this.onDelete});
  final List<RoutineStep> routine;
  final Future<void> Function(RoutineStep) onAdd;
  final ValueChanged<RoutineStep> onToggle;
  final ValueChanged<RoutineStep> onDelete;
  @override
  Widget build(BuildContext context) {
    final completed = routine.where((step) => step.done).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 23, 20, 100),
      children: [
        const SectionHeading(
          title: 'Your daily ritual',
          subtitle: 'A routine that fits into your day',
        ),
        const SizedBox(height: 17),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _forest,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$completed of ${routine.length} steps today',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'A little care, one step at a time.',
                      style: TextStyle(
                        color: Color(0xFFCFDCCE),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              CircularProgressIndicator(
                value: routine.isEmpty ? 0 : completed / routine.length,
                backgroundColor: const Color(0xFF728879),
                color: const Color(0xFFE9D6AF),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (routine.isEmpty)
          const _EmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'Your routine starts here',
            body:
                'Add a step, choose a time, and Glowly will send a daily reminder.',
          )
        else
          ...['AM', 'PM'].map((period) {
            final items = routine.where((step) => step.period == period).toList()
              ..sort((a, b) => a.time.compareTo(b.time));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 13, bottom: 9),
                  child: Text(
                    period == 'AM' ? 'MORNING' : 'EVENING',
                    style: const TextStyle(
                      color: _forest,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'No ${period == 'AM' ? 'morning' : 'evening'} steps yet.',
                      style: const TextStyle(
                        color: Color(0xFF89928A),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: RoutineTile(
                      item: item,
                      onToggle: () => onToggle(item),
                      onDelete: () => onDelete(item),
                    ),
                  ),
                ),
              ],
            );
          }),
        const SizedBox(height: 9),
        FilledButton.icon(
          onPressed: () => _addRoutineDialog(context, onAdd),
          icon: const Icon(Icons.add),
          label: const Text('Add a routine step'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Reminders are saved on this device. Allow notifications when asked so they can reach you.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF889189), fontSize: 11),
        ),
      ],
    );
  }

  Future<void> _addRoutineDialog(BuildContext context,Future<void> Function(RoutineStep) onAdd) async {
    final result=await showDialog<RoutineStep>(context:context,builder:(_)=>const RoutineEditor());if(result!=null) await onAdd(result);
  }
}

class RoutineTile extends StatelessWidget {
  const RoutineTile({super.key,required this.item,required this.onToggle,required this.onDelete});final RoutineStep item;final VoidCallback onToggle;final VoidCallback onDelete;
  @override
  Widget build(BuildContext context)=>Container(padding:const EdgeInsets.fromLTRB(10,10,13,10),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(17),border:Border.all(color:const Color(0xFFE9ECE5))),child:Row(children:[Checkbox(value:item.done,onChanged:(_)=>onToggle(),activeColor:_forest),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(item.title,style:TextStyle(color:_ink,fontWeight:FontWeight.w700,decoration:item.done?TextDecoration.lineThrough:null)),Text(item.product,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Color(0xFF808B82),fontSize:12))])),Text(item.time,style:const TextStyle(color:_forest,fontWeight:FontWeight.w700,fontSize:12)),PopupMenuButton<String>(onSelected:(v){if(v=='delete')onDelete();},itemBuilder:(_)=>const[PopupMenuItem(value:'delete',child:Text('Remove step'))]) ]));
}

class RoutineEditor extends StatefulWidget { const RoutineEditor({super.key}); @override State<RoutineEditor> createState()=>_RoutineEditorState(); }
class _RoutineEditorState extends State<RoutineEditor> {
  final _product=TextEditingController();String _step='Cleanse';String _period='AM';TimeOfDay _time=const TimeOfDay(hour:8,minute:0);
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Add a routine step'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(value:_step,decoration:const InputDecoration(labelText:'Step'),items:const['Cleanse','Toner','Serum','Moisturize','Sunscreen','Treatment','Other'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>_step=v??'Cleanse')),const SizedBox(height:10),TextField(controller:_product,decoration:const InputDecoration(labelText:'Product name',hintText:'e.g. Gentle daily cleanser')),const SizedBox(height:12),Row(children:[Expanded(child:DropdownButtonFormField<String>(value:_period,decoration:const InputDecoration(labelText:'Routine'),items:const['AM','PM'].map((v)=>DropdownMenuItem(value:v,child:Text(v=='AM'?'Morning':'Evening'))).toList(),onChanged:(v)=>setState(()=>_period=v??'AM'))),const SizedBox(width:9),Expanded(child:OutlinedButton.icon(onPressed:()async{final time=await showTimePicker(context:context,initialTime:_time);if(time!=null)setState(()=>_time=time);},icon:const Icon(Icons.schedule),label:Text(_time.format(context))))])]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:(){final name=_product.text.trim();if(name.isEmpty)return;final t='${_time.hour.toString().padLeft(2,'0')}:${_time.minute.toString().padLeft(2,'0')}';Navigator.pop(context,RoutineStep(id:DateTime.now().microsecondsSinceEpoch.remainder(1<<31),title:_step,product:name,time:t,period:_period));},child:const Text('Save'))]);
}

class ShelfPage extends StatelessWidget {
  const ShelfPage({super.key,required this.reviews,required this.onAddReview,required this.onDelete});final List<ProductReview> reviews;final VoidCallback onAddReview;final ValueChanged<ProductReview> onDelete;
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.fromLTRB(20,23,20,100),children:[Row(children:[const Expanded(child:SectionHeading(title:'Your product diary',subtitle:'Keep track of what works for you')),IconButton.filledTonal(onPressed:onAddReview,icon:const Icon(Icons.add),style:IconButton.styleFrom(backgroundColor:_sage,foregroundColor:_forest))]),const SizedBox(height:17),
    if(reviews.length>=2) Padding(padding:const EdgeInsets.only(bottom:13),child:FilledButton.tonalIcon(onPressed:()=>_compareReviews(context,reviews),icon:const Icon(Icons.compare_arrows),label:const Text('Compare my products'))),
    if(reviews.isEmpty)...[const SizedBox(height:30),const _EmptyState(icon:Icons.auto_stories_outlined,title:'Your shelf is waiting',body:'Add a review after trying a product and build your own personal comparison guide.'),const SizedBox(height:17),Center(child:FilledButton.icon(onPressed:onAddReview,icon:const Icon(Icons.rate_review_outlined),label:const Text('Review a product')))] else ...reviews.map((review)=>Padding(padding:const EdgeInsets.only(bottom:11),child:ReviewCard(review:review,onDelete:()=>onDelete(review)))),
    const SizedBox(height:12),const Text('Your notes help you compare your own experience over time. Results vary from person to person.',style:TextStyle(color:Color(0xFF889189),fontSize:11,height:1.4),textAlign:TextAlign.center),
  ]);
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key,required this.review,required this.onDelete});final ProductReview review;final VoidCallback onDelete;
  @override
  Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(review.product,style:const TextStyle(color:_ink,fontWeight:FontWeight.w700,fontSize:15))),IconButton(onPressed:onDelete,icon:const Icon(Icons.delete_outline,size:19),visualDensity:VisualDensity.compact)]),Row(children:[...List.generate(5,(i)=>Icon(i<review.rating?Icons.star_rounded:Icons.star_outline_rounded,size:18,color:const Color(0xFFE0AC5D))),const SizedBox(width:7),Text(review.date,style:const TextStyle(color:Color(0xFF8A948B),fontSize:11))]),const SizedBox(height:11),Wrap(spacing:7,runSpacing:7,children:[_Tag(review.skinType),if(review.duration.isNotEmpty)_Tag('Used ${review.duration}'),if(review.reaction.isNotEmpty)_Tag(review.reaction)]),if(review.notes.isNotEmpty)...[const SizedBox(height:10),Text(review.notes,style:const TextStyle(color:Color(0xFF59675E),fontSize:12,height:1.4))]])));
}

class _Tag extends StatelessWidget {const _Tag(this.text);final String text;@override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:_sage,borderRadius:BorderRadius.circular(30)),child:Text(text,style:const TextStyle(color:_forest,fontSize:10,fontWeight:FontWeight.w600)));}

void _compareReviews(BuildContext context,List<ProductReview> reviews) {
  showDialog<void>(context:context,builder:(context)=>AlertDialog(title:const Text('Your experience, side by side'),content:SizedBox(width:540,child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(columns:[const DataColumn(label:Text('')), ...reviews.map((r)=>DataColumn(label:SizedBox(width:125,child:Text(r.product,maxLines:2,overflow:TextOverflow.ellipsis))))],rows:[DataRow(cells:[const DataCell(Text('Your rating')), ...reviews.map((r)=>DataCell(Text('★ ${r.rating}/5')))]),DataRow(cells:[const DataCell(Text('Skin type')), ...reviews.map((r)=>DataCell(Text(r.skinType)))]),DataRow(cells:[const DataCell(Text('Time used')), ...reviews.map((r)=>DataCell(Text(r.duration.isEmpty?'—':r.duration)))]),DataRow(cells:[const DataCell(Text('Reaction')), ...reviews.map((r)=>DataCell(Text(r.reaction.isEmpty?'—':r.reaction)))]),]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Done'))]));
}

class ReviewEditor extends StatefulWidget {const ReviewEditor({super.key,this.initialProduct=''});final String initialProduct;@override State<ReviewEditor> createState()=>_ReviewEditorState();}
class _ReviewEditorState extends State<ReviewEditor> {
  late final TextEditingController _product=TextEditingController(text:widget.initialProduct);final _duration=TextEditingController();final _notes=TextEditingController();int _rating=4;String _skin='Combination';String _reaction='Felt good';
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Review a product'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[TextField(controller:_product,decoration:const InputDecoration(labelText:'Product name')),const SizedBox(height:11),const Text('How did it work for you?',style:TextStyle(color:_ink,fontWeight:FontWeight.w600)),Row(children:List.generate(5,(i)=>IconButton(onPressed:()=>setState(()=>_rating=i+1),visualDensity:VisualDensity.compact,icon:Icon(i<_rating?Icons.star_rounded:Icons.star_outline_rounded,color:const Color(0xFFE0AC5D),size:29)))),DropdownButtonFormField<String>(value:_skin,decoration:const InputDecoration(labelText:'My skin type'),items:const['Oily','Dry','Combination','Sensitive','Normal','Not sure'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>_skin=v??'Combination')),const SizedBox(height:10),TextField(controller:_duration,decoration:const InputDecoration(labelText:'How long did you use it?',hintText:'e.g. 3 weeks')),const SizedBox(height:10),DropdownButtonFormField<String>(value:_reaction,decoration:const InputDecoration(labelText:'My experience'),items:const['Felt good','No change yet','Too drying','Irritated my skin','Loved it','Not for me'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>_reaction=v??'Felt good')),const SizedBox(height:10),TextField(controller:_notes,maxLines:3,decoration:const InputDecoration(labelText:'Personal notes',hintText:'Anything you want to remember'))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:(){final product=_product.text.trim();if(product.isEmpty)return;Navigator.pop(context,ProductReview(id:DateTime.now().microsecondsSinceEpoch.toString(),product:product,rating:_rating,skinType:_skin,duration:_duration.text.trim(),reaction:_reaction,notes:_notes.text.trim(),date:DateFormat('d MMM yyyy').format(DateTime.now())));},child:const Text('Save review'))]);
}
