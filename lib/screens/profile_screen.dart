// lib/screens/profile_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import '../widgets/common_app_bar.dart';
import '../utils/globals.dart';
import 'email_signup_screen.dart';
import 'email_login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  Widget _buildBenefit({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.orange, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactInfo(BuildContext context) {
    const address = 'Leipziger Str. 21, 04420, Markranstädt';
    const email = 'info@citypizzaservice.com';
    const phone = '034205 83916';

    return Card(
      color: Colors.white12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(top: 32, bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            InkWell(
              onTap: () async {
                final query = Uri.encodeComponent(address);
                if (Platform.isAndroid) {
                  final geoUri = Uri.parse('geo:0,0?q=$query');
                  if (await canLaunchUrl(geoUri)) {
                    await launchUrl(geoUri, mode: LaunchMode.externalApplication);
                    return;
                  }
                }
                if (Platform.isIOS) {
                  final appleUrl = 'http://maps.apple.com/?q=$query';
                  if (await canLaunchUrl(Uri.parse(appleUrl))) {
                    await launchUrl(Uri.parse(appleUrl), mode: LaunchMode.externalApplication);
                    return;
                  }
                }
                final googleUrl = 'https://www.google.com/maps/search/?api=1&query=$query';
                await launchUrl(Uri.parse(googleUrl), mode: LaunchMode.externalApplication);
              },
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.orange, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      address,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 24),
            InkWell(
              onTap: () async {
                final uri = Uri(scheme: 'mailto', path: email);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  const Icon(Icons.email, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      email,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 24),
            InkWell(
              onTap: () async {
                final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  const Icon(Icons.phone, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      phone,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: buildCommonAppBar(
        title: 'Profil',
        context: context,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Willkommen!',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Erstellen Sie ein Konto, um von exklusiven Vorteilen zu profitieren:',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                color: Colors.white12,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildBenefit(
                        icon: Icons.cake,
                        title: 'Geburtstagsrabatt',
                        subtitle:
                            'Sichern Sie sich einen persönlichen Rabatt an Ihrem Ehrentag.',
                      ),
                      const Divider(color: Colors.white24),
                      _buildBenefit(
                        icon: Icons.star,
                        title: 'Exklusive Angebote',
                        subtitle:
                            'Erhalten Sie Zugang zu Sonderaktionen und Gutscheinen.',
                      ),
                      const Divider(color: Colors.white24),
                      _buildBenefit(
                        icon: Icons.history,
                        title: 'Bestellverlauf',
                        subtitle:
                            'Behalten Sie Ihre vergangenen Bestellungen im Blick.',
                      ),
                      const Divider(color: Colors.white24),
                      _buildBenefit(
                        icon: Icons.flash_on,
                        title: 'Schneller Checkout',
                        subtitle:
                            'Speichern Sie Ihre Daten für einen noch schnelleren Bestellvorgang.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: () {
                  navigatorKey.currentState!.pushNamed('/signup');
                },
                child: Text(
                  'Registrieren',
                  style: GoogleFonts.poppins(
                    color: Colors.black,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orange,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: GoogleFonts.poppins(fontSize: 16),
                ),
                onPressed: () {
                  navigatorKey.currentState!.pushNamed('/login');
                },
                child: const Text('Anmelden'),
              ),
              _buildContactInfo(context),
            ],
          ),
        ),
      ),
    );
  }
}
