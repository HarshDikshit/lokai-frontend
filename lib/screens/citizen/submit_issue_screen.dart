import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dio/dio.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../providers/issues_provider.dart';

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
  final _stt                    = SpeechToText();
  bool   _sttAvailable          = false;
  bool   _isListening           = false;
  String _spokenText            = '';          // final transcription
  String _partialText           = '';          // live interim words
  bool   _isProcessingVoice     = false;       // silently processing after stop
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
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _captionCtrl.dispose();
    _stt.stop();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─── STT init ─────────────────────────────────────────────────────────────
  Future<void> _initStt() async {
    final ok = await _stt.initialize(
      onError: (e) => debugPrint('[STT] error: $e'),
    );
    if (mounted) setState(() => _sttAvailable = ok);
  }

  // ─── Toggle listening ─────────────────────────────────────────────────────
  Future<void> _toggleListening() async {
    if (!_sttAvailable) {
      _snack('Speech recognition not available on this device', error: true);
      return;
    }

    if (_isListening) {
      // ── Stop: STT finalizes → _isProcessingVoice briefly true (hidden from user)
      await _stt.stop();
      setState(() {
        _isListening       = false;
        _isProcessingVoice = true;   // internal — no UI spinner shown
      });
      // Give STT ~400ms to deliver final result, then mark done
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() => _isProcessingVoice = false);
    } else {
      // ── Start
      setState(() {
        _spokenText  = '';
        _partialText = '';
      });
      await _stt.listen(
        onResult: (result) {
          setState(() {
            _partialText = result.recognizedWords;
            if (result.finalResult) {
              _spokenText  = result.recognizedWords;
              _partialText = '';
              _isListening = false;
            }
          });
        },
        listenFor: const Duration(minutes: 2),
        pauseFor:  const Duration(seconds: 4),   // auto-stop after 4s silence
        localeId:  'en_IN',                       // Indian English
        cancelOnError: true,
      );
      setState(() => _isListening = true);
    }
  }

  void _clearVoice() => setState(() {
    _spokenText  = '';
    _partialText = '';
  });

  // ─── Location ─────────────────────────────────────────────────────────────
  Future<void> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      // 1. Check / request permission
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _snack('Location permission permanently denied — enable in Settings', error: true);
        return;
      }

      // 2. Make sure location service is on
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _snack('Please enable device location / GPS', error: true);
        return;
      }

      // 3. Get position — use lower accuracy first for speed, then high if needed
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (_) {
        // Fallback: last known position
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) {
          _snack('Could not get location. Check GPS signal.', error: true);
          return;
        }
        pos = last;
      }

      _lat = pos.latitude;
      _lng = pos.longitude;

      // 4. Reverse geocode
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          _state = p.administrativeArea;
          _city  = p.locality;
          _town  = (p.subLocality?.isNotEmpty == true)
              ? p.subLocality
              : p.subAdministrativeArea;
          _locationText = [_town, _city, _state]
              .where((v) => v != null && v!.isNotEmpty)
              .join(', ');
        }
      } catch (_) {
        // Geocoding failed — coords are still valid, just no address text
        _locationText =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      }
    } catch (e) {
      _snack('Location error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  // ─── Image ────────────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource src) async {
    final f = await ImagePicker().pickImage(source: src, imageQuality: 80);
    if (f != null) setState(() => _image = File(f.path));
  }

  void _showImageSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('Select Source',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.camera_alt_outlined)),
            title: const Text('Camera'),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
          ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.photo_library_outlined)),
            title: const Text('Gallery'),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ─── Submit ───────────────────────────────────────────────────────────────
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
        // Transcribed text goes directly into description — no audio file sent
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

      await ApiService.instance.createIssue(FormData.fromMap(fields));
      ref.invalidate(issuesProvider);

      if (!mounted) return;
      _snack('Complaint submitted! AI is analyzing…');
      context.go('/citizen/issues');
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ));

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Complaint'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/citizen'),
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
  Widget _modeSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(children: SubmissionMode.values.map(_modeTab).toList()),
    );
  }

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
        onTap: () => setState(() => _mode = m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: sel ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: sel ? Colors.white : AppColors.textSecondary,
            )),
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
          // Mic button with pulse while listening
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

          // Status label
          Text(
            _isListening
                ? 'Listening… tap to stop'
                : hasText
                    ? 'Transcription complete ✓'
                    : 'Tap mic to speak your complaint',
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500,
              color: _isListening ? AppColors.error : AppColors.textSecondary,
            ),
          ),

          // Live partial text while speaking (subtle)
          if (_isListening && liveText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(liveText,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],

          // Final transcribed text box
          if (hasText) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: Text(_spokenText,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(_image!, fit: BoxFit.cover),
                  ),
                  Positioned(top: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _image = null),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 10),
                  Text('Tap to add photo',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  SizedBox(height: 4),
                  Text('Camera or Gallery',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
    onTap: _isGettingLocation ? null : _getLocation,
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
            Text(_locationText, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500,
              color: _lat != null ? AppColors.success : AppColors.textSecondary,
            )),
            if (_lat != null && (_state != null || _city != null))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  [if (_town != null) _town!, if (_city != null) _city!, if (_state != null) _state!].join(' • '),
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.send_outlined),
      label: Text(_isLoading ? 'Submitting…' : 'Submit Complaint'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}