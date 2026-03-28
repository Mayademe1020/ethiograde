import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/locale_provider.dart';
import '../../services/settings_provider.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final settings = context.watch<SettingsProvider>();
    final isSchoolMode = settings.isSchoolMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAm ? 'የደንበኝነት' : 'Subscription'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode toggle
            Text(
              isAm ? 'ሁኔታ ይምረጡ' : 'Choose Your Mode',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Individual mode
            _ModeCard(
              isSelected: !isSchoolMode,
              icon: Icons.person,
              titleEn: 'Individual Teacher',
              titleAm: 'የግል መምህር',
              featuresEn: [
                'Single teacher grading',
                'Up to 200 students',
                'All scanning features',
                'PDF reports',
                'WhatsApp sharing',
              ],
              featuresAm: [
                'አንድ መምህር መለኪያ',
                'እስከ 200 ተማሪዎች',
                'ሁሉም ማሳሰቢያ ባህሪያት',
                'PDF ሪፖርቶች',
                'WhatsApp ማጋራት',
              ],
              price: isAm ? 'ነጻ' : 'Free',
              priceDetail: isAm ? 'ከቴሌብር ጋር' : 'with Telebirr upgrade',
              isAmharic: isAm,
              onTap: () => settings.setSubscriptionMode('individual'),
            ),
            const SizedBox(height: 16),

            // School admin mode
            _ModeCard(
              isSelected: isSchoolMode,
              icon: Icons.business,
              titleEn: 'School Admin',
              titleAm: 'የት/ቤት አስተዳዳሪ',
              featuresEn: [
                'Manage multiple teachers',
                'Unlimited students',
                'School-wide analytics',
                'Centralized data control',
                'Bulk report generation',
                'Priority support',
              ],
              featuresAm: [
                'ብዙ መምህራንን ማስተዳደር',
                'ያልተገደበ ተማሪዎች',
                'የት/ቤት ስፋት ትንተና',
                'ማዕከላዊ መረጃ ቁጥጥር',
                'የጅምላ ሪፖርት ፍጠር',
                'ቅድሚያ ድጋፍ',
              ],
              price: isAm ? 'ዋጋ' : 'Contact Us',
              priceDetail: isAm ? 'ለት/ቤቶች' : 'For schools',
              isAmharic: isAm,
              onTap: () => settings.setSubscriptionMode('school'),
            ),

            const SizedBox(height: 24),

            // Current status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryGreen.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSchoolMode ? Icons.business : Icons.person,
                    color: AppTheme.primaryGreen,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAm ? 'የአሁኑ ሁኔታ' : 'Current Mode',
                          style: TextStyle(
                            color: AppTheme.lightText,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          isSchoolMode
                              ? (isAm ? 'የት/ቤት አስተዳዳሪ' : 'School Admin')
                              : (isAm ? 'የግል መምህር' : 'Individual Teacher'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // School admin features (visible only in school mode)
            if (isSchoolMode) ...[
              Text(
                isAm ? 'የት/ቤት አስተዳዳሪ ባህሪያት' : 'School Admin Features',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _AdminTile(
                icon: Icons.person_add,
                title: isAm ? 'መምህራን ያክሉ' : 'Add Teachers',
                subtitle: isAm
                    ? 'የት/ቤት መምህራን ይመዝግቡ'
                    : 'Register school teachers',
                onTap: () => _showAddTeacherDialog(context, isAm),
              ),
              _AdminTile(
                icon: Icons.lock,
                title: isAm ? 'መረጃ ቁጥጥር' : 'Data Control',
                subtitle: isAm
                    ? 'ሁሉም መረጃ በት/ቤት ውስጥ'
                    : 'All data stays in school',
                onTap: () {},
              ),
              _AdminTile(
                icon: Icons.payment,
                title: isAm ? 'ክፍያ' : 'Payment',
                subtitle: isAm ? 'በቴሌብር ይክፈሉ' : 'Pay with Telebirr',
                onTap: () => _showPaymentInfo(context, isAm),
              ),
            ],

            // Individual features
            if (!isSchoolMode) ...[
              Text(
                isAm ? 'የግል መምህር ባህሪያት' : 'Individual Features',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _AdminTile(
                icon: Icons.upgrade,
                title: isAm ? 'ወደ ክፍያ ያሻሽሉ' : 'Upgrade to Paid',
                subtitle: isAm
                    ? 'ቴሌብር በመጠቀም ያሻሽሉ'
                    : 'Upgrade via Telebirr',
                onTap: () => _showPaymentInfo(context, isAm),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddTeacherDialog(BuildContext context, bool isAm) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isAm ? 'መምህር ጨምር' : 'Add Teacher'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: isAm ? 'የመምህር ስም' : 'Teacher Name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: InputDecoration(
                labelText: isAm ? 'ስልክ' : 'Phone',
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(isAm ? 'ሰርዝ' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Add teacher to school
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isAm ? 'መምህር ተመዝግቧል' : 'Teacher added',
                  ),
                ),
              );
            },
            child: Text(isAm ? 'አክል' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _showPaymentInfo(BuildContext context, bool isAm) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isAm ? 'በቴሌብር ይክፈሉ' : 'Pay with Telebirr'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phone_android,
              size: 48,
              color: AppTheme.primaryGreen,
            ),
            const SizedBox(height: 16),
            Text(
              isAm
                  ? 'ቴሌብር ክፍያ በቅርቡ ይመጣል'
                  : 'Telebirr payment coming soon',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isAm
                  ? 'እስካሁን ነጻ ሁኔታን ይጠቀሙ'
                  : 'For now, enjoy the free tier',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.lightText, fontSize: 12),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(c),
            child: Text(isAm ? 'እሺ' : 'OK'),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final bool isSelected;
  final IconData icon;
  final String titleEn;
  final String titleAm;
  final List<String> featuresEn;
  final List<String> featuresAm;
  final String price;
  final String priceDetail;
  final bool isAmharic;
  final VoidCallback onTap;

  const _ModeCard({
    required this.isSelected,
    required this.icon,
    required this.titleEn,
    required this.titleAm,
    required this.featuresEn,
    required this.featuresAm,
    required this.price,
    required this.priceDetail,
    required this.isAmharic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final features = isAmharic ? featuresAm : featuresEn;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryGreen.withOpacity(0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryGreen.withOpacity(0.15)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected
                        ? AppTheme.primaryGreen
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAmharic ? titleAm : titleEn,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '$price $priceDetail',
                        style: TextStyle(
                          color: AppTheme.lightText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: AppTheme.primaryGreen,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 16, color: AppTheme.primaryGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(f, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryGreen),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
