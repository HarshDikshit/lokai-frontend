import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import '../../core/app_theme.dart';
import '../../services/api_service.dart';

class UploadVerificationScreen extends ConsumerStatefulWidget {
  final String taskId;
  const UploadVerificationScreen({super.key, required this.taskId});

  @override
  ConsumerState<UploadVerificationScreen> createState() => _UploadVerificationScreenState();
}

class _UploadVerificationScreenState extends ConsumerState<UploadVerificationScreen> {
  File? _beforeImage;
  File? _afterImage;
  double? _lat, _lng;
  bool _isLoading = false;

  Future<void> _pickImage(bool isBefore) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file != null) {
      setState(() {
        if (isBefore) _beforeImage = File(file.path);
        else _afterImage = File(file.path);
      });
    }
  }

  Future<void> _getLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition();
        setState(() { _lat = pos.latitude; _lng = pos.longitude; });
      }
    } catch (_) {
      setState(() { _lat = 26.8467; _lng = 80.9462; });
    }
  }

  Future<void> _upload() async {
    if (_afterImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('After image is required')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final formData = FormData.fromMap({
        'task_id': widget.taskId,
        if (_lat != null) 'latitude': _lat,
        if (_lng != null) 'longitude': _lng,
        if (_beforeImage != null)
          'before_image': await MultipartFile.fromFile(_beforeImage!.path, filename: 'before.jpg'),
        'after_image': await MultipartFile.fromFile(_afterImage!.path, filename: 'after.jpg'),
      });
      await ApiService.instance.uploadVerification(formData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification uploaded!'), backgroundColor: AppColors.success),
      );
      context.go('/leader/tasks');
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
        title: const Text('Upload Verification'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/leader/tasks'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.info, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Upload before & after photos to verify task completion',
                      style: TextStyle(fontSize: 13, color: AppColors.info),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Before image
            _ImageUploadCard(
              label: 'Before Photo',
              subtitle: 'Photo of the issue before resolution',
              image: _beforeImage,
              isRequired: false,
              onTap: () => _pickImage(true),
            ),
            const SizedBox(height: 16),

            // After image
            _ImageUploadCard(
              label: 'After Photo *',
              subtitle: 'Photo showing the issue is resolved',
              image: _afterImage,
              isRequired: true,
              onTap: () => _pickImage(false),
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
                  border: Border.all(color: _lat != null ? AppColors.success : AppColors.borderColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        color: _lat != null ? AppColors.success : AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _lat != null
                            ? 'Location captured: ${_lat?.toStringAsFixed(4)}, ${_lng?.toStringAsFixed(4)}'
                            : 'Tap to capture current location',
                        style: TextStyle(
                          color: _lat != null ? AppColors.success : AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      _lat != null ? Icons.check_circle : Icons.my_location,
                      color: _lat != null ? AppColors.success : AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _upload,
                icon: _isLoading
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_outlined),
                label: const Text('Upload Verification'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageUploadCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final File? image;
  final bool isRequired;
  final VoidCallback onTap;

  const _ImageUploadCard({
    required this.label,
    required this.subtitle,
    this.image,
    required this.isRequired,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: image != null ? AppColors.success : AppColors.borderColor,
            width: image != null ? 2 : 1,
          ),
        ),
        child: image != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(image!, fit: BoxFit.cover),
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 16),
                      ),
                    ),
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter, end: Alignment.topCenter,
                            colors: [Colors.black54, Colors.transparent],
                          ),
                        ),
                        child: Text(label,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 40, color: AppColors.textHint),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                ],
              ),
      ),
    );
  }
}