import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';
import '../../providers/issues_provider.dart';

class SubmitIssueScreen extends ConsumerStatefulWidget {
  const SubmitIssueScreen({super.key});

  @override
  ConsumerState<SubmitIssueScreen> createState() => _SubmitIssueScreenState();
}

class _SubmitIssueScreenState extends ConsumerState<SubmitIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _category;
  List<File> _images = [];
  double? _lat, _lng;
  String _locationText = 'Tap to get location';
  bool _isLoading = false;
  bool _isGettingLocation = false;

  final _categories = [
    'Roads & Infrastructure', 'Water Supply', 'Electricity', 'Sanitation',
    'Public Safety', 'Environment', 'Healthcare', 'Education', 'General'
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition();
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _locationText = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (e) {
      // Fallback coords for demo
      setState(() {
        _lat = 26.8467; _lng = 80.9462;
        _locationText = 'Lucknow, UP (demo)';
      });
    } finally {
      setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 80);
    if (files.isNotEmpty) {
      setState(() => _images = files.map((f) => File(f.path)).toList());
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please get your location first')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final formData = FormData.fromMap({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'location': '{"latitude": $_lat, "longitude": $_lng, "address": "$_locationText"}',
        if (_category != null) 'category': _category,
        'images': [
          for (final img in _images)
            await MultipartFile.fromFile(img.path,
                filename: img.path.split('/').last)
        ],
      });

      await ApiService.instance.createIssue(formData);
      ref.invalidate(issuesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Issue reported successfully! AI is analyzing...'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/citizen/issues');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Issue'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/citizen'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: AppColors.info, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI will automatically categorize and prioritize your issue',
                        style: TextStyle(fontSize: 13, color: AppColors.info),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Title
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Issue Title *',
                  prefixIcon: Icon(Icons.title),
                  hintText: 'Brief description of the problem',
                ),
                validator: (v) => v == null || v.length < 5 ? 'Min 5 characters' : null,
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Detailed Description *',
                  prefixIcon: Icon(Icons.description_outlined),
                  hintText: 'Describe the issue in detail...',
                  alignLabelWithHint: true,
                ),
                validator: (v) => v == null || v.length < 10 ? 'Min 10 characters' : null,
              ),
              const SizedBox(height: 16),

              // Category
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Category (optional – AI will suggest)',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 16),

              // Location
              GestureDetector(
                onTap: _getLocation,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _lat != null ? AppColors.successLight : AppColors.inputFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _lat != null ? AppColors.success : AppColors.borderColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: _lat != null ? AppColors.success : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _locationText,
                          style: TextStyle(
                            color: _lat != null ? AppColors.success : AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (_isGettingLocation)
                        const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _lat != null ? Icons.check_circle : Icons.my_location,
                          color: _lat != null ? AppColors.success : AppColors.primary,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Images
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Photos (optional)',
                      style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  if (_images.isNotEmpty)
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(_images[i], width: 100, height: 100, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(_images.isEmpty ? 'Add Photos' : 'Change Photos'),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submit,
                  icon: _isLoading
                      ? const SizedBox(height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_outlined),
                  label: const Text('Submit Issue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}