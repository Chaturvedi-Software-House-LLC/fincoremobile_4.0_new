/// Shared, branded HTML template for every support-request email this app
/// sends via SMTP (the Help screen's message form and the AI Assistant's
/// "Contact Support Team" card) - matches the look of the password-reset/
/// OTP emails already sent from Login.dart: logo header, brand-teal accent,
/// a clean details table, and the same footer/copyright block, rather than
/// each screen inventing its own plain, unstyled dump of fields.
/// Escapes characters that would otherwise break the surrounding HTML if
/// present in user-typed input (name, email, message, etc.) - e.g. a
/// message containing "<" or "&" could otherwise mangle the layout or get
/// interpreted as markup.
String _escapeHtml(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String buildSupportEmailHtml({
  required String title,
  required String subtitle,
  required List<MapEntry<String, String>> details,
  required String message,
}) {
  String row(String label, String value) => '''
      <tr>
        <td style="padding: 6px 0; font-family: Arial, sans-serif; font-size: 12px; color: #888; width: 140px; vertical-align: top;">${_escapeHtml(label)}</td>
        <td style="padding: 6px 0; font-family: Arial, sans-serif; font-size: 13px; color: #333; vertical-align: top;">${_escapeHtml(value)}</td>
      </tr>
      ''';

  return '''
    <div style="border: 1px solid #ccc; padding: 30px; margin: 0 20px; text-align: center;">
      <a href="https://tallyuae.ae/">
        <img src="https://mobile.chaturvedigroup.com/fincore_logo/tally_1.png" alt="Fincore Go" style="width: 150px; height: auto; margin-bottom: 10px;">
      </a>

      <div style="text-align: center;">
        <p style="font-size: 16px; font-family: Arial, sans-serif; color: #30D5C8; font-weight: bold; margin-bottom: 4px;">${_escapeHtml(title)}</p>
        <p style="font-size: 12px; font-family: Arial, sans-serif; color: #888; margin-top: 0;">${_escapeHtml(subtitle)}</p>
      </div>

      <br>

      <table style="width: 100%; border-collapse: collapse; text-align: left;">
        ${details.map((d) => row(d.key, d.value)).join()}
      </table>

      <br>

      <div style="text-align: left;">
        <p style="font-size: 12px; font-family: Arial, sans-serif; color: #888; margin-bottom: 6px;">Message</p>
        <div style="background-color: #f5f6fb; border-radius: 6px; padding: 14px; text-align: left; font-family: Arial, sans-serif; font-size: 13px; color: #333; line-height: 1.5;">
          ${_escapeHtml(message).replaceAll('\n', '<br>')}
        </div>
      </div>

      <br>

      <div style="text-align: start;">
        <p style="color: #999999; font-style: italic; font-size: 12px;">This is a system generated email. Do not reply directly to this address.</p>
      </div>

      <div style="text-align: start; border-top: 1px solid #ccc; padding-top: 10px;">
        <p style="font-size: 10px; font-family: Arial, sans-serif; color: #a3a2a2;">&copy; 2023-2026 Chaturvedi Software House LLC. All Rights Reserved</p>
        <p style="font-size: 10px; font-family: Arial, sans-serif; color: #a3a2a2; padding-top: 0px;">513 Al Khaleej Center Bur Dubai, Dubai United Arab Emirates, +97143258361</p>
      </div>
    </div>
    ''';
}
