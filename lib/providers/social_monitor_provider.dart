import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/models.dart';

final socialMonitorProvider = FutureProvider<SocialMonitorResponse>((ref) async {
  // Artificial delay to simulate fetching, as requested by user
  await Future.delayed(const Duration(seconds: 2));
  
  final data = await ApiService.instance.getSocialMonitor();
  return SocialMonitorResponse.fromJson(data);
});
