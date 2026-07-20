void main() {
  final phoneReg = RegExp(r'^(09|\+639)\d{9}$');
  final emailReg = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  final phone = '09999999999';
  final email = 'test5@test.com';

  print('Phone match: ${phoneReg.hasMatch(phone)}');
  print('Email match: ${emailReg.hasMatch(email)}');
}
