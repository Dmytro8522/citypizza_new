// lib/screens/profile_screen_auth.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io'; // уже есть

import '../widgets/common_app_bar.dart';
import '../utils/globals.dart';
import '../services/auth_service.dart';
import 'order_history_screen.dart';
import 'settings_screen.dart';

class ProfileScreenAuth extends StatelessWidget {
  /// Колбэк для выхода — передаётся из MainScaffold
  final VoidCallback onLogout;

  const ProfileScreenAuth({
    Key? key,
    required this.onLogout,
  }) : super(key: key);

  Future<void> _signOut(BuildContext context) async {
    await AuthService.signOut();
    onLogout();
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
                        // decoration: TextDecoration.underline, // убрано подчеркивание
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
                        // decoration: TextDecoration.underline, // убрано подчеркивание
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
                        // decoration: TextDecoration.underline, // убрано подчеркивание
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
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Unbekannt';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Profil',
          style: GoogleFonts.fredokaOne(color: Colors.orange),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart, color: Colors.white), // цвет иконки теперь белый
            tooltip: 'Warenkorb',
            onPressed: () {
              Navigator.of(context).pushNamed('/cart');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16)
              .add(EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom +
                      kBottomNavigationBarHeight)),
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white12,
              child: const Icon(
                Icons.person,
                size: 48,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              email,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.white),
              title: Text(
                'Bestellhistorie',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () {
                navigatorKey.currentState!.pushNamed('/history');
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.card_giftcard, color: Colors.white),
              title: Text(
                'Gutscheine & Angebote',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () => navigatorKey.currentState!.pushNamed('/discounts'),
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.white),
              title: Text(
                'Einstellungen',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white),
              title: Text(
                'Abmelden',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () => _signOut(context),
            ),
            _buildContactInfo(context),
          ],
        ),
      ),
    );
  }
}
