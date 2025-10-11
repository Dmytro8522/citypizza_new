import 'package:flutter/material.dart';

class NoInternetWidget extends StatelessWidget {
  final VoidCallback onRetry;
  final String? errorText;

  const NoInternetWidget({Key? key, required this.onRetry, this.errorText}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, color: Colors.orangeAccent, size: 50),
          const SizedBox(height: 10),
          Text(
            errorText ?? 'Keine Internetverbindung',
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Erneut versuchen'),
          ),
        ],
      ),
    );
  }
}
