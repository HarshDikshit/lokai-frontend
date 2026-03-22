import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';

class LocationPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  late LatLng _currentCenter;
  
  bool _isDragging = false;
  bool _isLoadingAddress = false;
  
  String? _state;
  String? _city;
  String? _town;
  String? _readableAddress;
  Timer? _debounceTimer;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  bool _isSuggesting = false;
  List<Map<String, dynamic>> _suggestions = [];

  @override
  void initState() {
    super.initState();
    // Default to a central location if none provided (e.g. New Delhi)
    _currentCenter = widget.initialLat != null && widget.initialLng != null
        ? LatLng(widget.initialLat!, widget.initialLng!)
        : const LatLng(28.6139, 77.2090); 

    _fetchAddress(_currentCenter);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapPosition position, bool hasGesture) {
    if (position.center != null) {
      if (!_isDragging) {
        setState(() => _isDragging = true);
      }
      _currentCenter = position.center!;
      
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _isDragging = false;
            _isLoadingAddress = true;
          });
          _fetchAddress(_currentCenter);
        }
      });
    }
  }

  Future<void> _fetchAddress(LatLng pos) async {
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        if (mounted) {
          setState(() {
            _state = p.administrativeArea;
            _city = p.locality;
            _town = p.subLocality;
            
            final parts = [p.subLocality, p.locality, p.administrativeArea]
                .where((s) => s != null && s.isNotEmpty)
                .toList();
            
            _readableAddress = parts.isNotEmpty 
                ? parts.join(', ') 
                : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
            _isLoadingAddress = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _readableAddress = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
          _isLoadingAddress = false;
        });
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    FocusScope.of(context).unfocus();
    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        final newPos = LatLng(loc.latitude, loc.longitude);
        _mapController.move(newPos, 14.0);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location not found')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not find location: $query')));
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    // Separate shorter debounce for typing suggestions
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _isSuggesting = true);
    try {
      final dio = Dio();
      final response = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'jsonv2',
          'limit': 5,
          'addressdetails': 1,
        },
        options: Options(
          headers: {'User-Agent': 'LokAI/1.0.0'},
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (response.statusCode == 200 && response.data is List) {
        if (mounted) {
          setState(() {
            _suggestions = List<Map<String, dynamic>>.from(response.data);
          });
        }
      }
    } catch (_) {
      // ignore silently to not disrupt UX on brief network drops
    } finally {
      if (mounted) setState(() => _isSuggesting = false);
    }
  }

  void _onSuggestionTap(Map<String, dynamic> sug) {
    FocusScope.of(context).unfocus();
    final lat = double.tryParse(sug['lat']?.toString() ?? '');
    final lon = double.tryParse(sug['lon']?.toString() ?? '');
    if (lat != null && lon != null) {
      final newPos = LatLng(lat, lon);
      _mapController.move(newPos, 14.0);
      setState(() {
         _searchController.text = sug['name'] ?? sug['display_name'] ?? '';
         _suggestions = [];
      });
    }
  }

  void _confirmLocation() {
    // Return all data via pop
    context.pop({
      'latitude': _currentCenter.latitude,
      'longitude': _currentCenter.longitude,
      'state': _state,
      'city': _city,
      'town': _town,
      'address': _readableAddress,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Location', style: TextStyle(fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          // ─── Map ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 15.0,
              onPositionChanged: _onPositionChanged,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.lokai.app',
                maxZoom: 19,
              ),
            ],
          ),

          // ─── Center Pin ───────────────────────────────────────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40.0), // visual offset for the pin
              child: AnimatedScale(
                scale: _isDragging ? 1.2 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(
                  Icons.location_pin,
                  color: AppColors.error,
                  size: 46,
                ),
              ),
            ),
          ),

          // ─── Bottom Panel ─────────────────────────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.place, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Selected Location',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textHint,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (_isLoadingAddress)
                              const Text('Fetching address...', style: TextStyle(fontSize: 14, color: AppColors.textSecondary))
                            else if (_readableAddress != null)
                              Text(
                                _readableAddress!,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: (_isDragging || _isLoadingAddress) ? null : _confirmLocation,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Confirm Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),

          // ─── Search Bar ───────────────────────────────────────────────────
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _searchLocation,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search city, town, or state...',
                      prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                      suffixIcon: _isSearching || _isSuggesting
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _suggestions = []);
                                FocusScope.of(context).unfocus();
                              },
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderColor),
                      itemBuilder: (context, index) {
                        final sug = _suggestions[index];
                        final title = sug['name'] ?? 'Unknown';
                        final subtitle = sug['display_name'] ?? '';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: const Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: subtitle.isNotEmpty && subtitle != title 
                              ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, 
                                     style: const TextStyle(fontSize: 11, color: AppColors.textHint)) 
                              : null,
                          onTap: () => _onSuggestionTap(sug),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
