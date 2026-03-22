import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dio/dio.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../providers/issues_provider.dart';
import '../../models/models.dart';

// ─── Priority helpers ─────────────────────────────────────────────────────────
String priorityLabel(double score) {
  if (score >= 0.8) return 'CRITICAL';
  if (score >= 0.6) return 'HIGH';
  if (score >= 0.4) return 'MEDIUM';
  return 'LOW';
}

Color priorityColor(double score) {
  if (score >= 0.8) return const Color(0xFFB71C1C);
  if (score >= 0.6) return const Color(0xFFE65100);
  if (score >= 0.4) return const Color(0xFFF9A825);
  return const Color(0xFF2E7D32);
}

String _timeAgo(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inDays >= 1) return '${diff.inDays}d ago';
  if (diff.inHours >= 1) return '${diff.inHours}h ago';
  return '${diff.inMinutes}m ago';
}

// ─── Mode ─────────────────────────────────────────────────────────────────────
enum SubmissionMode { text, voice, image }

class SubmitIssueScreen extends ConsumerStatefulWidget {
  const SubmitIssueScreen({super.key});

  @override
  ConsumerState<SubmitIssueScreen> createState() => _SubmitIssueScreenState();
}

class _SubmitIssueScreenState extends ConsumerState<SubmitIssueScreen>
    with TickerProviderStateMixin {

  // ── Mode ──────────────────────────────────────────────────────────────────
  SubmissionMode _mode = SubmissionMode.text;

  // ── Text ──────────────────────────────────────────────────────────────────
  final _descCtrl = TextEditingController();

  // ── Voice / STT ───────────────────────────────────────────────────────────
  final SpeechToText _stt   = SpeechToText();
  bool   _sttAvailable      = false;
  bool   _isListening        = false;
  String _spokenText         = '';
  String _partialText        = '';
  bool   _isProcessingVoice  = false;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Image ─────────────────────────────────────────────────────────────────
  File?  _image;
  final  _captionCtrl = TextEditingController();

  // ── Category ──────────────────────────────────────────────────────────────
  String? _category;
  final _categories = const [
    'Infrastructure & Roads', 'Sanitation & Waste', 'Water Supply',
    'Electricity', 'Public Safety', 'Healthcare', 'Education',
    'Transportation', 'Environment', 'Government Services', 'General',
  ];

  // ── Location ──────────────────────────────────────────────────────────────
  double? _lat, _lng;
  String? _state, _city, _town;
  String  _locationText      = 'Tap to detect location';
  bool    _isGettingLocation = false;

  // ── Submit ────────────────────────────────────────────────────────────────
  bool _isLoading = false;

  // ── Similar issues (Task 1) ───────────────────────────────────────────────
  Timer?              _debounce;
  List<SimilarCluster> _similar        = [];
  bool                _checkingDupes   = false;
  bool                _similarDismissed = false;
  bool                _similarExpanded  = false;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initStt();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _descCtrl.addListener(_onDescChanged);
  }

  @override
  void dispose() {
    _descCtrl.removeListener(_onDescChanged);
    _descCtrl.dispose();
    _captionCtrl.dispose();
    _stt.stop();
    _pulseCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ─── STT init ─────────────────────────────────────────────────────────────
  Future<void> _initStt() async {
    final ok = await _stt.initialize(
      onError: (e) => debugPrint('[STT] error: $e'),
    );
    if (mounted) setState(() => _sttAvailable = ok);
  }

  // ─── Similar issue debounce (Task 1) ─────────────────────────────────────
  void _onDescChanged() {
    final text = _descCtrl.text.trim();
    if (text.length < 20 || _lat == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _checkSimilar);
  }

  Future<void> _checkSimilar() async {
    if (_lat == null || _lng == null) return;
    final desc = _mode == SubmissionMode.text
        ? _descCtrl.text.trim()
        : _spokenText.trim();
    if (desc.length < 20) return;

    setState(() { _checkingDupes = true; _similarDismissed = false; });
    try {
      final res = await ApiService.instance.getSimilarIssues(
        description: desc,
        latitude:    _lat!,
        longitude:   _lng!,
        category:    _category,
      );
      final list = (res['similar_clusters'] as List? ?? [])
          .map((e) => SimilarCluster.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => _similar = list);
    } catch (_) {
      // Silent fail — never block submission
    } finally {
      if (mounted) setState(() => _checkingDupes = false);
    }
  }

  Future<void> _supportIssue(SimilarCluster cluster) async {
    try {
      await ApiService.instance.supportIssue(cluster.clusterId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Thanks! Your support has been registered. We\'ll keep you updated.'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 4),
      ));
      context.go('/citizen');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not register support. Please try again.'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ─── Toggle listening ─────────────────────────────────────────────────────
  Future<void> _toggleListening() async {
    if (!_sttAvailable) {
      _snack('Speech recognition not available on this device', error: true);
      return;
    }
    if (_isListening) {
      await _stt.stop();
      setState(() { _isListening = false; _isProcessingVoice = true; });
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() => _isProcessingVoice = false);
      // Re-check similar after voice
      if (_spokenText.trim().length >= 20 && _lat != null) _checkSimilar();
    } else {
      setState(() { _isListening = true; _spokenText = ''; _partialText = ''; });
      await _stt.listen(
        onResult: (r) {
          if (mounted) setState(() {
            if (r.finalResult) {
              _spokenText  = r.recognizedWords;
              _partialText = '';
            } else {
              _partialText = r.recognizedWords;
            }
          });
        },
        listenFor: const Duration(minutes: 2),
        pauseFor:  const Duration(seconds: 4),
        localeId:  'en_IN',
      );
    }
  }

  void _clearVoice() => setState(() {
    _spokenText = _partialText = '';
    _similar    = [];
  });

  // ─── Image picker ─────────────────────────────────────────────────────────
  void _showImageSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
        ListTile(leading: const Icon(Icons.camera_alt),
            title: const Text('Camera'),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); }),
        ListTile(leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); }),
      ])),
    );
  }

  Future<void> _pickImage(ImageSource src) async {
    final f = await ImagePicker().pickImage(source: src, imageQuality: 80);
    if (f != null && mounted) setState(() => _image = File(f.path));
  }

  // ─── Location ─────────────────────────────────────────────────────────────
  Future<void> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _snack('Location permission denied. Please enable in settings.',
            error: true);
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Please enable device location / GPS', error: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final placemarks = await placemarkFromCoordinates(
          pos.latitude, pos.longitude);
      final p = placemarks.isNotEmpty ? placemarks.first : null;
      if (mounted) {
        setState(() {
          _lat  = pos.latitude;
          _lng  = pos.longitude;
          _state = p?.administrativeArea;
          _city  = p?.locality;
          _town  = p?.subLocality;
          _locationText = [
            if (p?.subLocality?.isNotEmpty == true)  p!.subLocality!,
            if (p?.locality?.isNotEmpty == true)      p!.locality!,
            if (p?.administrativeArea?.isNotEmpty == true) p!.administrativeArea!,
          ].join(', ').isNotEmpty
              ? [p?.subLocality, p?.locality, p?.administrativeArea]
                  .whereType<String>().join(', ')
              : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        });
        // Trigger similar check now that we have location
        _onDescChanged();
      }
    } catch (e) {
      if (mounted) _snack('Could not get location. Check GPS signal.', error: true);
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  void _showLocationOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text(
                'Select Location Method',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.my_location, color: AppColors.primary),
              ),
              title: const Text('Use Current Location', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Detects your GPS automatically'),
              onTap: () {
                Navigator.pop(context);
                _getLocation();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.map_outlined, color: AppColors.success),
              ),
              title: const Text('Choose on Map', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Pin point location manually'),
              onTap: () {
                Navigator.pop(context);
                _openMapPicker();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _openMapPicker() async {
    final result = await context.push<Map<String, dynamic>>('/citizen/location_picker');
    if (result != null && mounted) {
      setState(() {
        _lat = result['latitude'];
        _lng = result['longitude'];
        _state = result['state'];
        _city = result['city'];
        _town = result['town'];
        _locationText = result['address'] ?? '$_lat, $_lng';
      });
      _onDescChanged(); // trigger similar detection
    }
  }

  // ─── Submit (Task 2) ──────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_lat == null) {
      _snack('Please detect your location first', error: true);
      return;
    }

    String? description;
    switch (_mode) {
      case SubmissionMode.text:
        if (_descCtrl.text.trim().length < 10) {
          _snack('Description must be at least 10 characters', error: true);
          return;
        }
        description = _descCtrl.text.trim();
      case SubmissionMode.voice:
        if (_spokenText.trim().isEmpty) {
          _snack('Please record your complaint first', error: true);
          return;
        }
        description = _spokenText.trim();
      case SubmissionMode.image:
        if (_image == null) {
          _snack('Please select an image first', error: true);
          return;
        }
        description = _captionCtrl.text.trim().isNotEmpty
            ? _captionCtrl.text.trim()
            : 'Image complaint';
    }

    setState(() => _isLoading = true);
    try {
      final locationJson =
          '{"latitude":$_lat,"longitude":$_lng,'
          '"state":"${_state ?? ""}","city":"${_city ?? ""}","town":"${_town ?? ""}","address":"$_locationText"}';

      final Map<String, dynamic> fields = {
        'description': description,
        'location':    locationJson,
        if (_category != null) 'category': _category,
      };

      if (_mode == SubmissionMode.image && _image != null) {
        fields['image'] = await MultipartFile.fromFile(
          _image!.path, filename: _image!.path.split('/').last,
        );
      }

      final raw = await ApiService.instance.createIssue(FormData.fromMap(fields));
      ref.invalidate(issuesProvider);

      if (!mounted) return;

      // ── Task 2: parse response and show feedback ──────────────────────────
      IssueCreateResponse? resp;
      try {
        if (raw is Map<String, dynamic>) resp = IssueCreateResponse.fromJson(raw);
      } catch (_) {}

      if (resp?.matchStatus != null) {
        await _showSubmitFeedback(resp!);
      } else {
        _snack('Complaint submitted! AI is analyzing…');
        context.pushReplacement('/citizen/issues');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showSubmitFeedback(IssueCreateResponse resp) async {
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubmitFeedbackSheet(response: resp),
    );
    if (mounted) context.pushReplacement('/citizen/issues');
  }

  void _snack(String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ));

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasSimilar = _similar.isNotEmpty && !_similarDismissed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Complaint'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoBanner(),
            const SizedBox(height: 20),
            _modeSwitcher(),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: KeyedSubtree(
                key: ValueKey(_mode),
                child: switch (_mode) {
                  SubmissionMode.text  => _textMode(),
                  SubmissionMode.voice => _voiceMode(),
                  SubmissionMode.image => _imageMode(),
                },
              ),
            ),
            const SizedBox(height: 20),
            _categoryDropdown(),
            const SizedBox(height: 16),
            _locationTile(),

            // ── Task 1: Similar issues card ──────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _checkingDupes
                  ? _SimilarLoadingIndicator()
                  : hasSimilar
                      ? _SimilarIssuesCard(
                          clusters:       _similar,
                          expanded:       _similarExpanded,
                          onExpand:       () => setState(() =>
                              _similarExpanded = !_similarExpanded),
                          onSupport:      (c) => _supportIssue(c),
                          onDismiss:      () => setState(() =>
                              _similarDismissed = true),
                        )
                      : const SizedBox.shrink(),
            ),

            const SizedBox(height: 32),
            _submitButton(),
          ],
        ),
      ),
    );
  }

  // ─── Info banner ──────────────────────────────────────────────────────────
  Widget _infoBanner() {
    const msgs = {
      SubmissionMode.text:  'Describe your complaint — AI will categorize & prioritize it',
      SubmissionMode.voice: 'Speak your complaint — it will be auto-transcribed',
      SubmissionMode.image: 'Photo your issue — AI will analyze and categorize it',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.infoLight, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.auto_awesome, color: AppColors.info, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msgs[_mode]!,
            style: const TextStyle(fontSize: 13, color: AppColors.info))),
      ]),
    );
  }

  // ─── Mode switcher ────────────────────────────────────────────────────────
  Widget _modeSwitcher() => Container(
    decoration: BoxDecoration(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderColor),
    ),
    padding: const EdgeInsets.all(4),
    child: Row(children: SubmissionMode.values.map(_modeTab).toList()),
  );

  Widget _modeTab(SubmissionMode m) {
    final sel = _mode == m;
    const data = {
      SubmissionMode.text:  ('Text',  Icons.text_fields_rounded),
      SubmissionMode.voice: ('Voice', Icons.mic_rounded),
      SubmissionMode.image: ('Image', Icons.image_rounded),
    };
    final (label, icon) = data[m]!;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _mode = m; _similar = []; _similarDismissed = false; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16,
                color: sel ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }

  // ─── Text mode ────────────────────────────────────────────────────────────
  Widget _textMode() => TextFormField(
    controller: _descCtrl,
    maxLines: 5,
    decoration: const InputDecoration(
      labelText: 'Describe your complaint *',
      prefixIcon: Icon(Icons.description_outlined),
      hintText: 'Explain the issue in detail…',
      alignLabelWithHint: true,
    ),
  );

  // ─── Voice mode ───────────────────────────────────────────────────────────
  Widget _voiceMode() {
    final hasText = _spokenText.isNotEmpty;
    final liveText = _isListening ? _partialText : '';
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: _isListening
              ? AppColors.error.withOpacity(0.06)
              : AppColors.inputFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isListening
                ? AppColors.error.withOpacity(0.5)
                : AppColors.borderColor,
          ),
        ),
        child: Column(children: [
          GestureDetector(
            onTap: _toggleListening,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                scale: _isListening ? _pulseAnim.value : 1.0,
                child: child,
              ),
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? AppColors.error : AppColors.primary,
                  boxShadow: [BoxShadow(
                    color: (_isListening ? AppColors.error : AppColors.primary)
                        .withOpacity(0.3),
                    blurRadius: 20, spreadRadius: 4,
                  )],
                ),
                child: Icon(
                  _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white, size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isListening ? 'Listening… tap to stop'
                : hasText  ? 'Transcription complete ✓'
                           : 'Tap mic to speak your complaint',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                color: _isListening ? AppColors.error : AppColors.textSecondary),
          ),
          if (_isListening && liveText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(liveText, style: const TextStyle(fontSize: 13,
                color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center),
          ],
          if (hasText) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderColor)),
              child: Text(_spokenText, style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                onPressed: _clearVoice,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Re-record'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    textStyle: const TextStyle(fontSize: 13)),
              ),
            ]),
          ],
        ]),
      ),
      if (!hasText)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'Your speech will be silently converted to text and submitted as the complaint description.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
    ]);
  }

  // ─── Image mode ───────────────────────────────────────────────────────────
  Widget _imageMode() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GestureDetector(
        onTap: _showImageSheet,
        child: Container(
          width: double.infinity, height: 200,
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _image != null ? AppColors.primary : AppColors.borderColor,
              width: _image != null ? 2 : 1,
            ),
          ),
          child: _image != null
              ? Stack(fit: StackFit.expand, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(15),
                      child: Image.file(_image!, fit: BoxFit.cover)),
                  Positioned(top: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _image = null),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 10),
                  Text('Tap to add photo',
                      style: TextStyle(color: AppColors.textSecondary,
                          fontSize: 14)),
                  SizedBox(height: 4),
                  Text('Camera or Gallery',
                      style: TextStyle(color: AppColors.textSecondary,
                          fontSize: 12)),
                ]),
        ),
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _captionCtrl,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Caption (optional)',
          prefixIcon: Icon(Icons.short_text),
          hintText: 'Brief note about this photo…',
        ),
      ),
    ],
  );

  // ─── Category ─────────────────────────────────────────────────────────────
  Widget _categoryDropdown() => DropdownButtonFormField<String>(
    value: _category,
    decoration: const InputDecoration(
      labelText: 'Category (optional – AI will suggest)',
      prefixIcon: Icon(Icons.category_outlined),
    ),
    items: _categories
        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
        .toList(),
    onChanged: (v) => setState(() => _category = v),
  );

  // ─── Location tile ────────────────────────────────────────────────────────
  Widget _locationTile() => GestureDetector(
    onTap: _isGettingLocation ? null : _showLocationOptions,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _lat != null ? AppColors.successLight : AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _lat != null ? AppColors.success : AppColors.borderColor),
      ),
      child: Row(children: [
        Icon(Icons.location_on_outlined,
            color: _lat != null ? AppColors.success : AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_locationText, style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _lat != null
                    ? AppColors.success : AppColors.textSecondary)),
            if (_lat != null && (_state != null || _city != null))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  [if (_town  != null) _town!,
                   if (_city  != null) _city!,
                   if (_state != null) _state!].join(' • '),
                  style: const TextStyle(fontSize: 11,
                      color: AppColors.textSecondary),
                ),
              ),
          ],
        )),
        if (_isGettingLocation)
          const SizedBox(height: 18, width: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(_lat != null ? Icons.check_circle : Icons.my_location,
              color: _lat != null ? AppColors.success : AppColors.primary,
              size: 20),
      ]),
    ),
  );

  // ─── Submit button ────────────────────────────────────────────────────────
  Widget _submitButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: _isLoading ? null : _submit,
      icon: _isLoading
          ? const SizedBox(height: 18, width: 18,
              child: CircularProgressIndicator(strokeWidth: 2,
                  color: Colors.white))
          : const Icon(Icons.send_outlined),
      label: Text(_isLoading ? 'Submitting…' : 'Submit Complaint'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Task 1 — Similar Issues Card
// ─────────────────────────────────────────────────────────────────────────────
class _SimilarLoadingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(children: [
      const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
      const SizedBox(width: 10),
      Text('Checking for similar reports nearby…',
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]),
  );
}

class _SimilarIssuesCard extends StatelessWidget {
  final List<SimilarCluster> clusters;
  final bool expanded;
  final VoidCallback onExpand;
  final ValueChanged<SimilarCluster> onSupport;
  final VoidCallback onDismiss;

  const _SimilarIssuesCard({
    required this.clusters,
    required this.expanded,
    required this.onExpand,
    required this.onSupport,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final primary    = clusters.first;
    final extras     = clusters.length - 1;
    final simPct     = (primary.similarityScore * 100).round();
    final priColor   = priorityColor(primary.priorityScore);
    final priLabel   = priorityLabel(primary.priorityScore);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.5),
              width: 1.5),
          boxShadow: [BoxShadow(
            color: const Color(0xFFFFB300).withOpacity(0.1),
            blurRadius: 12, offset: const Offset(0, 3),
          )],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFFFEE58),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              const Text('⚠️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              const Expanded(child: Text(
                'Similar issue already reported nearby',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                    color: Color(0xFF5D4037)),
              )),
              GestureDetector(
                onTap: onDismiss,
                child: const Icon(Icons.close, size: 18,
                    color: Color(0xFF795548)),
              ),
            ]),
          ),

          // ── Primary cluster ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Title
              Text('"${primary.normalizedTitle}"',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),

              // Meta chips
              Wrap(spacing: 8, runSpacing: 6, children: [
                _chip(Icons.group_rounded,
                    '${primary.complaintCount} complaints',
                    const Color(0xFF5D4037)),
                _chip(Icons.local_fire_department_rounded,
                    'Priority: $priLabel', priColor),
                if (primary.lastReportedAt != null)
                  _chip(Icons.schedule_rounded,
                      _timeAgo(primary.lastReportedAt),
                      const Color(0xFF5D4037)),
                _chip(Icons.percent_rounded,
                    '$simPct% match', AppColors.info),
              ]),
            ]),
          ),

          // ── Extra clusters (expandable) ──────────────────────────────────
          if (extras > 0) ...[
            GestureDetector(
              onTap: onExpand,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('and $extras more similar report${extras > 1 ? "s" : ""}',
                        style: const TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning)),
                  ),
                  const SizedBox(width: 4),
                  Icon(expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                      size: 18, color: AppColors.warning),
                ]),
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 8),
              ...clusters.skip(1).map((c) => Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderColor),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(c.normalizedTitle, style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('${c.complaintCount} reports  •  '
                          '${(c.similarityScore * 100).round()}% match',
                          style: const TextStyle(fontSize: 11,
                              color: AppColors.textSecondary)),
                    ])),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => onSupport(c),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          textStyle: const TextStyle(fontSize: 11)),
                      child: const Text('Support'),
                    ),
                  ]),
                ),
              )),
            ],
          ],

          // ── Action buttons ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: () => onSupport(primary),
                icon: const Text('👍', style: TextStyle(fontSize: 14)),
                label: const Text('Support this issue',
                    style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(
                onPressed: onDismiss,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: AppColors.primary),
                  foregroundColor: AppColors.primary,
                ),
                child: const Text('Report separately →',
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Task 2 — Post-Submit Feedback Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _SubmitFeedbackSheet extends StatelessWidget {
  final IssueCreateResponse response;
  const _SubmitFeedbackSheet({required this.response});

  @override
  Widget build(BuildContext context) {
    final status   = response.matchStatus ?? 'new_cluster';
    final priColor = priorityColor(response.priorityScore);
    final priLabel = priorityLabel(response.priorityScore);

    final config = switch (status) {
      'auto_merged' => (
          emoji:   '✅',
          title:   'Added to existing cluster',
          color:   AppColors.success,
          bgColor: AppColors.successLight,
          lines:   [
            'Your complaint has been merged with an existing report.',
            'The assigned leader has already been notified.',
          ],
        ),
      'pending_review' => (
          emoji:   '🕐',
          title:   'Your complaint is under review',
          color:   AppColors.warning,
          bgColor: const Color(0xFFFFFDE7),
          lines:   [
            'It closely matches an existing nearby report.',
            'A senior authority will verify and merge it shortly.',
          ],
        ),
      _ => (
          emoji:   '📋',
          title:   'New issue registered!',
          color:   AppColors.primary,
          bgColor: AppColors.infoLight,
          lines:   [
            'You\'re the first to report this in your area.',
            'A local leader has been assigned to resolve it.',
          ],
        ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 24),

        // ── Status icon + title ────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: config.bgColor,
              shape: BoxShape.circle,
              border: Border.all(color: config.color.withOpacity(0.3),
                  width: 2),
            ),
            child: Center(child: Text(config.emoji,
                style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(config.title, style: TextStyle(fontSize: 17,
                fontWeight: FontWeight.w800, color: config.color)),
            const SizedBox(height: 4),
            ...config.lines.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l, style: const TextStyle(fontSize: 13,
                  color: AppColors.textSecondary, height: 1.4)),
            )),
          ])),
        ]),
        const SizedBox(height: 20),

        // ── Meta info ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: Column(children: [
            _row('Category', response.category,
                Icons.category_outlined, AppColors.textSecondary),
            const Divider(height: 16, color: AppColors.borderColor),
            Row(children: [
              const Icon(Icons.local_fire_department_rounded,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text('Priority',
                  style: TextStyle(fontSize: 13,
                      color: AppColors.textSecondary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: priColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: priColor.withOpacity(0.4)),
                ),
                child: Text(priLabel,
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w800, color: priColor)),
              ),
            ]),
            if (response.clusterId != null) ...[
              const Divider(height: 16, color: AppColors.borderColor),
              _row('Cluster ID',
                  response.clusterId!.substring(0,
                      response.clusterId!.length.clamp(0, 8)) + '…',
                  Icons.hub_outlined, AppColors.textSecondary),
            ],
          ]),
        ),
        const SizedBox(height: 24),

        // ── Done button ──────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: config.color,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
            child: const Text('View My Issues →'),
          ),
        ),
      ]),
    );
  }

  Widget _row(String label, String value, IconData icon, Color color) =>
      Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13,
            color: AppColors.textSecondary)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]);
}