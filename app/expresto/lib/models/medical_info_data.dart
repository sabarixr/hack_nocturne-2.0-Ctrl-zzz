class MedicalInfoData {
  final String bloodType;
  final String bloodSign;
  final String height;
  final String weight;
  final DateTime? dateOfBirth;

  const MedicalInfoData({
    this.bloodType = 'O',
    this.bloodSign = '+',
    this.height = '170 cm',
    this.weight = '65 kg',
    this.dateOfBirth,
  });

  MedicalInfoData copyWith({
    String? bloodType,
    String? bloodSign,
    String? height,
    String? weight,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
  }) {
    return MedicalInfoData(
      bloodType: bloodType ?? this.bloodType,
      bloodSign: bloodSign ?? this.bloodSign,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
    );
  }
}
