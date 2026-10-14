import 'package:inventory_app/domain/models/models.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchCustomerContact(Customer customer) async {
  final uri = customer.primaryContact?.uri;
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> launchContact(CustomerContact contact) async {
  final uri = contact.uri;
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Open a contact channel with a prefilled receipt / message body.
Future<void> launchContactWithMessage(
  CustomerContact contact,
  String message, {
  String subject = 'Receipt',
}) async {
  Uri? uri;
  switch (contact.kind) {
    case CustomerContactKind.email:
      uri = Uri(
        scheme: 'mailto',
        path: contact.raw.trim(),
        // Percent-encode (%20) – queryParameters would turn spaces into '+',
        // which iOS Mail / Messages show literally.
        query: 'subject=${Uri.encodeComponent(subject)}'
            '&body=${Uri.encodeComponent(message)}',
      );
    case CustomerContactKind.whatsapp:
      final digits = contact.raw.replaceAll(RegExp(r'[^\d+]'), '');
      uri = Uri.parse(
        'https://wa.me/${Uri.encodeComponent(digits)}'
        '?text=${Uri.encodeComponent(message)}',
      );
    case CustomerContactKind.phone:
      final digits = contact.raw.replaceAll(RegExp(r'[^\d+]'), '');
      uri = Uri(
        scheme: 'sms',
        path: digits,
        query: 'body=${Uri.encodeComponent(message)}',
      );
    default:
      uri = contact.uri;
  }
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
