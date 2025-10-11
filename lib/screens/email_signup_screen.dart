// lib/screens/email_signup_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../services/auth_service.dart';
import 'email_login_screen.dart';
import 'home_screen.dart';

class EmailSignupScreen extends StatefulWidget {
  final String? initialName;
  final String? initialPhone;
  final String? initialCity;
  final String? initialStreet;
  final String? initialHouseNumber;
  final String? initialPostal;

  const EmailSignupScreen({
    Key? key,
    this.initialName,
    this.initialPhone,
    this.initialCity,
    this.initialStreet,
    this.initialHouseNumber,
    this.initialPostal,
  }) : super(key: key);

  @override
  State<EmailSignupScreen> createState() => _EmailSignupScreenState();
}

class _EmailSignupScreenState extends State<EmailSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _streetController = TextEditingController();
  final _houseNumberController = TextEditingController();
  final _postalController = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _streetController.dispose();
    _houseNumberController.dispose();
    _postalController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) _nameController.text = widget.initialName!;
    if (widget.initialPhone != null) _phoneController.text = widget.initialPhone!;
    if (widget.initialCity != null) _cityController.text = widget.initialCity!;
    if (widget.initialStreet != null) _streetController.text = widget.initialStreet!;
    if (widget.initialHouseNumber != null) _houseNumberController.text = widget.initialHouseNumber!;
    if (widget.initialPostal != null) _postalController.text = widget.initialPostal!;
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white10,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        city: _cityController.text.trim(),
        street: _streetController.text.trim(),
        houseNumber: _houseNumberController.text.trim(),
        postalCode: _postalController.text.trim(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bestätigen Sie Ihre E-Mail über den Link im Posteingang.',
          ),
        ),
      );
      // После регистрации — переходим в HomeScreen на вкладку «Profil»
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 2)),
        (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Registrieren',
          style: GoogleFonts.fredokaOne(color: Colors.orange),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // E-Mail & Passwort
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('E-Mail'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'E-Mail ist erforderlich';
                    if (!v.contains('@')) return 'Ungültige E-Mail';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Passwort'),
                  obscureText: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Passwort ist erforderlich' : null,
                ),

                const SizedBox(height: 24),
                // Persönliche Daten
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name ist erforderlich' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Telefon'),
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Telefon ist erforderlich' : null,
                ),

                const SizedBox(height: 24),
                // Geolocation-Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.my_location),
                  label: Text(
                    'Aktuellen Standort verwenden',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _useCurrentLocation,
                ),
                const SizedBox(height: 16),

                // Adresse
                TextFormField(
                  controller: _cityController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Stadt'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Stadt ist erforderlich' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _streetController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Straße'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Straße ist erforderlich' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _houseNumberController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Hausnummer'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Hausnummer ist erforderlich'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _postalController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Postleitzahl'),
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'PLZ ist erforderlich' : null,
                ),

                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(
                          'Registrieren',
                          style: GoogleFonts.poppins(color: Colors.black, fontSize: 18),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
