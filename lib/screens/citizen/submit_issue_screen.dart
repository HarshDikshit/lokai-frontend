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
import '../../core/localization.dart';

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

// ─── Mode ─────────────────────────────────────────────────────────────────────
enum SubmissionMode { text, voice, image }

class SubmitIssueScreen extends ConsumerStatefulWidget {
  const SubmitIssueScreen({super.key});

  @override
  ConsumerState<SubmitIssueScreen> createState() => _SubmitIssueScreenState();
}

class _SubmitIssueScreenState extends ConsumerState<SubmitIssueScreen>
    with TickerProviderStateMixin {

  SubmissionMode _mode = SubmissionMode.text;
  final _descCtrl = TextEditingController();
  final SpeechToText _stt = SpeechToText();
  bool _sttAvailable = false;
  bool _isListening = false;
  String _spokenText = '';
  String _partialText = '';
  bool _isProcessingVoice = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  File? _image;
  final _captionCtrl = TextEditingController();

  String? _category;
  Map<String, String> get _categoriesMap => {
    'Infrastructure & Roads': context.translate('cat_infra'),
    'Sanitation & Waste': context.translate('cat_sanitation'),
    'Water Supply': context.translate('cat_water'),
    'Electricity': context.translate('cat_electricity'),
    'Public Safety': context.translate('cat_safety'),
    'Healthcare': context.translate('cat_health'),
    'Education': context.translate('cat_edu'),
    'Transportation': context.translate('cat_transp'),
    'Environment': context.translate('cat_env'),
    'Government Services': context.translate('cat_gov'),
    'General': context.translate('cat_gen'),
  };

  double? _lat, _lng;
  String? _state, _city, _town;
  String _locationText = 'Tap to detect location';
  bool _isGettingLocation = false;
  bool _isLoading = false;

  // ── Duplicate Detection (Implicit) ────────────────────────────────────────
  bool _checkingDupes = false;

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
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _captionCtrl.dispose();
    _stt.stop();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _initStt() async {
    final ok = await _stt.initialize(
      onError: (e) => debugPrint('[STT] error: $e'),
    );
    if (mounted) setState(() => _sttAvailable = ok);
  }

  String _getLocString(String key) => context.translate(key);

  Future<void> _toggleListening() async {
    if (!_sttAvailable) {
      _snack('Speech recognition not available', error: true);
      return;
    }
    if (_isListening) {
      await _stt.stop();
      setState(() { _isListening = false; _isProcessingVoice = true; });
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() => _isProcessingVoice = false);
    } else {
      setState(() { _isListening = true; _spokenText = ''; _partialText = ''; });
      await _stt.listen(
        onResult: (r) {
          if (mounted) setState(() {
            if (r.finalResult) {
              _spokenText = r.recognizedWords;
              _partialText = '';
            } else {
              _partialText = r.recognizedWords;
            }
          });
        },
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 4),
        localeId: Localizations.localeOf(context).languageCode == 'hi' ? 'hi_IN' : 'en_IN',
      );
    }
  }

  void _clearVoice() => setState(() {
    _spokenText = _partialText = '';
  });

  void _showImageSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: Text(_getLocString('camera')),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); }),
        ListTile(leading: const Icon(Icons.photo_library), title: Text(_getLocString('gallery')),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); }),
      ])),
    );
  }

  Future<void> _pickImage(ImageSource src) async {
    final f = await ImagePicker().pickImage(source: src, imageQuality: 80);
    if (f != null && mounted) setState(() => _image = File(f.path));
  }

  Future<void> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Please enable GPS', error: true); return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final p = placemarks.isNotEmpty ? placemarks.first : null;
      if (mounted) {
        setState(() {
          _lat = pos.latitude; _lng = pos.longitude;
          _state = p?.administrativeArea; _city = p?.locality; _town = p?.subLocality;
          _locationText = [p?.subLocality, p?.locality].whereType<String>().join(', ');
        });
      }
    } catch (_) {
      if (mounted) _snack('Location error', error: true);
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  void _showLocationOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.my_location), title: Text(_getLocString('use_current_location')),
            onTap: () { Navigator.pop(context); _getLocation(); }),
        ListTile(leading: const Icon(Icons.map_outlined), title: Text(_getLocString('choose_on_map')),
            onTap: () { Navigator.pop(context); _openMapPicker(); }),
      ])),
    );
  }

  Future<void> _openMapPicker() async {
    final result = await context.push<Map<String, dynamic>>('/citizen/location_picker');
    if (result != null && mounted) {
      setState(() {
        _lat = result['latitude']; _lng = result['longitude'];
        _state = result['state']; _city = result['city']; _town = result['town'];
        _locationText = result['address'] ?? '$_lat, $_lng';
      });
    }
  }

  Future<void> _submit() async {
    if (_lat == null) { _snack('Location required', error: true); return; }

    String description = '';
    if (_mode == SubmissionMode.text) description = _descCtrl.text.trim();
    else if (_mode == SubmissionMode.voice) description = _spokenText.trim();
    else description = _captionCtrl.text.trim().isNotEmpty ? _captionCtrl.text.trim() : 'Image complaint';

    if (description.length < 10) { _snack('Description too short', error: true); return; }

    setState(() => _isLoading = true);
    try {
      // ── Simple Duplicate Check ─────────────────────────────────────────────
      final dupeRes = await ApiService.instance.checkDuplicate(
        description: description,
        city: _city ?? '',
        town: _town ?? '',
      );

      if (dupeRes['is_duplicate'] == true) {
        setState(() => _isLoading = false);
        final proceed = await _showDuplicateDialog(dupeRes['existing_issue']);
        if (proceed != true) return;
        setState(() => _isLoading = true);
      }

      final loc = '{"latitude":$_lat,"longitude":$_lng,"state":"${_state??""}","city":"${_city??""}","town":"${_town??""}","address":"$_locationText"}';
      final Map<String, dynamic> fields = {
        'description': description,
        'location': loc,
        if (_category != null) 'category': _category
      };
      if (_mode == SubmissionMode.image && _image != null) {
        fields['image'] = await MultipartFile.fromFile(_image!.path);
      }

      final raw = await ApiService.instance.createIssue(FormData.fromMap(fields));
      ref.invalidate(issuesProvider);

      if (!mounted) return;
      IssueCreateResponse? resp;
      try { if (raw is Map<String, dynamic>) resp = IssueCreateResponse.fromJson(raw); } catch (_) {}

      if (resp?.matchStatus != null) {
        await _showSubmitFeedback(resp!);
      } else {
        _snack(_getLocString('complaint_submitted'));
        context.pushReplacement('/citizen/issues');
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool?> _showDuplicateDialog(Map<String, dynamic>? issue) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.translate('similar_issue_found')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.translate('similar_issue_desc')),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(8)),
            child: Text(issue?['description'] ?? '', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic), maxLines: 4, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 16),
          Text(context.translate('submit_anyway_ask')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.translate('no_go_back'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.translate('yes_submit_anyway'))),
        ],
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? AppColors.error : AppColors.success));

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/citizen');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.white),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/citizen');
              }
            },
          ),
          title: Text(_getLocString('report_complaint')),
          actions: [
            IconButton(
              onPressed: () {
                final currentLocale = ref.read(localeProvider);
                ref.read(localeProvider.notifier).setLocale(currentLocale.languageCode == 'en' 
                        ? const Locale('hi') 
                        : const Locale('en'));
              },
              icon: const Icon(Icons.language),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _modeSwitcher(),
            const SizedBox(height: 24),
            _modeView(),
            const SizedBox(height: 20),
            _categoryDropdown(),
            const SizedBox(height: 16),
            _locationTile(),
            const SizedBox(height: 32),
            _submitButton(),
          ]),
        ),
      ),
    );
  }

  Widget _modeView() {
    return switch (_mode) {
      SubmissionMode.text => TextFormField(controller: _descCtrl, maxLines: 5, decoration: InputDecoration(labelText: '${_getLocString('description_label')}*', hintText: _getLocString('explain_issue'))),
      SubmissionMode.voice => _voiceMode(),
      SubmissionMode.image => _imageMode(),
    };
  }

  Widget _voiceMode() {
    return Center(
      child: Column(children: [
        GestureDetector(
          onTap: _toggleListening,
          child: Container(
            width: 80, height: 80,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _isListening ? AppColors.error : AppColors.primary),
            child: Icon(_isListening ? Icons.stop : Icons.mic, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 16),
        Text(_isListening ? _getLocString('listening') : _spokenText.isNotEmpty ? _getLocString('transcribed') : _getLocString('tap_to_speak')),
        if (_spokenText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_spokenText, textAlign: TextAlign.center)),
      ]),
    );
  }

  Widget _imageMode() => Column(children: [
    GestureDetector(
      onTap: _showImageSheet,
      child: Container(
        width: double.infinity, height: 200,
        decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(16)),
        child: _image != null ? Image.file(_image!, fit: BoxFit.cover) : const Icon(Icons.add_a_photo, size: 48),
      ),
    ),
    const SizedBox(height: 10),
    TextFormField(controller: _captionCtrl, decoration: InputDecoration(labelText: _getLocString('caption_optional'))),
  ]);

  Widget _modeSwitcher() => SegmentedButton<SubmissionMode>(
    segments: [
      ButtonSegment(value: SubmissionMode.text, label: Text(_getLocString('manual')), icon: const Icon(Icons.text_fields)), // Using 'manual' for text for now or add new string
      ButtonSegment(value: SubmissionMode.voice, label: Text(context.translate('mode_voice')), icon: const Icon(Icons.mic)),
      ButtonSegment(value: SubmissionMode.image, label: Text(context.translate('mode_image')), icon: const Icon(Icons.image)),
    ],
    selected: {_mode},
    onSelectionChanged: (s) => setState(() => _mode = s.first),
  );

  Widget _categoryDropdown() => DropdownButtonFormField<String>(
    value: _category,
    decoration: InputDecoration(labelText: _getLocString('category')),
    items: _categoriesMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
    onChanged: (v) => setState(() => _category = v),
  );

  Widget _locationTile() => ListTile(
    tileColor: _lat != null ? AppColors.successLight : AppColors.inputFill,
    leading: const Icon(Icons.location_on),
    title: Text(_locationText),
    trailing: const Icon(Icons.my_location),
    onTap: _showLocationOptions,
  );

  Widget _submitButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _isLoading ? null : _submit,
      child: Text(_isLoading ? _getLocString('submitting') : _getLocString('submit_complaint')),
    ),
  );
}

class _SubmitFeedbackSheet extends StatelessWidget {
  final IssueCreateResponse response;
  const _SubmitFeedbackSheet({required this.response});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 64),
        const SizedBox(height: 16),
        Text(response.message, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: () => Navigator.pop(context), child: Text(context.translate('close'))),
      ]),
    );
  }
}
