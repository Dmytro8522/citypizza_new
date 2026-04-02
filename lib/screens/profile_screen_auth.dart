// lib/screens/profile_screen_auth.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io'; // уже есть

import '../utils/globals.dart';
import '../services/auth_service.dart';
import '../services/app_config_service.dart';
import '../utils/app_text.dart';
import 'settings_screen.dart';

class ProfileScreenAuth extends StatelessWidget {
  /// Колбэк для выхода — передаётся из MainScaffold
  final VoidCallback onLogout;

  const ProfileScreenAuth({
    super.key,
    required this.onLogout,
  });

  Future<void> _safeLaunch(Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: mode);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    await AuthService.signOut();
    onLogout();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final navigator = Navigator.of(context);
    bool confirmed = false;

    confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Konto löschen?'),
            content: const Text(
              'Dein Konto und alle zugehörigen Daten werden dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      ),
    );

    try {
      await AuthService.deleteAccount();
      navigator.pop(); // close progress
      onLogout();
      navigator.popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konto wurde gelöscht')),
      );
    } catch (e) {
      navigator.pop(); // close progress
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  Widget _buildContactInfo(BuildContext context) {
    final address = AppConfigService.string(
      'contact.address',
      fallback: 'Härtelstraße 7, 04420 Leipzig',
    );
    final email = AppConfigService.string(
      'contact.email',
      fallback: 'do84arov@gmail.com',
    );
    final phone = AppConfigService.string(
      'contact.phone',
      fallback: '+49 162 4514836',
    );
    final privacyUrl = AppConfigService.string(
      'contact.links.datenschutz',
      fallback: 'https://dmytro8522.github.io/citypizza-legal/index.html',
    );
    final termsUrl = AppConfigService.string(
      'contact.links.agb',
      fallback: 'https://dmytro8522.github.io/citypizza-legal/terms.html',
    );
    final supportUrl = AppConfigService.string(
      'contact.links.support',
      fallback: 'https://dmytro8522.github.io/citypizza-legal/support.html',
    );

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
                  final appleUrl = Uri.parse('http://maps.apple.com/?q=$query');
                  if (await canLaunchUrl(appleUrl)) {
                    await launchUrl(appleUrl, mode: LaunchMode.externalApplication);
                    return;
                  }
                }
                final googleUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
                await _safeLaunch(googleUrl);
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
                await _safeLaunch(uri);
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
                await _safeLaunch(uri);
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
            const Divider(color: Colors.white24, height: 24),
            InkWell(
              onTap: () async => _safeLaunch(Uri.parse(privacyUrl)),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  const Icon(Icons.privacy_tip, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Datenschutzerklärung',
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
              onTap: () async => _safeLaunch(Uri.parse(termsUrl)),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  const Icon(Icons.article, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AGB',
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
              onTap: () async => _safeLaunch(Uri.parse(supportUrl)),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  const Icon(Icons.support_agent, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Support',
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
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Unbekannt';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppConfigService.color(
          'theme.appBarBackground',
          fallback: Colors.black,
        ),
        title: Text(
          AppText.t('appBarTitles.profile', fallback: 'Profil'),
          style: GoogleFonts.fredokaOne(
            color: AppConfigService.color(
              'theme.appBarTitleColor',
              fallback: Colors.orange,
            ),
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.shopping_cart,
              color: AppConfigService.color(
                'theme.appBarIconColor',
                fallback: Colors.white,
              ),
            ),
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
            const CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white12,
              child: Icon(
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
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: Text(
                'Konto löschen',
                style: GoogleFonts.poppins(color: Colors.redAccent),
              ),
              onTap: () => _deleteAccount(context),
            ),
            _buildContactInfo(context),
          ],
        ),
      ),
    );
  }
}
