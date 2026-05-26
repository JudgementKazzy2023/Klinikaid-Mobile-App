import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _acceptedPrivacy = false;
  bool _acceptedTerms = false;

  void _submit() async {
    if (_acceptedPrivacy && _acceptedTerms) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.acceptConsent();
      // Redirection is handled automatically by GoRouter via AuthProvider state changes
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Header
              const Icon(
                Icons.privacy_tip_outlined,
                size: 40,
                color: Color(0xFF00C1D4),
              ),
              const SizedBox(height: 16),
              const Text(
                'Data Privacy Consent',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Republic Act No. 10173 (Philippine Data Privacy Act)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white30,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),

              // Consent text scrollable block
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F131D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1C2230)),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Introduction & Processing Scope',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'KlinikAid Mobile ("App") is a patient-facing clinical integration system. To digitize your intake records and clinical document submissions, we require your explicit permission to collect and process your personal and sensitive health data.',
                              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                            ),
                            SizedBox(height: 16),
                            Text(
                              '1. Collected Information',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'We process:\n'
                              '• Personal Identity: Name, contact details, date of birth, gender, and address.\n'
                              '• Health Data: Laboratory results, diagnostic files, and doctor referrals.\n'
                              '• Chatbot Logs: Administrative queries and message histories.',
                              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                            ),
                            SizedBox(height: 16),
                            Text(
                              '2. Usage & Storage Boundaries',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Your information is stored in a shared secure cloud database (Supabase) accessed exclusively by authorized clinic personnel at Bloodcare Medical Laboratory.\n\n'
                              'All chatbot transactions are processed on secure servers. Under no circumstances is clinical diagnosis generated by the AI; all medical evaluations stay with clinic staff.',
                              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                            ),
                            SizedBox(height: 16),
                            Text(
                              '3. Your Rights Under RA 10173',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'You retain the right to:\n'
                              '• Access, inspect, and update your patient record.\n'
                              '• Request restriction or deletion of your data.\n'
                              '• File a complaint with the National Privacy Commission.',
                              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Checkbox 1: Privacy
              Theme(
                data: ThemeData(unselectedWidgetColor: Colors.white30),
                child: CheckboxListTile(
                  value: _acceptedPrivacy,
                  onChanged: (val) => setState(() => _acceptedPrivacy = val ?? false),
                  title: const Text(
                    'I read and accept the Data Privacy Statement under RA 10173.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: const Color(0xFF2E5BFF),
                  contentPadding: EdgeInsets.zero,
                ),
              ),

              // Checkbox 2: Terms
              Theme(
                data: ThemeData(unselectedWidgetColor: Colors.white30),
                child: CheckboxListTile(
                  value: _acceptedTerms,
                  onChanged: (val) => setState(() => _acceptedTerms = val ?? false),
                  title: const Text(
                    'I agree to the Terms of Service of KlinikAid.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: const Color(0xFF2E5BFF),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 20),

              // Error banner if any
              if (authProvider.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    authProvider.errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Accept Button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: (_acceptedPrivacy && _acceptedTerms && !authProvider.isLoading)
                      ? _submit
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E5BFF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF2E5BFF).withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                  child: authProvider.isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Accept & Continue',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Sign Out option
              TextButton(
                onPressed: () => authProvider.signOut(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                ),
                child: const Text('Cancel & Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
