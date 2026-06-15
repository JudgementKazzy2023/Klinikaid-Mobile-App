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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Header
              Icon(
                Icons.privacy_tip_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Data Privacy Consent',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Republic Act No. 10173 (Philippine Data Privacy Act)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Introduction & Processing Scope',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'KlinikAid Mobile ("App") is a patient-facing clinical integration system. To digitize your intake records and clinical document submissions, we require your explicit permission to collect and process your personal and sensitive health data.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13, height: 1.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '1. Collected Information',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'We process:\n'
                              '• Personal Identity: Name, contact details, date of birth, gender, and address.\n'
                              '• Health Data: Laboratory results, diagnostic files, and doctor referrals.\n'
                              '• Chatbot Logs: Administrative queries and message histories.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13, height: 1.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '2. Usage & Storage Boundaries',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your information is stored in a shared secure cloud database (Supabase) accessed exclusively by authorized clinic personnel at Bloodcare Medical Laboratory.\n\n'
                              'All chatbot transactions are processed on secure servers. Under no circumstances is clinical diagnosis generated by the AI; all medical evaluations stay with clinic staff.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13, height: 1.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '3. Your Rights Under RA 10173',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You retain the right to:\n'
                              '• Access, inspect, and update your patient record.\n'
                              '• Request restriction or deletion of your data.\n'
                              '• File a complaint with the National Privacy Commission.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13, height: 1.5),
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
              CheckboxListTile(
                value: _acceptedPrivacy,
                onChanged: (val) => setState(() => _acceptedPrivacy = val ?? false),
                title: Text(
                  'I read and accept the Data Privacy Statement under RA 10173.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).colorScheme.primary,
                contentPadding: EdgeInsets.zero,
              ),

              // Checkbox 2: Terms
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: (val) => setState(() => _acceptedTerms = val ?? false),
                title: Text(
                  'I agree to the Terms of Service of KlinikAid.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).colorScheme.primary,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),

              // Error banner if any
              if (authProvider.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    authProvider.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    disabledBackgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                  child: authProvider.isLoading
                      ? SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.onPrimary),
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
                  foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
