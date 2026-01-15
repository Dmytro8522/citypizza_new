import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/delivery_zone_service.dart';
import '../utils/address_localization.dart';
import '../utils/globals.dart';

/// Ensures the user selects delivery or pickup when they add to cart.
/// Shows dialog only if `delivery_mode` is missing or delivery lacks address data.
class DeliveryModePrompt {
  static Future<void> ensureModeSelected() async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final prefs = await SharedPreferences.getInstance();
    final existingMode = prefs.getString('delivery_mode');
    if (existingMode == 'pickup') return;
    if (existingMode == 'delivery') {
      final postal = prefs.getString('user_postal_code');
      final city = prefs.getString('user_city');
      final street = prefs.getString('user_street');
      final complete = [postal, city, street].every((e) => e != null && e.isNotEmpty);
      if (complete) return;
    }

    if (!ctx.mounted) return;
    await showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final postalCtrl = TextEditingController();
        double? minOrder;
        bool loading = false;
        return StatefulBuilder(builder: (context, setStateDialog) {
          Future<void> fetchMin(String code) async {
            final trimmed = code.trim();
            if (trimmed.length < 3) {
              setStateDialog(() => minOrder = null);
              return;
            }
            setStateDialog(() => loading = true);
            final mo = await DeliveryZoneService.getMinOrderForPostal(postalCode: trimmed);
            setStateDialog(() {
              minOrder = mo;
              loading = false;
            });
          }

          Future<void> pickDelivery() async {
            // Attempt auto-detect address
            try {
              final enabled = await Geolocator.isLocationServiceEnabled();
              if (enabled) {
                var perm = await Geolocator.checkPermission();
                if (perm == LocationPermission.denied) {
                  perm = await Geolocator.requestPermission();
                }
                if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
                  final pos = await Geolocator.getCurrentPosition();
                  final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude, localeIdentifier: 'de_DE');
                  final pl = placemarks.first;
                  final postal = pl.postalCode ?? '';
                  final city = normalizeAddressComponent(pl.locality ?? '');
                  final street = normalizeAddressComponent(pl.thoroughfare ?? '');
                  final house = normalizeAddressComponent(pl.subThoroughfare ?? '');
                  if (postal.isNotEmpty) {
                    postalCtrl.text = postal;
                    await fetchMin(postal);
                    await prefs.setString('user_postal_code', postal);
                  }
                  if (city.isNotEmpty) await prefs.setString('user_city', city);
                  if (street.isNotEmpty) await prefs.setString('user_street', street);
                  if (house.isNotEmpty) await prefs.setString('user_house_number', house);
                }
              }
            } catch (_) {}
            setStateDialog(() {});
          }

          return AlertDialog(
            backgroundColor: Colors.black.withOpacity(0.92),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            title: Text(
              'Bestellmodus wählen',
              style: GoogleFonts.poppins(
                color: Colors.orangeAccent,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bitte wählen Sie Lieferung oder Abholung. Für Lieferung benötigen wir Ihre Postleitzahl, um Mindestbestellwert und Verfügbarkeit zu prüfen.',
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            await prefs.setString('delivery_mode', 'pickup');
                            Navigator.of(dialogCtx, rootNavigator: true).pop();
                          },
                          child: const Text('Abholung', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            await prefs.setString('delivery_mode', 'delivery');
                            await pickDelivery();
                          },
                          child: const Text('Lieferung', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Postleitzahl (für Lieferung)', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: postalCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'z.B. 04109',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      suffixIcon: loading
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : (minOrder != null
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(Icons.check_circle, color: Colors.greenAccent.shade400),
                                )
                              : null),
                    ),
                    onChanged: (val) async {
                      await fetchMin(val);
                    },
                  ),
                  if (minOrder != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Mindestbestellwert: €${minOrder!.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Sie können diese Auswahl später in den Einstellungen ändern.',
                    style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        // Save entered postal if any, then close the dialog
                        final postal = postalCtrl.text.trim();
                        if (postal.isNotEmpty) {
                          await prefs.setString('user_postal_code', postal);
                        }
                        Navigator.of(dialogCtx, rootNavigator: true).pop();
                      },
                      child: const Text('OK', style: TextStyle(color: Colors.orangeAccent)),
                    ),
                  )
                ],
              ),
            ),
          );
        });
      },
    );
  }
}
