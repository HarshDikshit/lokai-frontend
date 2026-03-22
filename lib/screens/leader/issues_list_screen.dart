// screens/leader/issues_list_screen.dart
// Leader view — shows assigned issues with cluster complaint-count badge.
// Existing GPS-stamp + before/after photo logic preserved exactly.
// Fixed: safe image file handling for before/after photos so polling/rebuilds
// do not crash when temp/cache image paths disappear.

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../core/app_constants.dart';
import '../../models/models.dart';
import '../../providers/issues_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';

// ─── Safe file helper ─────────────────────────────────────────────────────────
bool _safeExists(File? file) {
  try {
    return file != null && file.existsSync();
  } catch (_) {
    return false;
  }
}

// ─── GPS helper ───────────────────────────────────────────────────────────────
Future<({double lat, double lng, String address})> _fetchGps() async {
  LocationPermission perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.deniedForever) {
    throw 'Location permission denied';
  }
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw 'Enable GPS first';
  }

  Position pos;
  try {
    pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    if (last == null) throw 'Could not get location — try again';
    pos = last;
  }

  String addr = '';
  try {
    final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
    if (marks.isNotEmpty) {
      final p = marks.first;
      addr = [p.subLocality, p.locality, p.administrativeArea]
          .where((v) => v != null && v!.isNotEmpty)
          .join(', ');
    }
  } catch (_) {}

  return (lat: pos.latitude, lng: pos.longitude, address: addr);
}

// ─── GPS + timestamp stamp ────────────────────────────────────────────────────
Future<File> _stampImage({
  required File src,
  required double lat,
  required double lng,
  required String address,
  required DateTime capturedAt,
}) async {
  final bytes = await src.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final orig = frame.image;
  final w = orig.width.toDouble();
  final h = orig.height.toDouble();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
  canvas.drawImage(orig, Offset.zero, Paint());

  final fontSize = (w * 0.028).clamp(18.0, 38.0);
  final padding = fontSize * 0.6;
  final lineH = fontSize * 1.45;
  final stampH = lineH * 3 + padding * 2;
  final stampY = h - stampH;

  canvas.drawRect(
    Rect.fromLTWH(0, stampY, w, stampH),
    Paint()..color = const Color(0xCC000000),
  );

  void drawLine(String text, double y, {Color color = Colors.white}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: w - padding * 2);

    tp.paint(canvas, Offset(padding, y));
  }

  drawLine(
    DateFormat('dd MMM yyyy  HH:mm:ss').format(capturedAt),
    stampY + padding,
    color: const Color(0xFFFFD54F),
  );
  drawLine(
    'GPS: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
    stampY + padding + lineH,
  );
  drawLine(
    address.isNotEmpty
        ? address
        : '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
    stampY + padding + lineH * 2,
    color: Colors.white70,
  );

  final picture = recorder.endRecording();
  final stamped = await picture.toImage(orig.width, orig.height);
  final pngBytes = await stamped.toByteData(format: ui.ImageByteFormat.png);

  // FIX: use a more persistent directory instead of temp/cache
  final dir = await getApplicationDocumentsDirectory();
  final out = File(
    '${dir.path}/stamped_${DateTime.now().millisecondsSinceEpoch}.png',
  );

  await out.writeAsBytes(pngBytes!.buffer.asUint8List());
  return out;
}

final _beforePhotos = <String, File>{};

// ─────────────────────────────────────────────────────────────────────────────
class LeaderIssuesListScreen extends ConsumerStatefulWidget {
  const LeaderIssuesListScreen({super.key});

  @override
  ConsumerState<LeaderIssuesListScreen> createState() =>
      _LeaderIssuesListScreenState();
}

class _LeaderIssuesListScreenState
    extends ConsumerState<LeaderIssuesListScreen> {
  String? _capturingBeforeFor;

  Future<void> _captureBeforePhoto(Issue issue) async {
    setState(() => _capturingBeforeFor = issue.id);
    try {
      final gps = await _fetchGps();
      final raw = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (raw == null) return;

      final stamped = await _stampImage(
        src: File(raw.path),
        lat: gps.lat,
        lng: gps.lng,
        address: gps.address,
        capturedAt: DateTime.now(),
      );

      if (!mounted) return;
      setState(() => _beforePhotos[issue.id] = stamped);
    } catch (e) {
      if (!mounted) return;
      _snack('Before photo error: $e');
    } finally {
      if (mounted) setState(() => _capturingBeforeFor = null);
    }
  }

  void _openResolutionSheet(Issue issue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResolutionSheet(
        issue: issue,
        beforePhoto: _beforePhotos[issue.id],
        onSuccess: () {
          _beforePhotos.remove(issue.id);
          ref.invalidate(issuesProvider);
        },
      ),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );

  @override
  Widget build(BuildContext context) {
    final issuesAsync = ref.watch(issuesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Assigned Issues'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/leader'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.read(issuesProvider.notifier).fetchIssues(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: (i) {
          if (i == 0) context.go('/leader');
          if (i == 2) context.go('/feed');
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            label: 'Issues',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_rounded),
            label: 'Feed',
          ),
        ],
      ),
      body: issuesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: '$e',
          onRetry: () => ref.read(issuesProvider.notifier).fetchIssues(),
        ),
        data: (issues) {
          if (issues.isEmpty) return const _EmptyState();

          final clusterCounts = <String, int>{};
          final primaryIssues = <String, Issue>{};
          final independentIssues = <Issue>[];

          for (final i in issues) {
            if (i.issueClusterId != null) {
              final cid = i.issueClusterId!;
              clusterCounts[cid] = (clusterCounts[cid] ?? 0) + 1;
              if (!primaryIssues.containsKey(cid)) {
                 primaryIssues[cid] = i;
              } else if (i.matchStatus != 'auto_merged') {
                 primaryIssues[cid] = i;
              }
            } else {
              independentIssues.add(i);
            }
          }

          final uniqueSorted = [...primaryIssues.values, ...independentIssues];

          final open =
              uniqueSorted.where((i) => i.status == IssueStatus.open).toList();
          final awaiting =
              uniqueSorted.where((i) => i.awaitingCitizenFeedback).toList();
          final rest = uniqueSorted
              .where(
                (i) =>
                    i.status != IssueStatus.open &&
                    !i.awaitingCitizenFeedback,
              )
              .toList();
          final sorted = [...open, ...awaiting, ...rest];

          if (sorted.isEmpty) return const _EmptyState();

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final issue = sorted[i];
              final count = (issue.issueClusterId != null)
                  ? (clusterCounts[issue.issueClusterId!] ?? 1)
                  : 1;

              return _IssueCard(
                issue: issue,
                duplicateCount: count,
                beforePhoto: _beforePhotos[issue.id],
                capturingBefore: _capturingBeforeFor == issue.id,
                onTap: () => context.push('/issue/${issue.id}'),
                onCaptureBefore: () => _captureBeforePhoto(issue),
                onResolve: () => _openResolutionSheet(issue),
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Issue card ───────────────────────────────────────────────────────────────
class _IssueCard extends StatelessWidget {
  final Issue issue;
  final int duplicateCount;
  final File? beforePhoto;
  final bool capturingBefore;
  final VoidCallback onTap;
  final VoidCallback onCaptureBefore;
  final VoidCallback onResolve;

  const _IssueCard({
    required this.issue,
    required this.duplicateCount,
    required this.beforePhoto,
    required this.capturingBefore,
    required this.onTap,
    required this.onCaptureBefore,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final canResolve = issue.leaderCanResolve;
    final isAwaiting = issue.awaitingCitizenFeedback;
    final isSecondAttempt = issue.resolutionAttempts >= 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: _statusColor(issue.status),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          InkWell(
            onTap: onTap,
            borderRadius: (canResolve || isAwaiting)
                ? BorderRadius.zero
                : const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          issue.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (issue.citizenPhone != null)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.call, size: 18, color: AppColors.success),
                          onPressed: () => launchUrl(Uri.parse('tel:${issue.citizenPhone}')),
                        ),
                      const SizedBox(width: 8),
                      StatusBadge(status: issue.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    issue.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (issue.category != null) _chip(issue.category!),
                      const Spacer(),
                      if (issue.location != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 12,
                              color: AppColors.textHint,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _locationLabel(issue.location!),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ResolutionTicks(
                        attempts: issue.resolutionAttempts,
                        status: issue.status,
                      ),
                    ],
                  ),
                  if (issue.issueClusterId != null) ...[
                    const SizedBox(height: 8),
                    _ClusterBadge(matchStatus: issue.matchStatus, duplicateCount: duplicateCount),
                  ],
                ],
              ),
            ),
          ),
          if (canResolve || isAwaiting) ...[
            const Divider(height: 1, color: AppColors.borderColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: canResolve
                  ? Column(
                      children: [
                        _BeforePhotoStrip(
                          photo: beforePhoto,
                          capturing: capturingBefore,
                          onCapture: onCaptureBefore,
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: onResolve,
                            icon: const Icon(Icons.upload_rounded, size: 16),
                            label: Text(
                              isSecondAttempt
                                  ? 'Submit Final Resolution  ✔✔'
                                  : 'Submit Resolution  ✔',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSecondAttempt
                                  ? AppColors.warning
                                  : AppColors.success,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    )
                  : _AwaitingFeedbackBanner(
                      attempts: issue.resolutionAttempts,
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  String _locationLabel(Map<String, dynamic> loc) {
    final parts = <String>[
      if ((loc['town'] ?? '').toString().isNotEmpty) loc['town'] as String,
      if ((loc['city'] ?? '').toString().isNotEmpty) loc['city'] as String,
    ];
    return parts.join(', ');
  }

  Color _statusColor(String s) {
    switch (s) {
      case IssueStatus.open:
        return AppColors.statusOpen;
      case IssueStatus.resolvedL1:
        return AppColors.success;
      case IssueStatus.resolvedL2:
        return AppColors.statusResolvedL2;
      case IssueStatus.escalated:
        return AppColors.statusEscalated;
      case IssueStatus.closed:
        return AppColors.statusClosed;
      default:
        return AppColors.borderColor;
    }
  }
}

// ─── Cluster badge for leader cards ──────────────────────────────────────────
class _ClusterBadge extends StatelessWidget {
  final String? matchStatus;
  final int duplicateCount;
  const _ClusterBadge({this.matchStatus, this.duplicateCount = 1});

  @override
  Widget build(BuildContext context) {
    final isGroup = matchStatus == 'auto_merged' || duplicateCount > 1;

    final (icon, label, color) = matchStatus == 'pending_review'
      ? (
          Icons.hourglass_top_rounded,
          'Awaiting duplicate review',
          AppColors.info,
        )
      : isGroup
      ? (
          Icons.group_rounded,
          duplicateCount > 1 ? '$duplicateCount citizens reported this' : 'Multiple citizens reported this',
          AppColors.warning,
        )
      : (
          Icons.fiber_new_rounded,
          'First report of this issue',
          AppColors.success,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Awaiting feedback banner ─────────────────────────────────────────────────
class _AwaitingFeedbackBanner extends StatelessWidget {
  final int attempts;
  const _AwaitingFeedbackBanner({required this.attempts});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.info.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.info.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.hourglass_top_rounded,
              size: 16,
              color: AppColors.info,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attempts == 1
                        ? 'Awaiting citizen feedback on Resolution ✔'
                        : 'Awaiting citizen feedback on Final Resolution ✔✔',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'You cannot submit another resolution until the citizen responds.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─── Before photo strip ───────────────────────────────────────────────────────
class _BeforePhotoStrip extends StatelessWidget {
  final File? photo;
  final bool capturing;
  final VoidCallback onCapture;

  const _BeforePhotoStrip({
    required this.photo,
    required this.capturing,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _safeExists(photo);

    return GestureDetector(
      onTap: capturing ? null : onCapture,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: hasPhoto
              ? AppColors.info.withOpacity(0.06)
              : AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasPhoto
                ? AppColors.info.withOpacity(0.5)
                : AppColors.borderColor,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(11)),
              child: hasPhoto
                  ? Image.file(
                      photo!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 56,
                        height: 56,
                        color: AppColors.info.withOpacity(0.08),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 22,
                          color: AppColors.textHint,
                        ),
                      ),
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      color: AppColors.info.withOpacity(0.08),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        size: 22,
                        color: AppColors.textHint,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    hasPhoto
                        ? 'Before photo captured ✓'
                        : 'Capture "Before" photo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasPhoto
                          ? AppColors.info
                          : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    hasPhoto
                        ? 'GPS & timestamp stamped'
                        : 'Optional  ·  Camera only  ·  GPS stamped',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: capturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      hasPhoto
                          ? Icons.refresh_rounded
                          : Icons.camera_enhance_outlined,
                      color:
                          hasPhoto ? AppColors.info : AppColors.primary,
                      size: 22,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Resolution sheet ─────────────────────────────────────────────────────────
class _ResolutionSheet extends StatefulWidget {
  final Issue issue;
  final File? beforePhoto;
  final VoidCallback onSuccess;

  const _ResolutionSheet({
    required this.issue,
    required this.beforePhoto,
    required this.onSuccess,
  });

  @override
  State<_ResolutionSheet> createState() => _ResolutionSheetState();
}

class _ResolutionSheetState extends State<_ResolutionSheet> {
  final _notesCtrl = TextEditingController();

  File? _afterImage;
  double? _lat, _lng;
  String _address = '';
  bool _gettingGps = false;
  bool _takingPhoto = false;
  bool _submitting = false;

  bool get _isFinal => widget.issue.resolutionAttempts >= 1;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _captureAfterPhoto() async {
    setState(() => _takingPhoto = true);
    try {
      if (_lat == null) await _doGetGps();

      final raw = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (raw == null) return;

      final stamped = await _stampImage(
        src: File(raw.path),
        lat: _lat ?? 0,
        lng: _lng ?? 0,
        address: _address,
        capturedAt: DateTime.now(),
      );

      if (!mounted) return;
      setState(() => _afterImage = stamped);
    } catch (e) {
      _snack('Photo error: $e', error: true);
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  Future<void> _doGetGps() async {
    setState(() => _gettingGps = true);
    try {
      final gps = await _fetchGps();
      setState(() {
        _lat = gps.lat;
        _lng = gps.lng;
        _address = gps.address;
      });
    } catch (e) {
      _snack('Location: $e', error: true);
    } finally {
      if (mounted) setState(() => _gettingGps = false);
    }
  }

  Future<void> _submit() async {
    if (_notesCtrl.text.trim().length < 5) {
      _snack('Describe what was done (min 5 chars)', error: true);
      return;
    }
    if (!_safeExists(_afterImage)) {
      _snack('"After" photo is required', error: true);
      return;
    }

    setState(() => _submitting = true);

    try {
      await ApiService.instance.uploadVerification(
        issueId: widget.issue.id,
        beforeImagePath: _safeExists(widget.beforePhoto)
            ? widget.beforePhoto!.path
            : null,
        afterImagePath: _afterImage!.path,
        latitude: _lat,
        longitude: _lng,
      );

      await ApiService.instance.resolveIssue(
        widget.issue.id,
        _notesCtrl.text.trim(),
      );

      // Optional cleanup of local files after successful upload
      try {
        if (_safeExists(widget.beforePhoto)) {
          await widget.beforePhoto!.delete();
        }
      } catch (_) {}

      try {
        if (_safeExists(_afterImage)) {
          await _afterImage!.delete();
        }
      } catch (_) {}

      if (!mounted) return;

      widget.onSuccess();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFinal
                ? 'Final resolution submitted ✔✔ — awaiting citizen feedback'
                : 'Resolution submitted ✔ — awaiting citizen feedback',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: error ? AppColors.error : AppColors.success,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (_isFinal
                            ? AppColors.warning
                            : AppColors.success)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _isFinal
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded,
                    color: _isFinal
                        ? AppColors.warning
                        : AppColors.success,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isFinal
                            ? 'Final Resolution  ✔✔'
                            : 'Submit Resolution  ✔',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.issue.title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isFinal) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.warning.withOpacity(0.4),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.warning,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Final attempt. If the citizen rejects this, the issue escalates to Higher Authority and counts as a failure.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            _label(
              'Before Photo',
              Icons.photo_camera_back_outlined,
              note: 'Captured on issue card · optional',
            ),
            const SizedBox(height: 8),
            _BeforePreview(photo: widget.beforePhoto),
            const SizedBox(height: 20),
            _label(
              'After Photo',
              Icons.add_photo_alternate_outlined,
              required: true,
              note: 'Camera only · GPS stamped',
            ),
            const SizedBox(height: 8),
            _AfterPhotoTile(
              photo: _afterImage,
              taking: _takingPhoto,
              onTap: _captureAfterPhoto,
              onClear: () => setState(() => _afterImage = null),
            ),
            const SizedBox(height: 20),
            _label(
              'Location',
              Icons.location_on_outlined,
              note: 'Auto-fetched when photo taken',
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _gettingGps ? null : _doGetGps,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _lat != null
                      ? AppColors.successLight
                      : AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _lat != null
                        ? AppColors.success
                        : AppColors.borderColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      color: _lat != null
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _lat != null
                            ? '${_address.isNotEmpty ? "$_address\n" : ""}${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}'
                            : 'Tap to fetch location manually',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: _lat != null
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (_gettingGps)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (_lat != null)
                      GestureDetector(
                        onTap: () => setState(() {
                          _lat = null;
                          _lng = null;
                          _address = '';
                        }),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: AppColors.textHint,
                        ),
                      )
                    else
                      const Icon(
                        Icons.my_location,
                        color: AppColors.primary,
                        size: 18,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _label(
              'Resolution Notes',
              Icons.description_outlined,
              required: true,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Describe what was done to fix this issue…',
                hintStyle: TextStyle(fontSize: 13),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isFinal
                            ? Icons.send_rounded
                            : Icons.check_rounded,
                        size: 18,
                      ),
                label: Text(
                  _submitting
                      ? 'Uploading photos…'
                      : _isFinal
                          ? 'Submit Final Resolution  ✔✔'
                          : 'Submit Resolution  ✔',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isFinal
                      ? AppColors.warning
                      : AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _label(
    String text,
    IconData icon, {
    bool required = false,
    String? note,
  }) =>
      Row(
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (required)
            const Text(
              '  *',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (note != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                note,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ],
        ],
      );
}

class _BeforePreview extends StatelessWidget {
  final File? photo;
  const _BeforePreview({required this.photo});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _safeExists(photo);

    if (!hasPhoto) {
      return Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderColor),
        ),
        child: const Text(
          'No before photo attached (optional — capture on issue card)',
          style: TextStyle(fontSize: 11, color: AppColors.textHint),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.info.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              photo!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.inputFill,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textHint,
                ),
              ),
            ),
            Positioned(
              top: 6,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.info,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'BEFORE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AfterPhotoTile extends StatelessWidget {
  final File? photo;
  final bool taking;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _AfterPhotoTile({
    required this.photo,
    required this.taking,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _safeExists(photo);

    if (hasPhoto) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.success, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  photo!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.inputFill,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black54, Colors.transparent],
                      stops: [0, 0.5],
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'AFTER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 10,
                  left: 12,
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 14),
                      SizedBox(width: 5),
                      Text(
                        'GPS + timestamp stamped',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 8,
                  child: GestureDetector(
                    onTap: onClear,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: taking ? null : onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (taking) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              const Text(
                'Getting GPS & opening camera…',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_enhance_outlined,
                  size: 28,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Take "After" Photo  *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Camera only  ·  GPS & timestamp auto-stamped',
                style: TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 60,
                color: AppColors.textHint,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppColors.inputFill,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.inbox_outlined,
                  size: 52,
                  color: AppColors.textHint,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No issues assigned',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Issues assigned to you will appear here.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textHint,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}