import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme/theme_provider.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Контроллеры для профиля
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _streetController = TextEditingController();
  final _houseNumberController = TextEditingController();
  final _postalController = TextEditingController();

  bool _profileLoading = false;
  bool _profileSaved = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.getProfile();
    if (profile == null) return;
    setState(() {
      _nameController.text = profile['first_name'] ?? '';
      _phoneController.text = profile['phone'] ?? '';
      _cityController.text = profile['city'] ?? '';
      _streetController.text = profile['street'] ?? '';
      _houseNumberController.text = profile['house_number'] ?? '';
      _postalController.text = profile['postal_code'] ?? '';
    });
  }

  Future<void> _saveProfile() async {
    setState(() {
      _profileLoading = true;
      _profileSaved = false;
    });
    try {
      await AuthService.updateProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        city: _cityController.text.trim(),
        street: _streetController.text.trim(),
        houseNumber: _houseNumberController.text.trim(),
        postalCode: _postalController.text.trim(),
      );
      setState(() {
        _profileSaved = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _profileSaved = false);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern: $e')),
      );
    } finally {
      setState(() {
        _profileLoading = false;
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Bitte aktiviere die Standortdienste in den Einstellungen.'),
        ),
      );
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Standortberechtigung verweigert. Autovervollständigung nicht möglich.',
          ),
        ),
      );
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final placemarks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final placemark = placemarks.first;
      setState(() {
        _cityController.text = placemark.locality ?? '';
        _streetController.text = placemark.thoroughfare ?? '';
        _houseNumberController.text = placemark.subThoroughfare ?? '';
        _postalController.text = placemark.postalCode ?? '';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Standort ermitteln fehlgeschlagen: $e')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _streetController.dispose();
    _houseNumberController.dispose();
    _postalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        backgroundColor: appTheme.backgroundColor,
        foregroundColor: appTheme.textColor,
      ),
      backgroundColor: appTheme.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Оставлен только раздел "Mein Profil" и поля профиля
            // Новый раздел "Mein Profil"
            const SizedBox(height: 32),
            Text('Mein Profil', style: TextStyle(fontSize: 18, color: appTheme.textColor)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.my_location),
              label: Text(
                'Aktuellen Standort verwenden',
                style: TextStyle(color: appTheme.textColor),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: appTheme.cardColor,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _useCurrentLocation,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Name',
                filled: true,
                fillColor: appTheme.cardColor,
                labelStyle: TextStyle(color: appTheme.textColorSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              style: TextStyle(color: appTheme.textColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: 'Telefon',
                filled: true,
                fillColor: appTheme.cardColor,
                labelStyle: TextStyle(color: appTheme.textColorSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              style: TextStyle(color: appTheme.textColor),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityController,
              decoration: InputDecoration(
                labelText: 'Stadt',
                filled: true,
                fillColor: appTheme.cardColor,
                labelStyle: TextStyle(color: appTheme.textColorSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              style: TextStyle(color: appTheme.textColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _streetController,
              decoration: InputDecoration(
                labelText: 'Straße',
                filled: true,
                fillColor: appTheme.cardColor,
                labelStyle: TextStyle(color: appTheme.textColorSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              style: TextStyle(color: appTheme.textColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _houseNumberController,
              decoration: InputDecoration(
                labelText: 'Hausnummer',
                filled: true,
                fillColor: appTheme.cardColor,
                labelStyle: TextStyle(color: appTheme.textColorSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              style: TextStyle(color: appTheme.textColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _postalController,
              decoration: InputDecoration(
                labelText: 'Postleitzahl',
                filled: true,
                fillColor: appTheme.cardColor,
                labelStyle: TextStyle(color: appTheme.textColorSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              style: TextStyle(color: appTheme.textColor),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _profileLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: appTheme.buttonColor,
                foregroundColor: appTheme.textColor,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _profileLoading
                  ? const CircularProgressIndicator()
                  : _profileSaved
                      ? const Icon(Icons.check, color: Colors.green)
                      : const Text('Profil speichern'),
            ),
          ],
        ),
      ),
    );
  }
}
