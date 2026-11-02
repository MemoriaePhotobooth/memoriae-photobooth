/// The studio's official payment account shown in the receipt-upload modal.
/// The QR image (assets/images/instapay_qr.jpg) belongs to this account, so
/// the name and number are kept next to it here and always shown together.
class StudioPaymentAccount {
  StudioPaymentAccount._();

  static const String qrAsset = 'assets/images/instapay_qr.jpg';
  static const String accountName = 'Mary Lyn T. Marbella';
  static const String accountNumber = '09754269253';

  /// "0975 426 9253" — easier to read and to type.
  static String get formattedNumber =>
      '${accountNumber.substring(0, 4)} ${accountNumber.substring(4, 7)} ${accountNumber.substring(7)}';
}
