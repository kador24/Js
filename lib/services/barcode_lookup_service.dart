import 'dart:convert';
import 'package:http/http.dart' as http;

class BarcodeLookupSuggestion {
  final String? name;
  final String? brand;
  final String? description;
  const BarcodeLookupSuggestion({this.name, this.brand, this.description});
}

class BarcodeLookupService {
  static const _userAgent = 'JamalPhoneManager/1.1.1 (offline-first shop manager)';

  Future<BarcodeLookupSuggestion?> lookup(String barcode) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    try {
      final uri = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$clean.json');
      final response = await http.get(uri, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map || data['status'] != 1) return null;
      final p = data['product'];
      if (p is! Map) return null;
      final name = (p['product_name'] ?? p['product_name_ar'] ?? '').toString().trim();
      final brand = (p['brands'] ?? '').toString().trim();
      final description = (p['generic_name'] ?? '').toString().trim();
      if (name.isEmpty && brand.isEmpty) return null;
      return BarcodeLookupSuggestion(
        name: name.isEmpty ? null : name,
        brand: brand.isEmpty ? null : brand,
        description: description.isEmpty ? null : description,
      );
    } catch (_) {
      return null;
    }
  }
}
