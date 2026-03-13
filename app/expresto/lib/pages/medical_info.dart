import 'package:expresto/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

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

class MedicalInfoPage extends StatefulWidget {
  const MedicalInfoPage({super.key, required this.initialData});

  final MedicalInfoData initialData;

  @override
  State<MedicalInfoPage> createState() => _MedicalInfoPageState();
}

class _MedicalInfoPageState extends State<MedicalInfoPage> {
  final List<String> bloodTypes = ['A', 'B', 'AB', 'O'];
  final List<String> signs = ['+', '-'];

  late MedicalInfoData data;

  @override
  void initState() {
    super.initState();
    data = widget.initialData;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSectionHeader('MEDICAL INFO'),
                  _buildBloodGroupCard(),
                  const SizedBox(height: 12),
                  _buildEditableTile(
                    label: 'Height',
                    value: data.height,
                    onTap: () => _editTextValue(
                      title: 'Edit Height',
                      initialValue: data.height,
                      onSave: (value) {
                        data = data.copyWith(height: value);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildEditableTile(
                    label: 'Weight',
                    value: data.weight,
                    onTap: () => _editTextValue(
                      title: 'Edit Weight',
                      initialValue: data.weight,
                      onSave: (value) {
                        data = data.copyWith(weight: value);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildEditableTile(
                    label: 'Date of Birth',
                    value: _formatDob(data.dateOfBirth),
                    onTap: _pickDateOfBirth,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, data),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.shellBorder),
                ),
                child: const Icon(
                  Icons.medical_information_outlined,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Medical Info',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context, data),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.shellBorder),
              ),
              child: const Icon(
                Icons.check,
                color: AppColors.textMuted,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          letterSpacing: 1.5,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildBloodGroupCard() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Blood Group',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              Theme(
                data: Theme.of(context).copyWith(canvasColor: AppColors.panel),
                child: DropdownButton<String>(
                  value: data.bloodType,
                  dropdownColor: AppColors.panel,
                  underline: const SizedBox(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  iconEnabledColor: AppColors.textMuted,
                  items: bloodTypes
                      .map(
                        (e) =>
                            DropdownMenuItem<String>(value: e, child: Text(e)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      data = data.copyWith(bloodType: value);
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Theme(
                data: Theme.of(context).copyWith(canvasColor: AppColors.panel),
                child: DropdownButton<String>(
                  value: data.bloodSign,
                  dropdownColor: AppColors.panel,
                  underline: const SizedBox(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  iconEnabledColor: AppColors.textMuted,
                  items: signs
                      .map(
                        (e) =>
                            DropdownMenuItem<String>(value: e, child: Text(e)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      data = data.copyWith(bloodSign: value);
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditableTile({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.shellBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTextValue({
    required String title,
    required String initialValue,
    required ValueChanged<String> onSave,
  }) async {
    final controller = TextEditingController(text: initialValue);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            title,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Value',
              labelStyle: TextStyle(color: AppColors.textMuted),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                setState(() {
                  onSave(value);
                });
                Navigator.pop(context);
              },
              child: const Text(
                'Save',
                style: TextStyle(
                  color: AppColors.blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initialDate = data.dateOfBirth ?? DateTime(now.year - 20, 1, 1);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              surface: AppColors.panel,
              primary: AppColors.blue,
              onSurface: AppColors.textPrimary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null) return;

    setState(() {
      data = data.copyWith(dateOfBirth: pickedDate);
    });
  }

  String _formatDob(DateTime? dateOfBirth) {
    if (dateOfBirth == null) {
      return 'Set';
    }

    final month = dateOfBirth.month.toString().padLeft(2, '0');
    final day = dateOfBirth.day.toString().padLeft(2, '0');
    return '$day/$month/${dateOfBirth.year}';
  }
}
