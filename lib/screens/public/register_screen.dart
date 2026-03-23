import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../core/localization.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _cityCtrl  = TextEditingController();
  final _townCtrl  = TextEditingController();

  bool _obscure           = true;
  String _selectedRole    = 'citizen';
  bool _isGettingLocation = false;
  int  _zoneTab           = 0;
  late TabController _tabCtrl;

  final _roles = [
    {'value': 'citizen',          'label': 'Citizen',          'icon': Icons.person_outline,          'desc': 'Report and track local issues'},
    {'value': 'leader',           'label': 'Leader',           'icon': Icons.shield_outlined,          'desc': 'Manage and resolve civic issues'},
    {'value': 'higher_authority', 'label': 'Higher Authority', 'icon': Icons.account_balance_outlined, 'desc': 'Oversee escalated issues'},
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() => _zoneTab = _tabCtrl.index));
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _emailCtrl, _passCtrl, _phoneCtrl,
                     _stateCtrl, _cityCtrl, _townCtrl]) {
      c.dispose();
    }
    _tabCtrl.dispose();
    super.dispose();
  }

  // ─── Location detect ──────────────────────────────────────────────────────
  Future<void> _detectLocation() async {
    // I'll skip translating error messages for now to keep it concise, but the main UI will be translated
    setState(() => _isGettingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        _snack('Location permission denied — enable in Settings', error: true); return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Please enable GPS / Location service', error: true); return;
      }
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) { _snack('Could not get location — try manual entry', error: true); return; }
        pos = last;
      }
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) {
        final p = marks.first;
        setState(() {
          _stateCtrl.text = p.administrativeArea ?? '';
          _cityCtrl.text  = p.locality ?? '';
          _townCtrl.text  = p.subLocality?.isNotEmpty == true
              ? p.subLocality! : (p.subAdministrativeArea ?? '');
        });
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  // ─── Register ─────────────────────────────────────────────────────────────
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole == 'leader') {
      if (_stateCtrl.text.trim().isEmpty || _cityCtrl.text.trim().isEmpty) {
        _snack('Please fill State and City for working zone', error: true); return;
      }
    }
    final leaderLocation = _selectedRole == 'leader'
        ? {'state': _stateCtrl.text.trim(), 'city': _cityCtrl.text.trim(), 'town': _townCtrl.text.trim()}
        : null;

    final success = await ref.read(authProvider.notifier).register(
      name: _nameCtrl.text.trim(), email: _emailCtrl.text.trim(),
      password: _passCtrl.text, role: _selectedRole,
      phone: _phoneCtrl.text.trim(), leaderLocation: leaderLocation,
    );
    if (!mounted) return;
    if (success) {
      switch (_selectedRole) {
        case 'leader':           context.go('/leader');    break;
        case 'higher_authority': context.go('/authority'); break;
        default:                 context.go('/citizen');
      }
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
    final auth        = ref.watch(authProvider);
    final size        = MediaQuery.of(context).size;
    final isTablet    = size.width >= 600;
    final hPad        = isTablet ? size.width * 0.12 : 20.0;
    final headingSize = isTablet ? 28.0 : 22.0;
    final iconBoxSize = isTablet ? 56.0 : 44.0;
    final iconSize    = isTablet ? 28.0 : 22.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: AppColors.primary),
                        onPressed: () => context.go('/'),
                        padding: EdgeInsets.zero,
                        iconSize: isTablet ? 24 : 20,
                      ),
                      IconButton(
                        onPressed: () {
                          final currentLocale = ref.read(localeProvider);
                          ref.read(localeProvider.notifier).setLocale(currentLocale.languageCode == 'en' 
                                  ? const Locale('hi') 
                                  : const Locale('en'));
                        },
                        icon: const Icon(Icons.language, color: AppColors.primary),
                      ),
                    ],
                  ),
                  SizedBox(height: isTablet ? 36 : 24),

                  // Header row
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Container(
                      width: iconBoxSize, height: iconBoxSize,
                      decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.how_to_reg_outlined,
                          color: Colors.white, size: iconSize),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.translate('create_account'),
                          style: TextStyle(fontSize: headingSize,
                              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(context.translate('join_platform'),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ])),
                  ]),
                  SizedBox(height: isTablet ? 32 : 24),

                  // Role cards — 2-column on tablet
                  _sectionLabel(context.translate('i_am_a')),
                  const SizedBox(height: 10),
                  isTablet ? _roleGridTablet() : _roleListMobile(),
                  SizedBox(height: isTablet ? 28 : 20),

                  // Form
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(context.translate('personal_details')),
                        const SizedBox(height: 14),

                        // Name + Phone in row on tablet
                        if (isTablet)
                          Row(children: [
                            Expanded(child: _nameField()),
                            const SizedBox(width: 14),
                            Expanded(child: _phoneField()),
                          ])
                        else ...[
                          _nameField(),
                          const SizedBox(height: 14),
                          _phoneField(),
                        ],
                        const SizedBox(height: 14),

                        // Email + Password in row on tablet
                        if (isTablet)
                          Row(children: [
                            Expanded(child: _emailField()),
                            const SizedBox(width: 14),
                            Expanded(child: _passwordField()),
                          ])
                        else ...[
                          _emailField(),
                          const SizedBox(height: 14),
                          _passwordField(),
                        ],

                        // Leader zone
                        if (_selectedRole == 'leader') ...[
                          SizedBox(height: isTablet ? 28 : 22),
                          _leaderZoneSection(isTablet: isTablet),
                        ],

                        // Error
                        if (auth.error != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: AppColors.errorLight,
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(auth.error!,
                                style: const TextStyle(color: AppColors.error, fontSize: 13)),
                          ),
                        ],

                        SizedBox(height: isTablet ? 36 : 28),

                        // Submit
                        SizedBox(
                          width: double.infinity,
                          height: isTablet ? 54 : 50,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _register,
                            style: ElevatedButton.styleFrom(
                              textStyle: TextStyle(
                                  fontSize: isTablet ? 16 : 15,
                                  fontWeight: FontWeight.w600),
                            ),
                            child: auth.isLoading
                                ? const SizedBox(height: 20, width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Text(context.translate('create_account')),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Login link
                        Center(child: Wrap(children: [
                          Text(context.translate('already_have_account'),
                              style: const TextStyle(color: AppColors.textSecondary)),
                          GestureDetector(
                            onTap: () => context.go('/login'),
                            child: Text(context.translate('sign_in_link'),
                                style: const TextStyle(color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ])),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Role layouts ─────────────────────────────────────────────────────────

  Widget _roleListMobile() => Column(
    children: _roles.map(_roleCard).toList(),
  );

  Widget _roleGridTablet() => Row(
    children: _roles.map((r) => Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: r != _roles.last ? 10 : 0),
        child: _roleCard(r, compact: true),
      ),
    )).toList(),
  );

  Widget _roleCard(Map<String, dynamic> role, {bool compact = false}) {
    final selected = _selectedRole == role['value'];
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role['value'] as String),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(compact ? 12 : 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: compact
            ? Column(children: [
                Icon(role['icon'] as IconData,
                    color: selected ? AppColors.primary : AppColors.textSecondary,
                    size: 24),
                const SizedBox(height: 8),
                Text(role['label'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: selected ? AppColors.primary : AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(role['desc'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                if (selected) ...[
                  const SizedBox(height: 6),
                  const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                ],
              ])
            : Row(children: [
                Icon(role['icon'] as IconData,
                    color: selected ? AppColors.primary : AppColors.textSecondary, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(role['label'] as String,
                      style: TextStyle(fontWeight: FontWeight.w600,
                          color: selected ? AppColors.primary : AppColors.textPrimary)),
                  Text(role['desc'] as String,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ])),
                if (selected) const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
              ]),
      ),
    );
  }

  // ─── Form fields ──────────────────────────────────────────────────────────

  Widget _nameField() => TextFormField(
    controller: _nameCtrl,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(
        labelText: context.translate('full_name'), prefixIcon: const Icon(Icons.person_outline)),
    validator: (v) => v == null || v.trim().length < 2 ? context.translate('full_name') : null,
  );

  Widget _emailField() => TextFormField(
    controller: _emailCtrl,
    keyboardType: TextInputType.emailAddress,
    decoration: InputDecoration(
        labelText: context.translate('email_address'), prefixIcon: const Icon(Icons.email_outlined)),
    validator: (v) => v == null || !v.contains('@') ? context.translate('enter_valid_email') : null,
  );

  Widget _phoneField() => TextFormField(
    controller: _phoneCtrl,
    keyboardType: TextInputType.phone,
    maxLength: 10,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: '${context.translate('contact_number')} *',
      prefixIcon: const Icon(Icons.phone_outlined),
      prefixText: '+91  ',
      counterText: '',
      hintText: '10-digit number',
    ),
    validator: (v) {
      if (v == null || v.trim().isEmpty) return 'Contact number required';
      if (v.trim().length < 10) return 'Enter 10-digit number';
      return null;
    },
  );

  Widget _passwordField() => TextFormField(
    controller: _passCtrl,
    obscureText: _obscure,
    decoration: InputDecoration(
      labelText: context.translate('password'),
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
    validator: (v) => v == null || v.length < 6 ? context.translate('min_6_char') : null,
  );

  // ─── Leader Working Zone ──────────────────────────────────────────────────

  Widget _leaderZoneSection({required bool isTablet}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.translate('working_zone')),
        const SizedBox(height: 4),
        Text(
          context.translate('set_area_manage'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),

        // Tab switcher
        Container(
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor),
          ),
          padding: const EdgeInsets.all(4),
          child: TabBar(
            controller: _tabCtrl,
            indicator: BoxDecoration(
                color: AppColors.primary, borderRadius: BorderRadius.circular(9)),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            dividerColor: Colors.transparent,
            tabs: [
              Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.edit_outlined, size: 15),
                const SizedBox(width: 6),
                Text(context.translate('manual')),
              ])),
              Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.my_location, size: 15),
                const SizedBox(width: 6),
                Text(context.translate('use_location')),
              ])),
            ],
          ),
        ),
        const SizedBox(height: 16),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _zoneTab == 0
              ? _manualZone(isTablet: isTablet)
              : _locationZone(),
        ),
      ],
    );
  }

  Widget _manualZone({required bool isTablet}) => Column(
    key: const ValueKey('manual'),
    children: [
      // State + City side-by-side on tablet
      if (isTablet)
        Row(children: [
          Expanded(child: _stateField()),
          const SizedBox(width: 14),
          Expanded(child: _cityField()),
        ])
      else ...[
        _stateField(),
        const SizedBox(height: 14),
        _cityField(),
      ],
      const SizedBox(height: 14),
      _townField(),
    ],
  );

  Widget _stateField() => TextFormField(
    controller: _stateCtrl,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(
        labelText: '${context.translate('state')} *', prefixIcon: const Icon(Icons.map_outlined),
        hintText: 'e.g. Uttar Pradesh'),
    validator: (v) => _selectedRole == 'leader' && (v == null || v.trim().isEmpty)
        ? 'State is required' : null,
  );

  Widget _cityField() => TextFormField(
    controller: _cityCtrl,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(
        labelText: '${context.translate('city')} *',
        prefixIcon: const Icon(Icons.location_city_outlined),
        hintText: 'e.g. Lucknow'),
    validator: (v) => _selectedRole == 'leader' && (v == null || v.trim().isEmpty)
        ? 'City is required' : null,
  );

  Widget _townField() => TextFormField(
    controller: _townCtrl,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(
        labelText: context.translate('town'),
        prefixIcon: const Icon(Icons.holiday_village_outlined),
        hintText: 'e.g. Hazratganj'),
  );

  Widget _locationZone() {
    final hasData = _stateCtrl.text.isNotEmpty || _cityCtrl.text.isNotEmpty;
    return Column(
      key: const ValueKey('location'),
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isGettingLocation ? null : _detectLocation,
            icon: _isGettingLocation
                ? const SizedBox(height: 16, width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.gps_fixed),
            label: Text(_isGettingLocation ? 'Detecting…'
                : hasData ? 'Re-detect Location' : context.translate('detect_my_location')),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppColors.primary),
              foregroundColor: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (hasData) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.lightbulb_outline, color: AppColors.info, size: 18),
                    const SizedBox(width: 8),
                    Text(context.translate('how_it_works'),
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.info)),
                  ]),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Text(context.translate('location_detected'),
                    style: TextStyle(fontWeight: FontWeight.w600,
                        color: AppColors.success, fontSize: 13)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _tabCtrl.animateTo(0),
                  child: Text(context.translate('edit'),
                      style: TextStyle(color: AppColors.primary,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
              _locRow(Icons.map_outlined, 'State', _stateCtrl.text),
              const SizedBox(height: 5),
              _locRow(Icons.location_city_outlined, 'City', _cityCtrl.text),
              if (_townCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 5),
                _locRow(Icons.holiday_village_outlined, 'Town', _townCtrl.text),
              ],
            ]),
          ),
          const SizedBox(height: 8),
          Text(context.translate('edit_manual_hint'),
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ] else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.inputFill, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
              SizedBox(width: 10),
              Expanded(child: Text(
                'Tap above to auto-fill your working zone from GPS.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              )),
            ]),
          ),
      ],
    );
  }

  Widget _locRow(IconData icon, String label, String value) => Row(children: [
    Icon(icon, size: 13, color: AppColors.textSecondary),
    const SizedBox(width: 6),
    Text('$label: ', style: const TextStyle(
        fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
    Expanded(child: Text(value, style: const TextStyle(
        fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600))),
  ]);

  Widget _sectionLabel(String text) => Row(children: [
    Container(width: 3, height: 16,
        decoration: BoxDecoration(color: AppColors.primary,
            borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(text, style: const TextStyle(
        fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
  ]);
}
